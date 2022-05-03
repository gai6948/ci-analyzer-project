resource "aws_iam_role" "glue_crawler" {
  name = "CIAnalyzerGlueCrawlerRole"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "glue.amazonaws.com"
        }
      },
    ]
  })

  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"]

  inline_policy {
    name = "s3_bucket_read"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "s3:GetObject",
            "s3:PutObject",
          ]
          Effect   = "Allow"
          Resource = ["arn:aws:s3:::${local.ci_analyzer_bucket_name}/*"]
        }
      ]
    })
  }
}

resource "aws_glue_catalog_database" "ci_analyzer" {
  name = "ci_analyzer"
}

resource "aws_glue_crawler" "ci_analyzer_workflows" {
  database_name = aws_glue_catalog_database.ci_analyzer.name
  name          = "ci_analyzer_workflows"
  role          = aws_iam_role.glue_crawler.arn

  s3_target {
    path = "s3://${local.ci_analyzer_bucket_name}/processed/workflows/"
  }
}

resource "aws_glue_crawler" "ci_analyzer_tests" {
  database_name = aws_glue_catalog_database.ci_analyzer.name
  name          = "ci_analyzer_tests"
  role          = aws_iam_role.glue_crawler.arn

  s3_target {
    path = "s3://${local.ci_analyzer_bucket_name}/processed/tests/"
  }
}

resource "aws_iam_role" "ci_analyzer_job" {
  name = "CIAnalyzerGlueJobRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "glue.amazonaws.com"
        }
      },
    ]
  })

  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"]

  inline_policy {
    name = "s3_bucket_read"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "s3:GetObject",
          ]
          Effect = "Allow"
          Resource = [
            "arn:aws:s3:::${local.ci_analyzer_bucket_name}/ci-analyzer/*",
            "arn:aws:s3:::${local.ci_analyzer_bucket_name}/etl-scripts/*"
          ]
        },
        {
          Action = [
            "s3:GetObject",
            "s3:PutObject",
            "s3:DeleteObject"
          ]
          Effect   = "Allow"
          Resource = ["arn:aws:s3:::${local.ci_analyzer_bucket_name}/processed/*"]
        }
      ]
    })
  }
}

resource "aws_cloudwatch_log_group" "ci_analyzer_glue" {
  name              = "ci-analyzer-glue"
  retention_in_days = 7
}

resource "aws_glue_job" "ci_analyzer" {
  name              = "ci-analyzer-prod"
  role_arn          = aws_iam_role.ci_analyzer_job.arn
  glue_version      = "3.0"
  worker_type       = "G.1X"
  number_of_workers = 2

  command {
    script_location = "s3://${local.ci_analyzer_bucket_name}/etl-scripts/process-ci-data.py"
  }

  default_arguments = {
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-continuous-log-filter"     = "true"
    "--enable-job-insights"              = "true"
    "--enable-metrics"                   = "true"
    "--date_override"                    = "none"
    "--input_output_s3_bucket"           = local.ci_analyzer_bucket_name
  }
}

resource "aws_glue_trigger" "ci_analyzer" {
  name     = "ci-analyzer-daily-run"
  schedule = "cron(50 23 * * ? *)"
  type     = "SCHEDULED"

  actions {
    job_name = aws_glue_job.ci_analyzer.name
  }
}

resource "aws_glue_trigger" "ci_analyzer_crawler" {
  name = "ci-analyzer-crawler-trigger"
  type = "CONDITIONAL"

  predicate {
    conditions {
      job_name = aws_glue_job.ci_analyzer.name
      state    = "SUCCEEDED"
    }
  }
  actions {
    crawler_name = aws_glue_crawler.ci_analyzer_workflows.name
  }
  actions {
    crawler_name = aws_glue_crawler.ci_analyzer_tests.name
  }

}
