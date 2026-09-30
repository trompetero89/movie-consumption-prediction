# Step Functions state machine orchestrating: validate -> run SageMaker
# Processing Job -> notify. Uses the native SageMaker Processing Job
# integration (.sync) so Step Functions polls completion without a custom
# Lambda poller.

resource "aws_sfn_state_machine" "pipeline" {
  name     = "${var.project_name}-monthly-inference"
  role_arn = aws_iam_role.step_functions.arn

  definition = jsonencode({
    Comment = "Monthly movie consumption inference pipeline"
    StartAt = "ValidateInput"
    States = {
      ValidateInput = {
        Type     = "Task"
        Resource = aws_lambda_function.validation.arn
        Parameters = {
          "bucket.$" = "$.bucket"
          "key.$"    = "$.key"
        }
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            IntervalSeconds = 5
            MaxAttempts     = 2
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error"
            Next        = "NotifyFailure"
          }
        ]
        Next = "RunInference"
      }

      RunInference = {
        Type     = "Task"
        Resource = "arn:aws:states:::sagemaker:createProcessingJob.sync"
        Parameters = {
          "ProcessingJobName.$" = "States.Format('${var.project_name}-{}', $$.Execution.Name)"
          RoleArn               = aws_iam_role.sagemaker_processing.arn
          AppSpecification = {
            ImageUri = "${aws_ecr_repository.inference.repository_url}:latest"
          }
          ProcessingResources = {
            ClusterConfig = {
              InstanceType   = var.processing_instance_type
              InstanceCount  = var.processing_instance_count
              VolumeSizeInGB = 20
            }
          }
          ProcessingInputs = [
            {
              InputName = "raw-data"
              S3Input = {
                "S3Uri.$"   = "States.Format('s3://${aws_s3_bucket.data.bucket}/raw/{}', $.month_prefix)"
                LocalPath   = "/opt/ml/processing/input/raw"
                S3DataType  = "S3Prefix"
                S3InputMode = "File"
              }
            },
            {
              InputName = "model"
              S3Input = {
                S3Uri       = "s3://${aws_s3_bucket.data.bucket}/model/"
                LocalPath   = "/opt/ml/processing/input/model"
                S3DataType  = "S3Prefix"
                S3InputMode = "File"
              }
            }
          ]
          ProcessingOutputConfig = {
            Outputs = [
              {
                OutputName = "predictions"
                S3Output = {
                  "S3Uri.$"    = "States.Format('s3://${aws_s3_bucket.data.bucket}/predictions/{}', $.month_prefix)"
                  LocalPath    = "/opt/ml/processing/output"
                  S3UploadMode = "EndOfJob"
                }
              }
            ]
          }
          StoppingCondition = {
            MaxRuntimeInSeconds = 3600
          }
        }
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error"
            Next        = "NotifyFailure"
          }
        ]
        Next = "NotifySuccess"
      }

      NotifySuccess = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.alerts.arn
          Message  = "Monthly movie consumption inference completed successfully."
        }
        End = true
      }

      NotifyFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.alerts.arn
          "Message.$" = "States.Format('Monthly movie consumption inference FAILED: {}', $.error)"
        }
        End = true
      }
    }
  })
}
