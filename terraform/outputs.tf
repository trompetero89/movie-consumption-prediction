output "data_bucket_name" {
  description = "S3 bucket holding raw inputs, model artifacts, and predictions."
  value       = aws_s3_bucket.data.bucket
}

output "ecr_repository_url" {
  description = "ECR repository URL for the inference container image."
  value       = aws_ecr_repository.inference.repository_url
}

output "state_machine_arn" {
  description = "ARN of the Step Functions state machine orchestrating the monthly pipeline."
  value       = aws_sfn_state_machine.pipeline.arn
}

output "sns_alerts_topic_arn" {
  description = "SNS topic ARN for pipeline success/failure notifications."
  value       = aws_sns_topic.alerts.arn
}

output "sagemaker_processing_role_arn" {
  description = "IAM role assumed by the SageMaker Processing Job."
  value       = aws_iam_role.sagemaker_processing.arn
}

output "codebuild_project_name" {
  description = "Name of the CodeBuild project that builds/pushes the inference image (null if codebuild_source_bucket was not set)."
  value       = local.create_codebuild ? aws_codebuild_project.build_image[0].name : null
}
