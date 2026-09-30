"""
Unit tests for src.inference feature engineering and pipeline glue.
"""

from __future__ import annotations

from pathlib import Path

import pandas as pd
import pytest

from src.inference import (
    FEATURE_COLUMNS,
    InferenceDataError,
    build_feature_table,
    build_may_features,
    load_consumption,
    load_movies,
    predict,
    run_inference,
)

REPO_ROOT = Path(__file__).resolve().parents[1]


class DummyModel:
    """A stand-in for the fitted pipeline; returns a deterministic prediction per row."""

    def predict(self, X: pd.DataFrame):
        return (X["may_streams"].fillna(0) * 1.1 + 1).to_numpy()


def test_build_may_features_aggregates_by_grain():
    consumption = pd.DataFrame(
        {
            "TITLE_ID": ["t1", "t1", "t1", "t2"],
            "month": ["2026-05-01", "2026-05-01", "2026-06-01", "2026-05-01"],
            "country": ["US", "US", "US", "FR"],
            "platform": ["Netflix", "Netflix", "Netflix", "Amazon"],
            "streams": [10, 5, 999, 3],
            "total_minutes": [100, 50, 999, 30],
        }
    )
    result = build_may_features(consumption)
    assert len(result) == 2
    row = result.loc[(result.TITLE_ID == "t1") & (result.country == "US") & (result.platform == "Netflix")].iloc[0]
    assert row.may_streams == 15
    assert row.may_total_minutes == 150


def test_build_may_features_raises_when_no_may_rows():
    consumption = pd.DataFrame(
        {
            "TITLE_ID": ["t1"],
            "month": ["2026-06-01"],
            "country": ["US"],
            "platform": ["Netflix"],
            "streams": [1],
            "total_minutes": [1],
        }
    )
    with pytest.raises(InferenceDataError):
        build_may_features(consumption)


def test_build_feature_table_preserves_grain_with_missing_movie():
    may_features = pd.DataFrame(
        {
            "TITLE_ID": ["t1", "t2"],
            "country": ["US", "FR"],
            "platform": ["Netflix", "Amazon"],
            "may_streams": [10, 3],
            "may_total_minutes": [100, 30],
        }
    )
    movies = pd.DataFrame(
        {
            "TITLE_ID": ["t1"],
            "release_year": [2020],
            "runtime_minutes": [100],
            "primary_genre": ["Drama"],
            "rating_value": [7.0],
            "rating_vote_count": [1000],
        }
    )
    table = build_feature_table(may_features, movies)
    assert len(table) == 2
    assert table.loc[table.TITLE_ID == "t2", "release_year"].isna().all()


def test_predict_uses_expected_feature_columns():
    feature_table = pd.DataFrame(
        {
            "TITLE_ID": ["t1"],
            "country": ["US"],
            "platform": ["Netflix"],
            "primary_genre": ["Drama"],
            "may_streams": [10.0],
            "may_total_minutes": [100.0],
            "release_year": [2020.0],
            "runtime_minutes": [100.0],
            "rating_value": [7.0],
            "rating_vote_count": [1000.0],
        }
    )
    preds = predict(DummyModel(), feature_table)
    assert list(preds) == [10.0 * 1.1 + 1]


def test_predict_raises_on_missing_feature_columns():
    feature_table = pd.DataFrame({"TITLE_ID": ["t1"], "country": ["US"], "platform": ["Netflix"]})
    with pytest.raises(InferenceDataError):
        predict(DummyModel(), feature_table)


def test_load_movies_missing_file():
    with pytest.raises(FileNotFoundError):
        load_movies(Path("does/not/exist.csv"))


def test_load_consumption_missing_column(tmp_path: Path):
    bad_file = tmp_path / "bad.csv"
    bad_file.write_text("imdb_id,month,country,platform,streams\nt1,2026-05-01,US,Netflix,1\n")
    with pytest.raises(InferenceDataError):
        load_consumption(bad_file)


@pytest.mark.skipif(
    not (REPO_ROOT / "artifacts" / "movie_consumption_model.pkl").exists(),
    reason="Model artifact not available in this environment.",
)
def test_run_inference_end_to_end_with_real_artifact():
    output = run_inference(
        movies_path=REPO_ROOT / "data" / "inference_movies.csv",
        consumption_path=REPO_ROOT / "data" / "inference_consumption.csv",
        model_path=REPO_ROOT / "artifacts" / "movie_consumption_model.pkl",
    )
    assert set(["TITLE_ID", "country", "platform", "predicted_june_streams"]).issubset(output.columns)
    assert len(output) > 0
    assert output["predicted_june_streams"].notna().all()
    assert (output["predicted_june_streams"] >= 0).all()
