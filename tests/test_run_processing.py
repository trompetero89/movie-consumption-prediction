"""
Tests for the SageMaker Processing Job entrypoint (container/run_processing.py).

Simulates the SageMaker-mounted directory layout using temporary directories.
"""

from __future__ import annotations

import importlib
import shutil
import sys
from pathlib import Path

import pandas as pd
import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
CONTAINER_DIR = REPO_ROOT / "container"

MODEL_PATH = REPO_ROOT / "artifacts" / "movie_consumption_model.pkl"


@pytest.mark.skipif(not MODEL_PATH.exists(), reason="Model artifact not available in this environment.")
def test_run_processing_end_to_end(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    input_root = tmp_path / "input"
    output_root = tmp_path / "output"

    (input_root / "raw" / "movies").mkdir(parents=True)
    (input_root / "raw" / "consumption").mkdir(parents=True)
    (input_root / "model").mkdir(parents=True)

    shutil.copy(REPO_ROOT / "data" / "inference_movies.csv", input_root / "raw" / "movies")
    shutil.copy(REPO_ROOT / "data" / "inference_consumption.csv", input_root / "raw" / "consumption")
    shutil.copy(MODEL_PATH, input_root / "model")

    monkeypatch.setenv("PROCESSING_INPUT_ROOT", str(input_root))
    monkeypatch.setenv("PROCESSING_OUTPUT_ROOT", str(output_root))
    monkeypatch.syspath_prepend(str(CONTAINER_DIR))
    monkeypatch.syspath_prepend(str(REPO_ROOT))

    # Reimport fresh so the module re-reads the env vars set above.
    sys.modules.pop("run_processing", None)
    run_processing = importlib.import_module("run_processing")

    exit_code = run_processing.main()

    assert exit_code == 0
    output_file = output_root / "predictions.csv"
    assert output_file.exists()

    output = pd.read_csv(output_file)
    assert list(output.columns) == ["TITLE_ID", "country", "platform", "predicted_june_streams"]
    assert len(output) == 321
    assert output["predicted_june_streams"].notna().all()


def test_find_single_csv_raises_when_missing(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.syspath_prepend(str(CONTAINER_DIR))
    sys.modules.pop("run_processing", None)
    run_processing = importlib.import_module("run_processing")

    with pytest.raises(FileNotFoundError):
        run_processing._find_single_csv(tmp_path / "does-not-exist", "movies")
