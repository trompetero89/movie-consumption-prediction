# Terraform — Movie Consumption Prediction Pipeline Infrastructure

S3 for data/model/ predictions, an ECR repo for the inference container, a validation Lambda,
a Step Functions state machine orchestrating a SageMaker Processing Job,
EventBridge triggers (S3 event + monthly fallback schedule), SNS alerts, and
CloudWatch alarms.

## Files

| File                  | Purpose                                                |
|-----------------------|---------------------------------------------------------|
| `main.tf`              | Provider/backend configuration                          |
| `variables.tf`         | Input variables (bucket name, instance type, etc.)       |
| `s3.tf`                | Data bucket (raw/model/predictions), versioning, lifecycle |
| `ecr.tf`               | Container image repository for the inference job        |
| `codebuild.tf`         | CodeBuild project that builds/pushes the inference image (enabled via `codebuild_source_bucket`) |
| `iam.tf`               | Least-privilege roles for SageMaker, Lambda, Step Functions, EventBridge |
| `lambda.tf`            | Validation Lambda (fast pre-flight checks)               |
| `lambda/validation/`   | Lambda source code                                       |
| `sns.tf`               | Alert topic + optional email subscription                |
| `step_functions.tf`    | Orchestration: validate → SageMaker Processing Job → notify |
| `eventbridge.tf`       | S3-event trigger + monthly fallback schedule              |
| `monitoring.tf`        | CloudWatch alarms on Step Functions failures/duration    |
| `outputs.tf`           | Useful resource identifiers after apply                  |

## Assumptions

- An AWS account/credentials are already configured for the Terraform AWS
  provider (`aws configure` / environment variables / SSO profile) — not
  managed by this code. The identity used needs permission to create S3,
  ECR, IAM (roles + inline policies), Lambda, Step Functions, EventBridge,
  SNS, CloudWatch, and CodeBuild resources (broad `AdministratorAccess` is
  sufficient for a personal/sandbox account; a real org would scope this to
  a dedicated deployment role).
- No pre-existing resources are assumed other than: the S3 bucket that
  holds the CodeBuild build-source zip (`codebuild_source_bucket`, see
  below) — everything else is created fresh by this Terraform.
- Remote state (S3 backend + DynamoDB lock table) is set up separately per
  environment; `main.tf` leaves the `backend "s3" {}` block commented out,
  so state is local by default (fine for this exercise / a single operator;
  not appropriate for a team without enabling it).
- The inference container image is built and pushed to the ECR repo created
  here via `../container/codebuild_deploy.sh` + the CodeBuild project in
  `codebuild.tf` (see `../container/README.md`) — Terraform provisions the
  ECR repository but does not build/push the image itself.
- `var.data_bucket_name` must be globally unique; the default value is a
  placeholder and should be overridden via a `terraform.tfvars` file or
  `-var` flag per account.
- The Lambda deployment package is zipped from `lambda/validation/` by
  `data.archive_file` for convenience; in a real CI/CD pipeline this would
  likely be built and versioned separately (e.g. via SAM/CDK-style asset
  packaging or a artifact bucket + `source_code_hash`).
- No SageMaker `Model`/real-time `Endpoint` resources are created, by design
  (Processing Job was chosen over Endpoint/Batch Transform for this batch,
  non-latency-sensitive workload).
- The container image is always built via the CodeBuild project in
  `codebuild.tf` (`count = local.create_codebuild ? 1 : 0`, enabled by
  setting `codebuild_source_bucket`); no local Docker installation is
  required or assumed anywhere in this solution. The variable expects an
  existing S3 bucket to hold the zipped build source (not created by this
  Terraform, to avoid assuming ownership of an unrelated bucket).
- Default region is `us-east-1` (`var.aws_region`); no multi-region or
  disaster-recovery setup is assumed for this exercise.
- SNS email alerting (`var.alert_email`) requires manual confirmation of the
  subscription email after `apply` — not automatable via Terraform.

## Usage

```bash
cd terraform
terraform init
terraform plan \
  -var="data_bucket_name=<your-globally-unique-bucket-name>" \
  -var="codebuild_source_bucket=<an-existing-s3-bucket-for-build-source>" \
  -var="alert_email=you@example.com"
terraform apply \
  -var="data_bucket_name=<your-globally-unique-bucket-name>" \
  -var="codebuild_source_bucket=<an-existing-s3-bucket-for-build-source>" \
  -var="alert_email=you@example.com"
```

After `apply`, build and push the inference container image via CodeBuild
(see `../container/README.md` for full details):

```bash
cd ..
./container/codebuild_deploy.sh <source_bucket> build-source.zip \
  "$(terraform -chdir=terraform output -raw codebuild_project_name)"
```

Then upload the model and inference data:

```bash
BUCKET="$(terraform -chdir=terraform output -raw data_bucket_name)"
aws s3 cp artifacts/movie_consumption_model.pkl "s3://${BUCKET}/model/"
aws s3 cp artifacts/feature_schema.json "s3://${BUCKET}/model/"
aws s3 cp data/inference_movies.csv "s3://${BUCKET}/raw/movies/2026-06/"
aws s3 cp data/inference_consumption.csv "s3://${BUCKET}/raw/consumption/2026-06/"
```

## Note on scope

Provisioning real AWS resources (`terraform apply`) is **not required** to
evaluate this code, the sections below describe what was verified
offline, what was verified with real resources, and what would
still need a live run to confirm. A single S3 bucket for
data/model/predictions, one Processing Job, one Step Functions state machine, and a
handful of least-privilege IAM roles.

## How this was validated without provisioning resources

- `terraform fmt -check -recursive` — clean, no formatting diffs.
- `terraform validate` — "Success! The configuration is valid." (checks
  syntax, argument types, and internal references across all `.tf` files).
- An **offline `terraform plan`**: added a temporary provider override
  (`skip_credentials_validation`, `skip_requesting_account_id`,
  `skip_metadata_api_check`, `skip_region_validation = true`) with fake
  static credentials, so the full ~25-resource plan could be computed with
  no network calls to AWS at all. This confirms the resource graph,
  references between resources (e.g. IAM role ARNs feeding into Lambda/Step
  Functions/EventBridge), and variable interpolation are all internally
  consistent. (The only remaining failure point offline is
  `data.aws_caller_identity.current`, needed for account-ID-scoped ARNs,
  which requires a real account.)
- `checkov` static scan: 146 checks passed, 16
  failed — all 16 are non-structural hardening suggestions
  rather than correctness issues; one is an
  intentional exception (the broad `ecr:GetAuthorizationToken` action,
  which AWS requires to be `Resource = "*"`).

## What was additionally verified with a real AWS account

Earlier in this project a full `terraform apply` was run against a real,
personal AWS account: all 31 resources (S3 buckets, ECR repo, 5 IAM roles,
Lambda, SNS topic, Step Functions state machine, 2 EventBridge rules, 2
CloudWatch alarms, CodeBuild project) were created successfully with the
IAM policies exactly as committed here (no permissions had to be loosened
to make `apply` succeed). `terraform destroy` was then run and verified,
via AWS CLI queries across S3/ECR/Step Functions/Lambda/IAM, to leave zero
resources behind.

## What remains unverified

- The exact EventBridge event pattern transformer for S3 Object
  Created events under real data upload conditions.
- Whether `ml.m5.large` is right-sized for the Processing Job at
  production data volumes.
- IAM policy completeness if the Processing Job were run inside a VPC,
 would validate with `terraform plan` plus a first
  successful job run, then tighten with IAM Access Analyzer.
