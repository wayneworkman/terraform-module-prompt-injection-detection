variable "prompt_override_key" {
  description = "Optional S3 key for custom prompt (reads from module-created bucket). If not provided, uses hardcoded default prompt in Lambda code."
  type        = string
  default     = ""
}

variable "model_id" {
  description = "AWS Bedrock model ID to use for prompt injection detection"
  type        = string
  default     = "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
}

variable "max_tokens" {
  description = "Maximum tokens for model response"
  type        = number
  default     = 4096
}

variable "temperature" {
  description = "Temperature setting for model inference"
  type        = number
  default     = 1.0
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}

variable "lambda_name_prepend" {
  description = "Optional prefix for Lambda function name"
  type        = string
  default     = ""
}

variable "lambda_name_append" {
  description = "Optional suffix for Lambda function name"
  type        = string
  default     = ""
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 900
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512
}

variable "s3_access_logging_bucket" {
  description = "Optional S3 bucket name for access logging. If not provided, access logging is disabled."
  type        = string
  default     = ""
}

variable "s3_access_logging_prefix" {
  description = "Optional prefix for S3 access logs. Only used if s3_access_logging_bucket is provided."
  type        = string
  default     = ""
}
