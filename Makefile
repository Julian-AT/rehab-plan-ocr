.PHONY: help bootstrap doctor format lint test test-tools test-ios build verify bindings check-bindings test-agenda restore convert verify-assets package restore-ocr-training restore-assistant-training restore-assistant-export
export PATH := $(CURDIR)/.tools/bin:$(HOME)/.cargo/bin:$(PATH)
TARGET ?= simulator

help:
	@echo 'Setup: make bootstrap restore convert [TARGET=simulator|device|all]'
	@echo 'Build: make build [TARGET=simulator|device]; make bindings; make check-bindings'
	@echo 'Checks: make lint test test-tools test-ios verify-assets; make test-<probe>'
	@echo 'Package an existing archive: make package'
	@echo 'Model development: make restore-ocr-training restore-assistant-training restore-assistant-export'

bootstrap doctor format lint test:
	python3 tooling/dev/quality.py $@

test-tools:
	python3 tooling/dev/quality.py test-tools

test-ios:
	python3 tooling/dev/quality.py test-ios

build:
	python3 tooling/dev/quality.py build $(TARGET)

verify: lint test build

bindings check-bindings:
	sh tooling/build/build-native.sh $@

test-agenda:
	sh tooling/checks/test-agenda.sh

restore:
	uv sync --locked
	uv sync --locked --script tooling/build/export-victoria.py
	uv run --locked --with cmake==3.31.6 cmake --version
	uv run --locked python tooling/build/fetch-models.py --tier small
	uv run --locked python tooling/build/fetch-ios-runtime.py
	python3 tooling/build/build-phonemizer.py --source-only
	python3 tooling/build/fetch-speech-model.py restore

convert:
	@case "$(TARGET)" in \
	  simulator) python3 tooling/build/build-phonemizer.py --offline host aarch64-apple-ios-sim ;; \
	  device) python3 tooling/build/build-phonemizer.py --offline host aarch64-apple-ios ;; \
	  all) python3 tooling/build/build-phonemizer.py --offline host aarch64-apple-ios aarch64-apple-ios-sim ;; \
	  *) echo 'TARGET must be simulator, device or all' >&2; exit 2 ;; \
	esac
	python3 tooling/build/fetch-speech-model.py convert

verify-assets:
	python3 tooling/build/verify-native-assets.py $(TARGET)

package:
	python3 tooling/release/package-native.py

NATIVE_PROBES := $(patsubst tooling/checks/%.sh,%,$(wildcard tooling/checks/test-*.sh))
.PHONY: $(NATIVE_PROBES)
$(filter-out test-agenda,$(NATIVE_PROBES)):
	sh tooling/checks/$@.sh $(TEST_ARGS)

restore-ocr-training:
	UV_PROJECT_ENVIRONMENT=$(CURDIR)/.local/envs/ocr uv sync --locked --project ml/training/ocr

restore-assistant-training:
	UV_PROJECT_ENVIRONMENT=$(CURDIR)/.local/envs/assistant uv sync --locked --project ml/training/assistant

restore-assistant-export:
	UV_PROJECT_ENVIRONMENT=$(CURDIR)/.local/envs/assistant-export uv sync --locked --project ml/training/assistant/export
