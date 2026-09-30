# ECR repository holding the container image used by the SageMaker Processing Job.

resource "aws_ecr_repository" "inference" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "IMMUTABLE" # force explicit new tags per release

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "inference" {
  repository = aws_ecr_repository.inference.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only the last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
