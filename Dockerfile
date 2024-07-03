FROM postgres:16-alpine as build

RUN apk update && apk add --no-cache \
    libffi-dev \
    gcc \
    musl-dev \
    git \
    python3 \
    python3-dev \
    py3-pip \
    zip \
    unzip

RUN python3 -m venv /opt/venv

ENV PATH="/opt/venv/bin:$PATH"

RUN . /opt/venv/bin/activate && \
    pip install --upgrade pip && \
    pip install boto3==1.9.42

RUN mkdir lambda lambda/bin
WORKDIR lambda

# Copy required Postgres binaries and libraries into the Lambda directory
RUN cp \
    /usr/local/bin/pg_dump \
    /usr/local/bin/psql \
    /usr/local/lib/libpq.so.5 \
    /usr/local/lib/libpq.so.5.16 \
    ./bin
 
COPY requirements.txt .
RUN pip install -r requirements.txt --target .
RUN find . -name "*.pyc" -delete

COPY main.py .
RUN zip -r lambda.zip .

FROM postgres:16-alpine as test

RUN apk update && apk add --no-cache \
    libffi-dev \
    gcc \
    musl-dev \
    git \
    python3 \
    python3-dev \
    py3-pip \
    zip \
    unzip

RUN python3 -m venv /opt/venv

ENV PATH="/opt/venv/bin:$PATH"

RUN . /opt/venv/bin/activate && \
    pip install --upgrade pip && \
    pip install boto3==1.9.42

RUN mkdir lambda lambda/bin
WORKDIR lambda

COPY requirements-test.txt .
RUN pip install -r requirements-test.txt --target .

COPY --from=build lambda/lambda.zip .
RUN unzip -o lambda.zip

COPY test.py .

CMD ["python3", "-m", "pytest", "-s", "test.py"]
