# IAM roles, one per component, scoped to the specific bucket prefixes,
# ECR repo, and SNS topic used by this pipeline (no wildcard resources).

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# SageMaker Processing Job execution role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "sagemaker_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sagemaker_processing" {
  name               = "${var.project_name}-sagemaker-processing-role"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume.json
}

data "aws_iam_policy_document" "sagemaker_processing" {
  statement {
    sid     = "ReadRawAndModel"
    actions = ["s3:GetObject", "s3:GetObjectVersion", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.data.arn,
      "${aws_s3_bucket.data.arn}/raw/*",
      "${aws_s3_bucket.data.arn}/model/*",
    ]
  }

  statement {
    sid       = "WritePredictions"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.data.arn}/predictions/*"]
  }

  statement {
    sid       = "PullContainerImage"
    actions   = ["ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:BatchCheckLayerAvailability"]
    resources = [aws_ecr_repository.inference.arn]
  }

  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # required to be "*" by the ECR API for this action
  }

  statement {
    sid     = "Logging"
    actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/sagemaker/ProcessingJobs*"
    ]
  }
}

resource "aws_iam_role_policy" "sagemaker_processing" {
  name   = "${var.project_name}-sagemaker-processing-policy"
  role   = aws_iam_role.sagemaker_processing.id
  policy = data.aws_iam_policy_document.sagemaker_processing.json
}

# ---------------------------------------------------------------------------
# Validation Lambda execution role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "validation_lambda" {
  name               = "${var.project_name}-validation-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "validation_lambda" {
  statement {
    sid       = "ReadRaw"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.data.arn, "${aws_s3_bucket.data.arn}/raw/*"]
  }

  statement {
    sid       = "Logging"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-*"]
  }
}

resource "aws_iam_role_policy" "validation_lambda" {
  name   = "${var.project_name}-validation-lambda-policy"
  role   = aws_iam_role.validation_lambda.id
  policy = data.aws_iam_policy_document.validation_lambda.json
}

# ---------------------------------------------------------------------------
# Step Functions execution role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "sfn_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "step_functions" {
  name               = "${var.project_name}-step-functions-role"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume.json
}

data "aws_iam_policy_document" "step_functions" {
  statement {
    sid     = "RunProcessingJob"
    actions = ["sagemaker:CreateProcessingJob", "sagemaker:DescribeProcessingJob", "sagemaker:StopProcessingJob"]
    resources = [
      "arn:aws:sagemaker:${var.aws_region}:${data.aws_caller_identity.current.account_id}:processing-job/${var.project_name}-*"
    ]
  }

  statement {
    sid       = "PassSagemakerRole"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.sagemaker_processing.arn]
  }

  statement {
    sid       = "InvokeValidationLambda"
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.validation.arn]
  }

  statement {
    sid       = "PublishAlerts"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }

  statement {
    sid     = "SfnManagedRuleEvents"
    actions = ["events:PutTargets", "events:PutRule", "events:DescribeRule"]
    resources = [
      "arn:aws:events:${var.aws_region}:${data.aws_caller_identity.current.account_id}:rule/StepFunctionsGetEventsForSageMakerProcessingJobsRule"
    ]
  }
}

resource "aws_iam_role_policy" "step_functions" {
  name   = "${var.project_name}-step-functions-policy"
  role   = aws_iam_role.step_functions.id
  policy = data.aws_iam_policy_document.step_functions.json
}

# ---------------------------------------------------------------------------
# EventBridge -> Step Functions trigger role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "events_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eventbridge_invoke_sfn" {
  name               = "${var.project_name}-eventbridge-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.events_assume.json
}

data "aws_iam_policy_document" "eventbridge_invoke_sfn" {
  statement {
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.pipeline.arn]
  }
}

resource "aws_iam_role_policy" "eventbridge_invoke_sfn" {
  name   = "${var.project_name}-eventbridge-sfn-policy"
  role   = aws_iam_role.eventbridge_invoke_sfn.id
  policy = data.aws_iam_policy_document.eventbridge_invoke_sfn.json
}
