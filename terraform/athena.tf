resource "random_string" "athena" {
  length  = 8
  special = false
  lower   = true
  upper   = false
}

locals {
  athena_result_bucket_name = "aws-athena-query-results-${random_string.athena.result}"
  athena_database_name      = "ci_analyzer"
}

resource "aws_s3_bucket" "athena_result" {
  bucket = local.athena_result_bucket_name
}

resource "aws_s3_bucket_public_access_block" "athena_result" {
  bucket              = aws_s3_bucket.athena_result.id
  block_public_acls   = true
  block_public_policy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "athena_result" {
  bucket = aws_s3_bucket.athena_result.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_athena_database" "example" {
  name   = local.athena_database_name
  bucket = local.athena_result_bucket_name
}

resource "aws_athena_workgroup" "ci_analyzer" {
  name = local.athena_database_name

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_result.bucket}/output/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
}
