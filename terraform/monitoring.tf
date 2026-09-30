# CloudWatch alarms for basic operational monitoring.

resource "aws_cloudwatch_metric_alarm" "sfn_failures" {
  alarm_name          = "${var.project_name}-sfn-execution-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alerts when the monthly inference Step Functions execution fails."
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.pipeline.arn
  }
}

resource "aws_cloudwatch_metric_alarm" "processing_job_duration" {
  alarm_name          = "${var.project_name}-sfn-execution-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionTime"
  namespace           = "AWS/States"
  period              = 300
  statistic           = "Maximum"
  threshold           = 3600000 # 1 hour, in ms
  alarm_description   = "Alerts if a monthly inference execution runs unexpectedly long."
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.pipeline.arn
  }
}
