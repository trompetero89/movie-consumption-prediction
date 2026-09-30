"""
Validation Lambda invoked by the Step Functions pipeline before starting the
SageMaker Processing Job. Performs a fast, cheap sanity check on the newly
arrived consumption CSV so we fail fast instead of paying for SageMaker
compute against malformed input.
"""

from __future__ import annotations

import csv
import io
import json
import os

import boto3

REQUIRED_COLUMNS = {"imdb_id", "month", "country", "platform", "streams", "total_minutes"}

s3 = boto3.client("s3")


def lambda_handler(event, context):
    bucket = event.get("bucket") or os.environ["DATA_BUCKET"]
    key = event["key"]

    response = s3.get_object(Bucket=bucket, Key=key)
    body = response["Body"].read().decode("utf-8-sig")

    reader = csv.reader(io.StringIO(body))
    header = next(reader, None)
    if header is None:
        raise ValueError(f"File s3://{bucket}/{key} is empty.")

    missing = REQUIRED_COLUMNS - set(header)
    if missing:
        raise ValueError(f"File s3://{bucket}/{key} is missing required column(s): {sorted(missing)}")

    row_count = sum(1 for _ in reader)
    if row_count == 0:
        raise ValueError(f"File s3://{bucket}/{key} has a header but no data rows.")

    return {
        "statusCode": 200,
        "bucket": bucket,
        "key": key,
        "row_count": row_count,
        "message": "Validation passed.",
    }
