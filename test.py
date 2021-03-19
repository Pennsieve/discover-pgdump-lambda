import os
import subprocess
import time
import pytest
import boto3
from sqlalchemy import create_engine
from sqlalchemy.engine.url import URL
from sqlalchemy.exc import ProgrammingError
from botocore.exceptions import BotoCoreError

from main import lambda_handler, PG_PATH, PSQL, POSTGRES_PASSWORD_SSM_KEY, S3_URL, SSM_URL

# Shared Postgres credentials
PG_USER = 'postgres'
PG_PASSWORD = 'password'
PG_DATABASE = 'postgres'
PG_PORT = '5432'

# Connection to Pennsieve Postgres DB
PG_HOST = 'pennsievedb'

# Connection to empty Postgres DB
PG_HOST_EMPTY = 'emptydb'

ORGANIZATION_SCHEMA = 1
S3_BUCKET = 'test-bucket'
S3_KEY = 'dump-file.sql'
DUMP = 'dump.sql'


def pg_ready(host):
    try:
        subprocess.check_output([
            PSQL,
            '--host', host,
            '--port', PG_PORT,
            '--user', PG_USER,
            '--dbname', PG_DATABASE,
            '-c', "SELECT 1;"
        ], env={
            'PGPASSWORD': PG_PASSWORD,
            'LD_LIBRARY_PATH': PG_PATH
        })
        return True
    except subprocess.CalledProcessError:
        return False


def s3_ready(s3):
    try:
        list(s3.buckets.all())
        return True
    except BotoCoreError:
        return False


def ssm_ready(ssm):
    try:
        list(ssm.describe_parameters())
        return True
    except BotoCoreError:
        return False


def test_main():

    while not (pg_ready(PG_HOST) and pg_ready(PG_HOST_EMPTY)):
        print("Waiting for Postgres containers...")
        time.sleep(1)

    s3 = boto3.resource('s3', endpoint_url=S3_URL)
    while not (s3_ready(s3)):
        print("Waiting for S3 container...")
        time.sleep(1)

    ssm = boto3.client('ssm', endpoint_url=SSM_URL)
    while not (ssm_ready(ssm)):
        print("Waiting for SSM container...")
        time.sleep(1)

    bucket = s3.create_bucket(Bucket=S3_BUCKET)

    ssm.put_parameter(Name=POSTGRES_PASSWORD_SSM_KEY,
                      Value='password',
                      Type='SecureString')

    os.environ.update({
        'POSTGRES_HOST': PG_HOST,
        'POSTGRES_PORT': PG_PORT,
        'POSTGRES_USER': PG_USER,
        'POSTGRES_DATABASE': PG_DATABASE,
        'S3_BUCKET': S3_BUCKET,
    })

    lambda_handler({
        'organization_schema': ORGANIZATION_SCHEMA,
        's3_key': S3_KEY,
    }, {})

    bucket.download_file(S3_KEY, DUMP)

    # Import the dump file into a clean database
    # There is not an easy way to import a whole file using SqlAlchemy, so use psql
    subprocess.check_output([
        PSQL,
        '--host', PG_HOST_EMPTY,
        '--port', PG_PORT,
        '--user', PG_USER,
        '--dbname', PG_DATABASE,
        '--file', DUMP,
        '-v', 'ON_ERROR_STOP=1'
    ], env={
        'PGPASSWORD': PG_PASSWORD,
        'LD_LIBRARY_PATH': PG_PATH
    })

    # Connect to the new database
    engine = create_engine(URL(
        drivername='postgresql',
        database=PG_DATABASE,
        username=PG_USER,
        password=PG_PASSWORD,
        host=PG_HOST_EMPTY,
        port=PG_PORT))

    # Does the pennsievedb seed data from pennsieve-api/local-seed.sql look good?
    with engine.connect() as conn:
        rows = conn.execute(f'SELECT * FROM "{ORGANIZATION_SCHEMA}".datasets;').fetchall()
        assert len(rows) == 1
        assert rows[0]['name'] == 'Pennsieve Dataset'
        assert rows[0]['node_id'] == 'N:dataset:c0f0db41-c7cb-4fb5-98b4-e90791f8a975'

        with pytest.raises(ProgrammingError):
            conn.execute('SELECT * FROM "2".datasets;').fetchall()

        rows = conn.execute(f'SELECT * FROM "{ORGANIZATION_SCHEMA}".files;').fetchall()
        assert len(rows) == 0
