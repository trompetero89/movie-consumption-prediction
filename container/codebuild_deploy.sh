#!/usr/bin/env bash
# Usage (from the repo root):
#   ./container/codebuild_deploy.sh <source_bucket> [source_key] [codebuild_project_name]

set -euo pipefail

BUCKET="${1:?Usage: $0 <source_bucket> [source_key] [codebuild_project_name]}"
KEY="${2:-build-source.zip}"
PROJECT="${3:-movie-consumption-build-image}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZIP_PATH="$(mktemp -d)/build-source.zip"

echo "Zipping build source..."
cd "${REPO_ROOT}"
zip -q -r "${ZIP_PATH}" src container requirements.txt

echo "Uploading to s3://${BUCKET}/${KEY}..."
aws s3 cp "${ZIP_PATH}" "s3://${BUCKET}/${KEY}"

echo "Starting CodeBuild project ${PROJECT}..."
BUILD_ID=$(aws codebuild start-build --project-name "${PROJECT}" --query 'build.id' --output text)
echo "Build started: ${BUILD_ID}"

echo "Waiting for build to finish..."
while true; do
  STATUS=$(aws codebuild batch-get-builds --ids "${BUILD_ID}" --query 'builds[0].buildStatus' --output text)
  echo "  status: ${STATUS}"
  case "${STATUS}" in
    IN_PROGRESS) sleep 10 ;;
    SUCCEEDED) echo "Build succeeded."; exit 0 ;;
    *) echo "Build ended with status ${STATUS}. Check CloudWatch Logs (/aws/codebuild/${PROJECT})."; exit 1 ;;
  esac
done
