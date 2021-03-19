FROM amazonlinux:latest as build

# amazon-linux-extras does not support Postgres 12 yet, install from Postgres directly
RUN echo -e '\n\
[postgresql12]\n\
name=PostgreSQL 12 for RHEL/CentOS 7 - x86_64\n\
baseurl=https://download.postgresql.org/pub/repos/yum/12/redhat/rhel-7-x86_64\n\
enabled=1\n\
gpgcheck=0'\
>> /etc/yum.repos.d/pgdg.repo && cat /etc/yum.repos.d/pgdg.repo && yum makecache

RUN yum -y install git \
    python37 \
    python37-pip \
    zip \
    unzip \
    postgresql12.x86_64 \
    postgresql12-libs.x86_64 \
    && yum clean all

RUN python3 -m pip install --upgrade pip \
    && python3 -m pip install boto3==1.9.42

RUN mkdir lambda lambda/bin
WORKDIR lambda

# # Copy required Postgres binaries and libraries into the Lambda directory
RUN cp \
    /usr/pgsql-12/bin/pg_dump \
    /usr/pgsql-12/bin/psql \
    /usr/pgsql-12/lib/libpq.so.5 \
    /usr/pgsql-12/lib/libpq.so.5.12 \
    ./bin

COPY requirements.txt .
RUN python3 -m pip install -r requirements.txt --target .
RUN find . -name "*.pyc" -delete

COPY main.py .
RUN zip -r lambda.zip .

FROM amazonlinux:latest as test

RUN yum -y install git \
    python37 \
    python37-pip \
    zip \
    unzip \
    && yum clean all

RUN python3 -m pip install --upgrade pip \
    && python3 -m pip install boto3==1.9.42

RUN mkdir lambda
WORKDIR lambda

COPY requirements-test.txt .
RUN python3 -m pip install -r requirements-test.txt

COPY --from=build lambda/lambda.zip .
RUN unzip lambda.zip

COPY test.py .

CMD ["python3", "-m", "pytest", "-s", "test.py"]
