variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "bucket_name" {
  description = "Name prefix for the S3 bucket for static website hosting (account ID is appended to ensure global uniqueness)"
  type        = string
  default     = "cliff-static-website"
}

variable "aws_region" {
  description = "The AWS region to create resources in."
  type        = string
  default     = "us-east-1"
}

variable "oac_name" {
  description = "Name of the CloudFront Origin Access Control"
  type        = string
  default     = "demo-oac"
}

variable "bucket_tag" {
  description = "The tag for the s3 bucket"
  type        = string
  default     = "My bucket"
}

variable "oac_description" {
  description = "Description of the CloudFront Origin Access Control"
  type        = string
  default     = "static website Policy"
}

variable "lambda_execution_role" {
  description = "Lambda Execution Role name"
  type        = string
  default     = "site-lambda-execution-role"
}

variable "lambda_cloudwatch_dynamoDB_policy_name" {
  description = "Lambda policy name for cloudwatch and dynamoDB"
  type        = string
  default     = "site-lambda-permissions-policy"
}

variable "api_gateway_name" {
  description = "Name of the API Gateway HTTP API"
  type        = string
  default     = "serverless_lambda_gw"
}

variable "api_gateway_stage_name" {
  description = "Deployment stage name for the API Gateway API"
  type        = string
  default     = "serverless_lambda_stage"
}

variable "lambda_function_name" {
  description = "Name of the backend Lambda function"
  type        = string
  default     = "cliff-backend-handler"
}

variable "lambda_handler" {
  description = "Handler used by the backend Lambda function"
  type        = string
  default     = "lambda_function.lambda_handler"
}

variable "lambda_runtime" {
  description = "Runtime used by the backend Lambda function"
  type        = string
  default     = "python3.12"
}



variable "alert_email" {
  description = "Email address to receive CloudWatch alarm notifications"
  type        = string
  default = "gitacliff48@gmail.com"
}

variable "backup_retention_days" {
  description = "Number of days to retain DynamoDB backups (7 dev, 14 staging, 30 prod)"
  type        = number
  default     = 7
}

variable "cognito_callback_urls" {
  description = "Allowed redirect URLs after Cognito login"
  type        = list(string)
  default     = ["https://cliffworld.link/callback"]
}

variable "cognito_logout_urls" {
  description = "Allowed redirect URLs after Cognito logout"
  type        = list(string)
  default     = ["https://cliffworld.link"]
}

variable "cost_anomaly_threshold_percentage" {
  description = "Minimum percentage increase in spend to trigger a cost anomaly alert"
  type        = number
  default     = 50
}

variable "cost_anomaly_threshold_absolute" {
  description = "Minimum absolute dollar amount of spend increase to trigger a cost anomaly alert"
  type        = number
  default     = 10
}

