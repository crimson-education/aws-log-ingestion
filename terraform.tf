terraform {
  required_version = "~> 0.14"
}

variable "service_name" {
  type        = string
  description = "The name of the lambda function and related resources"
  default     = "newrelic-log-ingestion"
}

variable "nr_license_key" {
  type        = string
  description = "Your NewRelic license key."
  sensitive   = true
}

variable "nr_logging_enabled" {
  type        = bool
  description = "Determines if logs are forwarded to New Relic Logging"
  default     = false
}

variable "nr_infra_logging" {
  type        = bool
  description = "Determines if logs are forwarded to New Relic Infrastructure"
  default     = true
}

variable "memory_size" {
  type        = number
  description = "Memory size for the New Relic Log Ingestion Lambda function"
  default     = 128
}

variable "timeout" {
  type        = number
  description = "Timeout for the New Relic Log Ingestion Lambda function"
  default     = 30
}

variable "function_role" {
  type        = string
  description = "IAM Role name that this function will assume. Should provide the AWSLambdaBasicExecutionRole policy. If not specified, an appropriate Role will be created, which will require CAPABILITY_IAM to be acknowledged."
  default     = null
}

variable "permissions_boundary" {
  type        = string
  description = "IAM Role Permissions Boundary (optional)"
  default     = null
}

variable "lambda_log_retention_in_days" {
  type        = number
  description = "Number of days to keep logs from the lambda for"
  default     = 7
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
locals {
  aws_account_id = data.aws_caller_identity.current.account_id
  aws_partition  = data.aws_partition.current.partition
  aws_region     = data.aws_region.current.name
}

data "aws_iam_policy_document" "lambda_assume_policy" {
  statement {
    actions = [
      "sts:AssumeRole"
    ]
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  count = var.function_role == null ? 1 : 0

  name                 = var.name
  assume_role_policy   = data.aws_iam_policy_document.lambda_assume_policy.json
  permissions_boundary = var.permissions_boundary
}

resource "aws_iam_role_policy_attachment" "lambda_log_policy" {
  count = var.function_role == null ? 1 : 0

  role       = aws_iam_role.lambda_role.0.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = var.lambda_log_retention_in_days
}

resource "aws_lambda_function" "ingestion_function" {
  depends_on = [
    aws_iam_role.lambda_role,
    aws_cloudwatch_log_group.lambda_logs,
  ]

  function_name = var.name
  description   = "Sends log data from CloudWatch Logs to New Relic Infrastructure (Cloud integrations) and New Relic Logging"
  publish       = true
  role = (var.function_role != null
    ? var.function_role
    : aws_iam_role.lambda_role.0.arn
  )
  runtime     = "python3.7"
  handler     = "function.lambda_handler"
  memory_size = var.memory_size
  timeout     = var.timeout

  filename         = ""
  source_code_hash = ""

  environment {
    variables = {
      LICENSE_KEY     = var.nr_license_key
      LOGGING_ENABLED = var.nr_logging_enabled ? "True" : "False"
      INFRA_ENABLED   = var.nr_infra_logging ? "True" : "False"
    }
  }
}

resource "aws_lambda_permission" "log_invoke_permission" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingestion_function.function_name
  principal     = "logs.${local.aws_region}.amazonaws.com"
  source_arn    = "arn:${local.aws_partition}:logs:${local.aws_region}:${local.aws_account_id}:log-group:*"
}

output "function_arn" {
  value       = aws_lambda_function.ingestion_function.arn
  description = "Log ingestion lambda function ARN"
}
