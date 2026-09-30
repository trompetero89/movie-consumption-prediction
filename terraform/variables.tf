variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment name (e.g. dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Short name used to prefix resource names."
  type        = string
  default     = "movie-consumption"
}

variable "data_bucket_name" {
  description = "Globally-unique S3 bucket name for raw data, model artifacts, and predictions."
  type        = string
  default     = "movie-consumption-prediction-data" # override per account; must be globally unique
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository holding the inference container image."
  type        = string
  default     = "movie-consumption-inference"
}

variable "processing_instance_type" {
  description = "Instance type for the SageMaker Processing Job."
  type        = string
  default     = "ml.m5.large"
}

variable "processing_instance_count" {
  description = "Number of instances for the SageMaker Processing Job."
  type        = number
  default     = 1
}

variable "model_version_id" {
  description = "S3 object version ID of the model artifact to use (empty string = latest)."
  type        = string
  default     = ""
}

variable "schedule_expression" {
  description = "EventBridge Scheduler cron/rate expression for the monthly fallback trigger."
  type        = string
  default     = "cron(0 6 3 * ? *)" # 06:00 UTC on the 3rd of every month
}

variable "alert_email" {
  description = "Email address subscribed to the SNS topic for pipeline failure/success alerts."
  type        = string
  default     = "" # leave blank to skip creating an email subscription
}
