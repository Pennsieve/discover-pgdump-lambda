# OUTPUT LAMBDA ARN
output "lambda_function_arn" {
  value = aws_lambda_function.discover_pgdump_lambda_function.arn
}
