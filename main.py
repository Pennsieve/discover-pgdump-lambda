import os
import subprocess
import boto3
import structlog

PG_PATH = 'bin'
PG_DUMP = f'{PG_PATH}/pg_dump'
PSQL = f'{PG_PATH}/psql'


# Configure JSON logs in a format that ELK can understand
# --------------------------------------------------

def rewrite_event_to_message(logger, name, event_dict):
    """
    Rewrite the default structlog `event` to a `message`.
    """
    event = event_dict.pop('event', None)
    if event is not None:
        event_dict['message'] = event
    return event_dict


def add_log_level(logger, name, event_dict):
    event_dict['log_level'] = name.upper()
    return event_dict


structlog.configure(
    processors=[
        rewrite_event_to_message,
        add_log_level,
        structlog.processors.format_exc_info,
        structlog.processors.TimeStamper(fmt='iso'),
        structlog.processors.JSONRenderer()])


# Main lambda handler
# --------------------------------------------------

ENVIRONMENT = os.environ['ENVIRONMENT']
SERVICE_NAME = os.environ['SERVICE_NAME']
TIER = os.environ['TIER']
FULL_SERVICE_NAME = f'{SERVICE_NAME}-{TIER}'

if ENVIRONMENT == 'local':
    S3_URL = 'http://localstack:4566'
    SSM_URL = 'http://localstack:4566'
else:
    S3_URL = None
    SSM_URL = None

POSTGRES_PASSWORD_SSM_KEY = f'/{ENVIRONMENT}/{SERVICE_NAME}-{TIER}/pennsieve-postgres-password'


def lambda_handler(event, context):

    # Create basic Pennsieve log context
    log = structlog.get_logger()
    log = log.bind(**{'class': f'{lambda_handler.__module__}.{lambda_handler.__name__}'})
    log = log.bind(pennsieve={'service_name': FULL_SERVICE_NAME})

    try:
        log.info('Reading environment')
        pg_user     = os.environ['POSTGRES_USER']
        pg_database = os.environ['POSTGRES_DATABASE']
        pg_port     = os.environ['POSTGRES_PORT']
        pg_host     = os.environ['POSTGRES_HOST']
        s3_bucket   = os.environ['S3_BUCKET']

        log.info(f"POSTGRES_HOST: {pg_host}")
        log.info(f"S3_BUCKET: {s3_bucket}")

        log.info('Parsing event')
        organization_schema = event['organization_schema']
        s3_key = event['s3_key']

        # Rebind Pennsieve log context with event info
        log = log.bind(
            pennsieve={
                'service_name': FULL_SERVICE_NAME,
                'organization_schema': organization_schema,
                's3_bucket': s3_bucket,
                's3_key': s3_key,
            },
        )

        # Get Postgres password directly from SSM
        ssm = boto3.client('ssm', endpoint_url=SSM_URL)
        pg_password = ssm.get_parameter(
            Name=POSTGRES_PASSWORD_SSM_KEY, WithDecryption=True
        )['Parameter']['Value']

        log.info('Starting lambda')
        s3_client = boto3.client('s3', endpoint_url=S3_URL)

        log.info('Dumping org schema')
        process = subprocess.Popen([
            PG_DUMP,
            '--schema', str(organization_schema),
            '--host', pg_host,
            '--port', pg_port,
            '--user', pg_user,
            '--dbname', pg_database,

            # Don't export `GRANT` and `ALTER TABLE .. OWNER TO` statements.
            # These cause error log messages when loading the dump, eg:
            # `ERROR: role "bfroot" does not exist`
            '--no-owner',
            '--no-privileges',

            # Only export table definitions and rows, excluding all constraints.
            # Because the database is read-only we don't need constraints.
            # This fixes errors when loading tables that reference the undumped
            # `pennsieve.users` table: `ERROR:  schema "pennsieve" does not exist`.
            '--section', 'pre-data',
            '--section', 'data',
        ], env={
            'PGPASSWORD': pg_password,
            'LD_LIBRARY_PATH': PG_PATH
        },
           stdout=subprocess.PIPE,
           stderr=subprocess.PIPE)

        log.info('Streaming SQL to S3')
        s3_client.upload_fileobj(process.stdout, s3_bucket, s3_key)

        process.wait()
        if process.returncode != 0:
            raise Exception(process.stderr.read())

    except Exception as e:
        log.error(e, exc_info=True)
        raise
