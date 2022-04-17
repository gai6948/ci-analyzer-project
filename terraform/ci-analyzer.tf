resource "random_string" "ci_analyzer" {
  length  = 8
  special = false
  lower   = true
  upper   = false
}

locals {
  ci_analyzer_bucket_name = "ci-analyzer-${random_string.ci_analyzer.result}"
  ci_analyzer_user        = "ci-analyzer"
}

resource "aws_s3_bucket" "ci_analyzer" {
  bucket = local.ci_analyzer_bucket_name

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
      }
    }
  }
}

resource "aws_s3_bucket_public_access_block" "ci_analyzer" {
  bucket = aws_s3_bucket.ci_analyzer.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_user_policy" "ci_analyzer_policy" {
  name = "CIAnalyzerPolicy"
  user = local.ci_analyzer_user

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:PutObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ]
        Effect   = "Allow"
        Resource = ["${aws_s3_bucket.ci_analyzer.arn}/*"]
      },
      {
        Action = [
          "s3:ListBucket"
        ]
        Effect   = "Allow"
        Resource = ["${aws_s3_bucket.ci_analyzer.arn}"]
      }
    ]
  })
}

output "ci_analyzer_bucket_arn" {
  value = aws_s3_bucket.ci_analyzer.arn
}
