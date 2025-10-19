terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }
  }
}

# Local variables for naming
locals {
  lambda_base_name = "prompt-injection-detection"
  lambda_name = join("-", compact([
    var.lambda_name_prepend,
    local.lambda_base_name,
    var.lambda_name_append
  ]))
}

# S3 Bucket for prompt storage (always created)
resource "aws_s3_bucket" "prompt_injection_storage" {
  bucket_prefix = "${var.lambda_name_prepend != "" ? "${var.lambda_name_prepend}-" : ""}prompt-injection-"

  tags = {
    Purpose = "Prompt injection detection storage"
    Module  = "terraform-module-prompt-injection-detection"
  }
}

# Block public access to S3 bucket
resource "aws_s3_bucket_public_access_block" "prompt_injection_storage" {
  bucket = aws_s3_bucket.prompt_injection_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable encryption at rest for S3 bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "prompt_injection_storage" {
  bucket = aws_s3_bucket.prompt_injection_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Enable versioning for S3 bucket
resource "aws_s3_bucket_versioning" "prompt_injection_storage" {
  bucket = aws_s3_bucket.prompt_injection_storage.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable S3 access logging (optional)
resource "aws_s3_bucket_logging" "prompt_injection_storage" {
  count = var.s3_access_logging_bucket != "" ? 1 : 0

  bucket = aws_s3_bucket.prompt_injection_storage.id

  target_bucket = var.s3_access_logging_bucket
  target_prefix = var.s3_access_logging_prefix
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.lambda_name}"
  retention_in_days = var.log_retention_days
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda" {
  name = "${local.lambda_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for CloudWatch Logs
resource "aws_iam_role_policy" "lambda_logs" {
  name = "${local.lambda_name}-logs-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
      }
    ]
  })
}

# IAM Policy for Bedrock
resource "aws_iam_role_policy" "lambda_bedrock" {
  name = "${local.lambda_name}-bedrock-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Policy for S3 (prompt storage)
resource "aws_iam_role_policy" "lambda_s3" {
  name = "${local.lambda_name}-s3-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.prompt_injection_storage.arn}/*"
      }
    ]
  })
}

# Create Lambda deployment package
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "/tmp/lambda_function_${local.lambda_name}.zip"
}

# Lambda Function
resource "aws_lambda_function" "detector" {
  filename         = data.archive_file.lambda.output_path
  function_name    = local.lambda_name
  role             = aws_iam_role.lambda.arn
  handler          = "handler.lambda_handler"
  source_code_hash = data.archive_file.lambda.output_base64sha256
  runtime          = "python3.13"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size

  environment {
    variables = {
      PROMPT_BUCKET       = aws_s3_bucket.prompt_injection_storage.id
      PROMPT_OVERRIDE_KEY = var.prompt_override_key
      MODEL_ID            = var.model_id
      MAX_TOKENS          = tostring(var.max_tokens)
      TEMPERATURE         = tostring(var.temperature)
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy.lambda_logs,
    aws_iam_role_policy.lambda_bedrock,
    aws_iam_role_policy.lambda_s3
  ]
}
