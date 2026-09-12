# T1 CloudWatch alarms (standard sets from
# pennsieve-infra-dashboard/docs/alarm-coverage-plan.md). No alarm_actions
# yet: alarms surface on the infra dashboard and console without paging.
module "service_alarms" {
  source = "git@github.com:Pennsieve/terraform-modules.git//service-alarms"

  environment_name = var.environment_name
  service_name     = var.service_name

  lambdas = {
    pgdump = {
      function_name   = aws_lambda_function.discover_pgdump_lambda_function.function_name
      timeout_seconds = aws_lambda_function.discover_pgdump_lambda_function.timeout
    }
  }
}
