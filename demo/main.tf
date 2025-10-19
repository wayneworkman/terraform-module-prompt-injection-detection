terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

module "prompt-injection-detection" {
  source = "../"
}

output "lambda_function_name" {
  description = "Name of the deployed Lambda function"
  value       = module.prompt-injection-detection.lambda_function_name
}

output "lambda_function_arn" {
  description = "ARN of the deployed Lambda function"
  value       = module.prompt-injection-detection.lambda_function_arn
}

output "s3_bucket_id" {
  description = "S3 bucket ID for prompt storage (use this for custom prompts)"
  value       = module.prompt-injection-detection.bucket_id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN for prompt storage"
  value       = module.prompt-injection-detection.bucket_arn
}
