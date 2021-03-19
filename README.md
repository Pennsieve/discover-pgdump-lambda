## discover-pgdump-lambda

Dump an organization schema from the main Postgres database and stream it to S3.

### Building

Run `make package` to build the Lambda and bundle the necessary Postgres binaries in a Docker.

### Testing

Run `make test` to test the Lambda.
