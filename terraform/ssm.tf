resource "aws_ssm_parameter" "pennsieve_postgres_database" {
  name  = "/${var.environment_name}/${var.service_name}-${var.tier}/pennsieve-postgres-database"
  type  = "String"
  value = var.pennsieve_postgres_database
}

resource "aws_ssm_parameter" "pennsieve_postgres_host" {
  name  = "/${var.environment_name}/${var.service_name}-${var.tier}/pennsieve-postgres-host"
  type  = "String"
  value = data.terraform_remote_state.pennsieve_postgres.outputs.master_fqdn
}

resource "aws_ssm_parameter" "pennsieve_postgres_port" {
  name  = "/${var.environment_name}/${var.service_name}-${var.tier}/pennsieve-postgres-port"
  type  = "String"
  value = data.terraform_remote_state.pennsieve_postgres.outputs.master_port
}

resource "aws_ssm_parameter" "pennsieve_postgres_user" {
  name  = "/${var.environment_name}/${var.service_name}-${var.tier}/pennsieve-postgres-user"
  type  = "String"
  value = "${var.environment_name}_${var.service_name}_${var.tier}_user"
}

resource "aws_ssm_parameter" "pennsieve_postgres_password" {
  name  = "/${var.environment_name}/${var.service_name}-${var.tier}/pennsieve-postgres-password"
  type  = "SecureString"
  value = "dummy"

  lifecycle {
    ignore_changes = [value]
  }
}
