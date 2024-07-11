FROM --platform=linux/amd64 public.ecr.aws/lambda/python:3.11 as build

RUN yum -y update && yum -y install \
    gcc \
    gzip.x86_64 \
    libicu-devel \
    make \
    openssl-devel \
    readline-devel \
    tar.x86_64 \
    unzip.x86_64 \
    wget \
    zip.x86_64 \
    zlib-devel

WORKDIR /tmp
RUN wget https://ftp.postgresql.org/pub/source/v16.1/postgresql-16.1.tar.gz
RUN tar -xvzf postgresql-16.1.tar.gz

WORKDIR /tmp/postgresql-16.1
RUN ./configure --bindir=/usr/bin --with-openssl

RUN make -C src/bin install
RUN make -C src/include install
RUN make -C src/interfaces install

RUN python3.11 -m venv /opt/venv
RUN source /opt/venv/bin/activate && \
    pip3.11 install --upgrade pip && \
    pip3.11 install boto3==1.34.140

RUN mkdir -p /lambda/bin
WORKDIR /lambda

# Copy required Postgres binaries and libraries into the Lambda directory
RUN cp \
    /usr/bin/pg_dump \
    /usr/bin/psql \
    /usr/local/pgsql/lib/libpq.so.5 \
    /usr/local/pgsql/lib/libpq.so.5.16 \
    ./bin

COPY requirements.txt .
RUN pip3.11 install -r requirements.txt --target .
RUN find . -name "*.pyc" -delete

COPY main.py .
RUN zip -r lambda.zip .

#####################################

FROM public.ecr.aws/lambda/python:3.11 as test

RUN yum -y update && yum -y install \
    unzip.x86_64

RUN python3.11 -m venv /opt/venv

RUN source /opt/venv/bin/activate && \
    pip3.11 install --upgrade pip && \
    pip3.11 install boto3==1.34.140

RUN mkdir -p lambda/bin
WORKDIR lambda

COPY requirements-test.txt .
RUN pip install -r requirements-test.txt --target .

COPY --from=build lambda/lambda.zip .
RUN unzip -o lambda.zip

COPY test.py .

CMD ["python3.11", "-m", "pytest", "-s", "test.py"]
