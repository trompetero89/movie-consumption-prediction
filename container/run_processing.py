"""
SageMaker Processing Job entrypoint. Wraps `src.inference.run_inference`.

SageMaker mounts:
  /opt/ml/processing/input/raw/movies/**/*.csv
  /opt/ml/processing/input/raw/consumption/**/*.csv
  /opt/ml/processing/input/model/movie_consumption_model.pkl
  /opt/ml/processing/output/predictions.csv
"""

from __future__ import annotations

import logging
import os
import sys
from pathlib import Path

sys.path.insert(0, "/opt/ml/processing/input/code")
sys.path.insert(0, str(Path(__file__).resolve().parent))

from src.inference import InferenceDataError, run_inference  # noqa: E402

INPUT_ROOT = Path(os.environ.get("PROCESSING_INPUT_ROOT", "/opt/ml/processing/input"))
OUTPUT_ROOT = Path(os.environ.get("PROCESSING_OUTPUT_ROOT", "/opt/ml/processing/output"))

logger = logging.getLogger("run_processing")


def _find_single_csv(directory: Path, label: str) -> Path:
    if not directory.exists():
        raise FileNotFoundError(f"{label} input directory not found: {directory}")
    candidates = sorted(directory.rglob("*.csv"))
    if not candidates:
        raise FileNotFoundError(f"No CSV file found under {directory} for {label}.")
    if len(candidates) > 1:
        logger.warning(
            "Multiple CSV files found under %s for %s; using the first: %s",
            directory,
            label,
            candidates[0],
        )
    return candidates[0]


def main() -> int:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )

    movies_path = _find_single_csv(INPUT_ROOT / "raw" / "movies", "movies")
    consumption_path = _find_single_csv(INPUT_ROOT / "raw" / "consumption", "consumption")
    model_path = INPUT_ROOT / "model" / "movie_consumption_model.pkl"

    try:
        output = run_inference(
            movies_path=movies_path,
            consumption_path=consumption_path,
            model_path=model_path,
        )
    except (FileNotFoundError, InferenceDataError):
        logger.exception("Inference failed due to a data/artifact problem.")
        return 3
    except Exception:  # noqa: BLE001
        logger.exception("Unexpected error during processing job.")
        return 1

    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    output_path = OUTPUT_ROOT / "predictions.csv"
    output.to_csv(output_path, index=False)
    logger.info("Wrote %d predictions to %s", len(output), output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
