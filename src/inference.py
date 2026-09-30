"""
Inference pipeline for the Movie Consumption Prediction Challenge.
"""

from __future__ import annotations

import logging
import pickle
from dataclasses import dataclass
from pathlib import Path
from typing import Final

import pandas as pd

logger = logging.getLogger(__name__)

GRAIN: Final[list[str]] = ["TITLE_ID", "country", "platform"]

CATEGORICAL_FEATURES: Final[list[str]] = ["country", "platform", "primary_genre"]
NUMERIC_FEATURES: Final[list[str]] = [
    "may_streams",
    "may_total_minutes",
    "release_year",
    "runtime_minutes",
    "rating_value",
    "rating_vote_count",
]
FEATURE_COLUMNS: Final[list[str]] = CATEGORICAL_FEATURES + NUMERIC_FEATURES

MAY: Final[str] = "2026-05-01"

REQUIRED_MOVIE_COLUMNS: Final[list[str]] = [
    "TITLE_ID",
    "YEAR",
    "RUNTIME_MINUTES",
    "PRIMARY_GENRE",
    "RATING_VALUE",
    "RATING_VOTE_COUNT",
]
REQUIRED_CONSUMPTION_COLUMNS: Final[list[str]] = [
    "imdb_id",
    "month",
    "country",
    "platform",
    "streams",
    "total_minutes",
]


class InferenceDataError(ValueError):
    """Raised when the supplied inference inputs fail validation."""


@dataclass(frozen=True)
class InferenceArtifacts:
    """Holds the fitted model loaded from disk."""

    model: object

    @classmethod
    def load(cls, model_path: Path) -> "InferenceArtifacts":
        if not model_path.exists():
            raise FileNotFoundError(f"Model artifact not found at: {model_path}")
        logger.info("Loading model artifact from %s", model_path)
        with open(model_path, "rb") as fh:
            model = pickle.load(fh)
        return cls(model=model)


def _validate_columns(df: pd.DataFrame, required: list[str], name: str) -> None:
    missing = [c for c in required if c not in df.columns]
    if missing:
        raise InferenceDataError(
            f"{name} is missing required column(s): {missing}. Found columns: {list(df.columns)}"
        )


def load_movies(path: Path) -> pd.DataFrame:
    """Load and standardize movie metadata (renames to lower_snake_case feature names)."""
    if not path.exists():
        raise FileNotFoundError(f"Movies file not found: {path}")
    raw = pd.read_csv(path, encoding="utf-8-sig", dtype={"TITLE_ID": "string"})
    _validate_columns(raw, REQUIRED_MOVIE_COLUMNS, "Movies file")

    movies = raw.rename(
        columns={
            "YEAR": "release_year",
            "RUNTIME_MINUTES": "runtime_minutes",
            "PRIMARY_GENRE": "primary_genre",
            "RATING_VALUE": "rating_value",
            "RATING_VOTE_COUNT": "rating_vote_count",
        }
    ).copy()

    duplicated = movies["TITLE_ID"].duplicated()
    if duplicated.any():
        dupes = movies.loc[duplicated, "TITLE_ID"].unique().tolist()
        logger.warning(
            "Movies file has %d duplicate TITLE_ID row(s); keeping the first occurrence: %s",
            len(dupes),
            dupes[:10],
        )
        movies = movies.drop_duplicates(subset="TITLE_ID", keep="first")

    return movies[
        ["TITLE_ID", "release_year", "runtime_minutes", "primary_genre", "rating_value", "rating_vote_count"]
    ]


def load_consumption(path: Path) -> pd.DataFrame:
    """Load and standardize consumption records (key renamed to TITLE_ID, types coerced)."""
    if not path.exists():
        raise FileNotFoundError(f"Consumption file not found: {path}")
    raw = pd.read_csv(path, encoding="utf-8-sig", dtype={"imdb_id": "string"})
    _validate_columns(raw, REQUIRED_CONSUMPTION_COLUMNS, "Consumption file")

    consumption = raw.rename(columns={"imdb_id": "TITLE_ID"}).copy()
    consumption["month"] = pd.to_datetime(consumption["month"], errors="raise").dt.strftime("%Y-%m-%d")
    for column in ("streams", "total_minutes"):
        consumption[column] = pd.to_numeric(consumption[column], errors="raise")
    return consumption


def build_may_features(consumption: pd.DataFrame, may_month: str = MAY) -> pd.DataFrame:
    """Aggregate consumption to May features at the TITLE_ID x country x platform grain."""
    may = consumption.loc[consumption["month"].eq(may_month)]
    if may.empty:
        raise InferenceDataError(
            f"No consumption rows found for month={may_month!r}. "
            "Cannot build inference features without May data."
        )
    return (
        may.groupby(GRAIN, as_index=False, dropna=False)
        .agg(
            may_streams=("streams", "sum"),
            may_total_minutes=("total_minutes", "sum"),
        )
    )


def build_feature_table(may_features: pd.DataFrame, movies: pd.DataFrame) -> pd.DataFrame:
    """Join film-level attributes onto the May feature rows without changing the grain."""
    n_before = len(may_features)
    table = may_features.merge(movies, on="TITLE_ID", how="left", validate="many_to_one")
    if len(table) != n_before:
        raise InferenceDataError("Join with movie metadata changed row count; grain was not preserved.")

    unmatched = table.loc[table["release_year"].isna(), "TITLE_ID"].unique()
    if len(unmatched) > 0:
        logger.warning(
            "%d TITLE_ID(s) present in consumption but missing from movie metadata; "
            "numeric attributes will be imputed by the model's fitted imputer: %s",
            len(unmatched),
            list(unmatched)[:10],
        )
    return table


def predict(model: object, feature_table: pd.DataFrame) -> pd.Series:
    """Generate predictions using the supplied, already-fitted model. No fitting happens here."""
    missing = [c for c in FEATURE_COLUMNS if c not in feature_table.columns]
    if missing:
        raise InferenceDataError(f"Feature table is missing expected columns: {missing}")
    X = feature_table[FEATURE_COLUMNS]
    preds = model.predict(X)
    return pd.Series(preds, index=feature_table.index, name="predicted_june_streams")


def run_inference(
    movies_path: Path,
    consumption_path: Path,
    model_path: Path,
    may_month: str = MAY,
) -> pd.DataFrame:
    """End-to-end pipeline: load -> aggregate -> join -> predict. Returns the output DataFrame."""
    movies = load_movies(movies_path)
    consumption = load_consumption(consumption_path)

    may_features = build_may_features(consumption, may_month=may_month)
    feature_table = build_feature_table(may_features, movies)

    artifacts = InferenceArtifacts.load(model_path)
    predictions = predict(artifacts.model, feature_table)

    output = feature_table[["TITLE_ID", "country", "platform"]].copy()
    output["predicted_june_streams"] = predictions.round(2)

    # Preserve full film x country x platform grain from the May input.
    if len(output) != len(may_features):
        raise InferenceDataError("Output row count does not match the number of May combinations.")

    return output.sort_values(["TITLE_ID", "country", "platform"]).reset_index(drop=True)
