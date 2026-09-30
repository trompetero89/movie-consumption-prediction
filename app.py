"""
Streamlit UI for the Movie Consumption Prediction Challenge inference solution.

Run locally:
    pip install -e ".[ui]"
    streamlit run app.py
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

import pandas as pd
import streamlit as st

sys.path.insert(0, str(Path(__file__).resolve().parent))

from src.inference import InferenceDataError, run_inference  # noqa: E402

DEFAULT_MOVIES = Path("data/inference_movies.csv")
DEFAULT_CONSUMPTION = Path("data/inference_consumption.csv")
DEFAULT_MODEL = Path("artifacts/movie_consumption_model.pkl")

st.set_page_config(page_title="Movie Consumption Predictor", page_icon="🎬", layout="wide")

st.title("Movie Consumption Prediction")
st.caption(
    "Predicts June 2026 streams per TITLE_ID × country × platform from May 2026 "
    "consumption and movie metadata, using the supplied fitted model."
)

with st.sidebar:
    st.header("Inputs")
    st.markdown(
        "Upload your own raw CSVs, or leave blank to use the supplied "
        "`data/inference_*.csv` files by default."
    )
    movies_file = st.file_uploader("Movies metadata CSV", type="csv", key="movies")
    consumption_file = st.file_uploader("Consumption CSV", type="csv", key="consumption")
    may_month = st.text_input("May input month", value="2026-05-01")
    run_button = st.button("Run inference", type="primary", use_container_width=True)


def _resolve_input_path(uploaded_file, default_path: Path, tmp_dir: Path) -> Path:
    if uploaded_file is None:
        return default_path
    path = tmp_dir / uploaded_file.name
    path.write_bytes(uploaded_file.getvalue())
    return path


if "predictions" not in st.session_state:
    st.session_state.predictions = None

if run_button:
    if not DEFAULT_MODEL.exists():
        st.error(f"Model artifact not found at {DEFAULT_MODEL}. Cannot run inference.")
    else:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = Path(tmp)
            movies_path = _resolve_input_path(movies_file, DEFAULT_MOVIES, tmp_dir)
            consumption_path = _resolve_input_path(consumption_file, DEFAULT_CONSUMPTION, tmp_dir)

            try:
                with st.spinner("Running feature engineering and prediction..."):
                    output = run_inference(
                        movies_path=movies_path,
                        consumption_path=consumption_path,
                        model_path=DEFAULT_MODEL,
                        may_month=may_month,
                    )
                st.session_state.predictions = output
                st.success(f"Generated {len(output)} predictions.")
            except FileNotFoundError as exc:
                st.error(f"Input file error: {exc}")
            except InferenceDataError as exc:
                st.error(f"Data validation error: {exc}")
            except Exception as exc:  # noqa: BLE001
                st.error(f"Unexpected error: {exc}")

predictions: pd.DataFrame | None = st.session_state.predictions

if predictions is None:
    st.info("Upload CSVs (optional) and click **Run inference** to get started.")
else:
    col1, col2, col3 = st.columns(3)
    col1.metric("Predictions", len(predictions))
    col2.metric("Distinct films", predictions["TITLE_ID"].nunique())
    col3.metric("Avg. predicted streams", f"{predictions['predicted_june_streams'].mean():.1f}")

    tab_table, tab_charts = st.tabs(["Predictions table", "Visualizations"])

    with tab_table:
        st.dataframe(predictions, use_container_width=True, height=420)
        st.download_button(
            "Download predictions.csv",
            data=predictions.to_csv(index=False).encode("utf-8"),
            file_name="predictions.csv",
            mime="text/csv",
            use_container_width=True,
        )

    with tab_charts:
        st.subheader("Top 15 films by predicted June streams")
        top_films = (
            predictions.groupby("TITLE_ID")["predicted_june_streams"]
            .sum()
            .sort_values(ascending=False)
            .head(15)
        )
        st.bar_chart(top_films)

        st.subheader("Predicted streams by platform")
        by_platform = predictions.groupby("platform")["predicted_june_streams"].sum().sort_values(ascending=False)
        st.bar_chart(by_platform)

        st.subheader("Predicted streams by country")
        by_country = predictions.groupby("country")["predicted_june_streams"].sum().sort_values(ascending=False)
        st.bar_chart(by_country)

        st.subheader("Distribution of predicted_june_streams")
        st.bar_chart(predictions["predicted_june_streams"])
