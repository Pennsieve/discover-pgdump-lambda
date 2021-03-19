// Create Lambda function
resource "aws_lambda_function" "discover_pgdump_lambda_function" {
  description       = var.description
  function_name     = "${var.environment_name}-${var.service_name}-${var.tier}-lambda-${data.terraform_remote_state.vpc.outputs.aws_region_shortname}"
  handler           = "main.lambda_handler"
  runtime           = var.runtime
  role              = aws_iam_role.lambda_iam_role.arn
  s3_bucket         = data.aws_s3_bucket_object.s3_bucket_object.bucket
  s3_key            = data.aws_s3_bucket_object.s3_bucket_object.key
  s3_object_version = data.aws_s3_bucket_object.s3_bucket_object.version_id
  timeout           = var.timeout
  memory_size       = var.memory_size

  vpc_config {
    subnet_ids         = tolist(data.terraform_remote_state.vpc.outputs.private_subnet_ids)
    security_group_ids = [data.terraform_remote_state.platform_infrastructure.outputs.discover_pgdump_security_group_id]
  }

  environment {
    variables = {
      VERSION           = var.version_number
      ENVIRONMENT       = var.environment_name
      SERVICE_NAME      = var.service_name
      TIER              = var.tier
      POSTGRES_HOST     = aws_ssm_parameter.pennsieve_postgres_host.value
      POSTGRES_PORT     = aws_ssm_parameter.pennsieve_postgres_port.value
      POSTGRES_DATABASE = aws_ssm_parameter.pennsieve_postgres_database.value
      POSTGRES_USER     = aws_ssm_parameter.pennsieve_postgres_user.value
      S3_BUCKET         = data.terraform_remote_state.platform_infrastructure.outputs.discover_pgdump_bucket_id
    }
  }
}
