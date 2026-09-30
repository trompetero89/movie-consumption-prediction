# Inference Container (SageMaker Processing Job)

Packages the Part 1 inference logic (`src/inference.py`) as a Docker image
that runs as a **SageMaker Processing Job**, orchestrated by the Step
Functions state machine in `../terraform/step_functions.tf`. The image is
built and pushed entirely via **AWS CodeBuild** — no local Docker
installation is required.

## Files

| File                | Purpose                                                        |
|---------------------|-----------------------------------------------------------------|
| `Dockerfile`         | Builds the image: Python 3.13 + `requirements.txt` + `src/` + entrypoint |
| `run_processing.py`  | Entrypoint: discovers input CSVs, calls `run_inference`, writes `predictions.csv` |
| `buildspec.yml`      | CodeBuild build spec: builds and pushes the image using CodeBuild's own Docker-enabled environment |
| `codebuild_deploy.sh`| Zips `src/`+`container/`+`requirements.txt`, uploads to S3, and triggers the CodeBuild project |

## How SageMaker wires this up

Per `terraform/step_functions.tf`, the Processing Job mounts:

```
/opt/ml/processing/input/raw/       <- ProcessingInput "raw-data" (S3 raw/<month_prefix>/)
/opt/ml/processing/input/model/     <- ProcessingInput "model" (S3 model/)
/opt/ml/processing/output/          <- ProcessingOutput "predictions" (S3 predictions/<month_prefix>/)
```

`run_processing.py` recursively searches `input/raw/movies/` and
`input/raw/consumption/` for a single CSV file each (so the exact S3 key,
e.g. `raw/consumption/2026-06/inference_consumption.csv`, doesn't need to be
hard-coded), loads the model from `input/model/movie_consumption_model.pkl`,
runs the same `run_inference()` pipeline used by `predict.py` locally, and
writes `output/predictions.csv`.

The `PROCESSING_INPUT_ROOT` / `PROCESSING_OUTPUT_ROOT` environment variables
override these paths, which is how `tests/test_run_processing.py` exercises
the entrypoint locally in plain Python — without Docker and without needing
write access to `/opt`.

## Testing the entrypoint logic (no Docker, no AWS)

`tests/test_run_processing.py` simulates the SageMaker directory layout in a
temp directory and runs the entrypoint's `main()` function directly against
the real supplied model and inference data:

```bash
python -m pytest tests/test_run_processing.py -v
```

This validates the file-discovery logic and end-to-end wiring (321 rows,
correct columns, no nulls) purely in Python, before ever building an image.

## Building and pushing the image, via AWS CodeBuild

1. Ensure Terraform was applied with `codebuild_source_bucket` set (creates
   the CodeBuild project, its IAM role, and a log group — see
   `../terraform/codebuild.tf`):

   ```bash
   cd terraform
   terraform apply \
     -var="data_bucket_name=<your-bucket>" \
     -var="codebuild_source_bucket=<an-existing-s3-bucket-for-build-source>"
   ```

2. From the repo root, zip the source, upload it, and trigger the build:

   ```bash
   cd ..
   ./container/codebuild_deploy.sh <source_bucket> build-source.zip \
     "$(terraform -chdir=terraform output -raw codebuild_project_name)"
   ```

   The script uploads `src/`, `container/`, and `requirements.txt` as a zip,
   starts the `aws codebuild start-build` run, and polls until it succeeds
   or fails, printing the CloudWatch Logs group to check on failure
   (`/aws/codebuild/<project_name>`).

Re-run step 2 any time `src/inference.py` or `container/Dockerfile` changes
— CodeBuild always builds fresh from the zip you just uploaded, and pushes
to the `:latest` tag in the ECR repo (`terraform/ecr.tf`).

## What remains unverified without a live AWS account

- The CodeBuild path (`buildspec.yml` + `codebuild.tf`) — validated via
  `terraform validate`/`plan` and a real `terraform apply` +
  `codebuild_deploy.sh` run. Would re-validate any future change by
  re-running `codebuild_deploy.sh` against a sandbox account and checking
  `/aws/codebuild/<project>` logs.
- Real SageMaker Processing Job execution against the pushed image (needs
  `terraform apply` + a built/pushed image + a Step Functions execution) —
  would validate by starting an execution with a test
  `{"bucket": ..., "key": ...}` input and checking the CloudWatch Logs group
  `/aws/sagemaker/ProcessingJobs`.
