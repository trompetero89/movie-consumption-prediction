variable "codebuild_source_bucket" {
  description = <<-EOT
    S3 bucket + key (bucket/key.zip) containing the build source (container/,
    src/, requirements.txt) that CodeBuild will fetch and build. Upload with:
      cd .. && zip -r build-source.zip src container requirements.txt
      aws s3 cp build-source.zip s3://<bucket>/<key>.zip
    Leave empty to skip creating the CodeBuild project.
  EOT
  type        = string
  default     = ""
}

variable "codebuild_source_key" {
  description = "S3 key of the zipped build source, relative to codebuild_source_bucket."
  type        = string
  default     = "build-source.zip"
}

locals {
  create_codebuild = var.codebuild_source_bucket != ""
}

data "aws_iam_policy_document" "codebuild_assume" {
  count = local.create_codebuild ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  count              = local.create_codebuild ? 1 : 0
  name               = "${var.project_name}-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume[0].json
}

data "aws_iam_policy_document" "codebuild" {
  count = local.create_codebuild ? 1 : 0

  statement {
    sid       = "Logging"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.project_name}-*"]
  }

  statement {
    sid       = "ReadBuildSource"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["arn:aws:s3:::${var.codebuild_source_bucket}/${var.codebuild_source_key}"]
  }

  statement {
    sid       = "ReadBuildSourceBucketList"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.codebuild_source_bucket}"]
  }

  statement {
    sid = "PushToEcr"
    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = [aws_ecr_repository.inference.arn]
  }

  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # required to be "*" by the ECR API for this action
  }
}

resource "aws_iam_role_policy" "codebuild" {
  count  = local.create_codebuild ? 1 : 0
  name   = "${var.project_name}-codebuild-policy"
  role   = aws_iam_role.codebuild[0].id
  policy = data.aws_iam_policy_document.codebuild[0].json
}

resource "aws_cloudwatch_log_group" "codebuild" {
  count             = local.create_codebuild ? 1 : 0
  name              = "/aws/codebuild/${var.project_name}-build-image"
  retention_in_days = 30
}

resource "aws_codebuild_project" "build_image" {
  count         = local.create_codebuild ? 1 : 0
  name          = "${var.project_name}-build-image"
  description   = "Builds and pushes the inference container image to ECR."
  service_role  = aws_iam_role.codebuild[0].arn
  build_timeout = 20

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true # required to run `docker build` inside CodeBuild

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }
    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }
    environment_variable {
      name  = "ECR_REPOSITORY_URL"
      value = aws_ecr_repository.inference.repository_url
    }
    environment_variable {
      name  = "IMAGE_TAG"
      value = "latest"
    }
  }

  source {
    type      = "S3"
    location  = "${var.codebuild_source_bucket}/${var.codebuild_source_key}"
    buildspec = "container/buildspec.yml"
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.codebuild[0].name
    }
  }
}
