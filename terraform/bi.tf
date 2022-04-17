locals {
  bi_user = "bi-user"
}

resource "aws_iam_user_policy" "bi_user_policy" {
  name = "BIUserS3Policy"
  user = local.bi_user

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:s3:::${local.ci_analyzer_bucket_name}/*"
        ]
      },
      {
        Action = [
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:s3:::${local.ci_analyzer_bucket_name}"
        ]
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "bi_user_athena" {
  name       = "athenafullaccess"
  users      = [local.bi_user]
  policy_arn = "arn:aws:iam::aws:policy/AmazonAthenaFullAccess"
}

resource "aws_iam_policy_attachment" "bi_user_quicksight" {
  name       = "quicksightfullaccess"
  users      = [local.bi_user]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSQuicksightAthenaAccess"
}
