terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # backend "s3" {} # configure remote state per environment
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "movie-consumption-prediction"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
