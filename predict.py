#!/usr/bin/env python
"""
CLI entrypoint for the Movie Consumption Prediction Challenge inference solution.

python predict.py \
    --movies data/inference_movies.csv \
    --consumption data/inference_consumption.csv \
    --model artifacts/movie_consumption_model.pkl \
    --output output/predictions.csv
"""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from src.inference import InferenceDataError, run_inference  # noqa: E402


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--movies", type=Path, default=Path("data/inference_movies.csv"), help="Path to raw movie metadata CSV.")
    parser.add_argument("--consumption", type=Path, default=Path("data/inference_consumption.csv"), help="Path to raw consumption CSV.")
    parser.add_argument("--model", type=Path, default=Path("artifacts/movie_consumption_model.pkl"), help="Path to the fitted model pickle.")
    parser.add_argument("--output", type=Path, default=Path("output/predictions.csv"), help="Path to write the output CSV.")
    parser.add_argument("--may-month", type=str, default="2026-05-01", help="Month string (YYYY-MM-DD) identifying the May input month.")
    parser.add_argument("--log-level", type=str, default="INFO", choices=["DEBUG", "INFO", "WARNING", "ERROR"])
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )
    logger = logging.getLogger("predict")

    try:
        output = run_inference(
            movies_path=args.movies,
            consumption_path=args.consumption,
            model_path=args.model,
            may_month=args.may_month,
        )
    except FileNotFoundError as exc:
        logger.error("Input file error: %s", exc)
        return 2
    except InferenceDataError as exc:
        logger.error("Data validation error: %s", exc)
        return 3
    except Exception:  
        logger.exception("Unexpected error while running inference.")
        return 1

    args.output.parent.mkdir(parents=True, exist_ok=True)
    output.to_csv(args.output, index=False)
    logger.info("Wrote %d predictions to %s", len(output), args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
