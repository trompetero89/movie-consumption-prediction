.PHONY: setup predict test ui clean

VENV := .venv
PYTHON := $(VENV)/bin/python3.13

setup:
	python3.13 -m venv $(VENV)
	$(PYTHON) -m pip install --upgrade pip -q
	$(PYTHON) -m pip install -e ".[dev]" -q

predict:
	$(PYTHON) predict.py \
		--movies data/inference_movies.csv \
		--consumption data/inference_consumption.csv \
		--model artifacts/movie_consumption_model.pkl \
		--output output/predictions.csv

test:
	$(PYTHON) -m pytest tests/ -v

ui:
	$(PYTHON) -m pip install -e ".[ui]" -q
	$(PYTHON) -m streamlit run app.py

clean:
	rm -rf $(VENV) .pytest_cache **/__pycache__ output/predictions.csv
