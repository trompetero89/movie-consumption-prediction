# EventBridge triggers for the Step Functions pipeline:
#  1. Primary: S3 "Object Created" event under raw/consumption/ (near-real-time).
#  2. Fallback: monthly schedule, in case the object-created event is missed.

resource "aws_cloudwatch_event_rule" "on_new_consumption_file" {
  name        = "${var.project_name}-on-new-consumption-file"
  description = "Triggers the inference pipeline when a new consumption file lands in S3."

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = { name = [aws_s3_bucket.data.bucket] }
      object = { key = [{ prefix = "raw/consumption/" }] }
    }
  })
}

resource "aws_cloudwatch_event_target" "on_new_consumption_file" {
  rule     = aws_cloudwatch_event_rule.on_new_consumption_file.name
  arn      = aws_sfn_state_machine.pipeline.arn
  role_arn = aws_iam_role.eventbridge_invoke_sfn.arn

  # NOTE: input_transformer here is illustrative; in practice, deriving
  # `month_prefix` from the S3 key reliably may warrant a tiny Lambda
  # instead of a pure EventBridge input transform.
  input_transformer {
    input_paths = {
      key    = "$.detail.object.key"
      bucket = "$.detail.bucket.name"
    }
    input_template = <<EOF
{
  "bucket": <bucket>,
  "key": <key>
}
EOF
  }
}

resource "aws_cloudwatch_event_rule" "monthly_fallback" {
  name                = "${var.project_name}-monthly-fallback"
  description         = "Fallback trigger in case the S3 event notification is missed."
  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "monthly_fallback" {
  rule     = aws_cloudwatch_event_rule.monthly_fallback.name
  arn      = aws_sfn_state_machine.pipeline.arn
  role_arn = aws_iam_role.eventbridge_invoke_sfn.arn
}
