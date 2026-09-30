# Container image for the SageMaker Processing Job that runs the movie
# consumption inference pipeline (feature engineering + scoring with the
# supplied fitted model). Pinned to match artifacts/feature_schema.json
# (scikit-learn 1.8.0, Python 3.13) so the pickled model unpickles safely.

FROM python:3.13-slim

WORKDIR /opt/program

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/
COPY container/run_processing.py ./run_processing.py

ENTRYPOINT ["python", "run_processing.py"]
