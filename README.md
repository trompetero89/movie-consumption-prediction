# Movie Consumption Prediction Challenge — Inference Solution

Predicts June 2026 streams per `TITLE_ID × country × platform`, using the
supplied pre-trained model and May 2026 raw inputs.

## Contents

```
Makefile                        One-command setup/predict/test targets
pyproject.toml                  Package metadata, pinned dependencies, pytest config
predict.py                      CLI entrypoint
src/inference.py                Data loading, feature engineering, prediction logic
tests/test_inference.py         Unit tests (pytest)
output/predictions.csv          Generated predictions 
terraform/                      Terraform infrastructure
container/                      SageMaker Processing Job container (Dockerfile + entrypoint)
```

## What the pipeline does

1. **Load** `data/inference_movies.csv` and `data/inference_consumption.csv` as-is.
2. **Standardize keys/types**: rename `imdb_id → TITLE_ID`, parse `month`,
   coerce `streams`/`total_minutes` to numeric — mirroring
   `02_model_development_reference.ipynb`.
3. **Aggregate May features** by summing `streams`/`total_minutes` within each
   `TITLE_ID × country × platform` group for `month == 2026-05-01`.
4. **Join movie attributes** (`release_year`, `runtime_minutes`,
   `primary_genre`, `rating_value`, `rating_vote_count`) onto the May rows by
   `TITLE_ID`, left join.
5. **Load the supplied model** (`artifacts/movie_consumption_model.pkl`) with
   `pickle`.
6. **Predict** `predicted_june_streams` for every row, in the exact feature
   order from `artifacts/feature_schema.json`.
7. **Write** `TITLE_ID, country, platform, predicted_june_streams` to CSV.


## Setup

Requires Python 3.13 

### One command

```bash
make setup    # creates .venv and installs dependencies (from pyproject.toml)
make predict  # runs inference, writes output/predictions.csv
make test     # runs the pytest 
```


## Run inference

```bash
python predict.py \
  --movies data/inference_movies.csv \
  --consumption data/inference_consumption.csv \
  --model artifacts/movie_consumption_model.pkl \
  --output output/predictions.csv
```

Exit codes: `0` success, `2` missing input file, `3` data validation failure


## Run tests

```bash
make test
```



## Known limitations, what I would improve with more time

- The model's fitted imputer silently fills missing metadata
 with training-set defaults; in production I'd surface a
  per-row data-quality flag in the output rather than only logging it.
- No confidence intervals, prediction uncertainty is produced, only the
  point estimate the model returns.
- No schema pinning check against `feature_schema.json` at runtime
  (currently the feature order is hard-coded to match it); I'd add a startup
  assertion that compares the two.
- No integration test that stubs a corrupted or incompatible pickle file.

## AI-assisted development tools used

This solution was developed with **Copilot**,
 which was used to draft `src/inference.py`,
`predict.py`, `tests/test_inference.py`and the Terraform files. 
