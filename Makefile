.PHONY: bootstrap doctor format lint test test-ios build verify bindings check-bindings test-agenda restore restore-ocr-training restore-assistant-training restore-assistant-export
export PATH := $(CURDIR)/.tools/bin:$(HOME)/.cargo/bin:$(PATH)
bootstrap doctor format lint test:
	python3 scripts/quality.py $@

test-ios:
	python3 scripts/quality.py test-ios

build:
	python3 scripts/quality.py build simulator

verify: lint test build

bindings check-bindings:
	sh scripts/build-native.sh $@

test-agenda:
	sh scripts/test-agenda-cache.sh

restore:
	uv run --locked python scripts/fetch-models.py --tier small
	uv run --locked python scripts/fetch-ios-runtime.py
	uv run --locked python scripts/fetch-speech-model.py

restore-ocr-training:
	UV_PROJECT_ENVIRONMENT=$(CURDIR)/.local/envs/ocr uv sync --locked --project ml/training/ocr

restore-assistant-training:
	UV_PROJECT_ENVIRONMENT=$(CURDIR)/.local/envs/assistant uv sync --locked --project ml/training/assistant

restore-assistant-export:
	UV_PROJECT_ENVIRONMENT=$(CURDIR)/.local/envs/assistant-export uv sync --locked --project ml/training/assistant/export
