# Layout:
#   raw/movies/YYYY-MM/...
#   raw/consumption/YYYY-MM/...
#   model/movie_consumption_model.pkl
#   model/feature_schema.json
#   predictions/YYYY-MM/predictions.csv

resource "aws_s3_bucket" "data" {
  bucket = var.data_bucket_name
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Transition older raw data to Infrequent Access after 90 days.
resource "aws_s3_bucket_lifecycle_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    id     = "raw-data-ia-transition"
    status = "Enabled"

    filter {
      prefix = "raw/"
    }

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }
  }
}

# Used by the EventBridge rule in eventbridge.tf as the primary trigger.
resource "aws_s3_bucket_notification" "data" {
  bucket      = aws_s3_bucket.data.id
  eventbridge = true
}
