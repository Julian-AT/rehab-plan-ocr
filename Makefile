.PHONY: help bootstrap doctor format lint test test-tools test-ios build verify bindings check-bindings test-agenda restore convert verify-assets package restore-ocr-training restore-assistant-training restore-assistant-export
export PATH := $(CURDIR)/.tools/bin:$(HOME)/.cargo/bin:$(PATH)
TARGET ?= simulator

help:
	@echo 'Setup: make bootstrap restore convert [TARGET=simulator|device|all]'
	@echo 'Build: make build [TARGET=simulator|device]; make bindings; make check-bindings'
	@echo 'Checks: make lint test test-tools test-ios verify-assets; make test-<probe>'
	@echo 'Package an existing archive: make package'
	@echo 'Model development: make restore-ocr-training restore-assistant-training restore-assistant-export'
	@echo 'Assistant smoke: make restore-assistant-assets build-assistant-runtime; make assistant-smoke RUN=<new-directory>'

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

.PHONY: restore-assistant-assets build-assistant-runtime assistant-smoke evaluate-assistant
restore-assistant-assets: restore-assistant-training restore-assistant-export
	.local/envs/assistant/bin/python ml/training/assistant/restore.py
	python3 ml/training/assistant/runtime.py restore

build-assistant-runtime:
	python3 ml/training/assistant/runtime.py build

assistant-smoke:
	@test -n "$(RUN)" || { echo 'Set RUN to a new directory below .local/runs'; exit 2; }
	HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 .local/envs/assistant/bin/python ml/training/assistant/smoke.py --output "$(RUN)" --execute

evaluate-assistant:
	@test -n "$(RUN)" || { echo 'Set RUN to the completed smoke directory'; exit 2; }
	HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 .local/envs/assistant/bin/python ml/evaluation/conversation/compare.py --run "$(RUN)" --output "$(RUN)/evaluation"

MIGRATION ?= .local/migrations/private-storage.json
.PHONY: inventory-private migrate-private
inventory-private:
	python3 tooling/dev/migrate-private.py plan --manifest "$(MIGRATION)"

migrate-private:
	python3 tooling/dev/migrate-private.py apply --manifest "$(MIGRATION)"

.PHONY: intake
intake:
	@test -n "$(REQUEST)" -a -n "$(BATCH)" || { echo 'Set REQUEST and a new BATCH below .local/datasets/incoming'; exit 2; }
	uv run --locked python ml/data/annotation/intake.py "$(REQUEST)" "$(BATCH)"

OCR_MODE ?= frozen-backbone
OCR_EPOCHS ?= 100
OCR_PATIENCE ?= 5
FONT ?= /System/Library/Fonts/Supplemental/Arial.ttf
FOLD ?= 0
.PHONY: restore-ocr-assets prepare-ocr-smoke prepare-ocr-data train-ocr resume-ocr export-ocr
restore-ocr-assets: restore-ocr-training
	.local/envs/ocr/bin/python ml/training/ocr/restore.py

prepare-ocr-smoke:
	@test -n "$(DATASET)" || { echo 'Set DATASET to a new directory below .local'; exit 2; }
	.local/envs/ocr/bin/python ml/training/ocr/prepare.py --output "$(DATASET)" --smoke-font "$(FONT)"

prepare-ocr-data:
	@test -n "$(DATASET)" -a -n "$(SOURCE_DATASET)" || { echo 'Set DATASET and SOURCE_DATASET to reviewed local references'; exit 2; }
	.local/envs/ocr/bin/python ml/training/ocr/prepare.py --output "$(DATASET)" --references "$(SOURCE_DATASET)" --fold "$(FOLD)"

train-ocr:
	@test -n "$(RUN)" -a -n "$(DATASET)" || { echo 'Set RUN and DATASET'; exit 2; }
	.local/envs/ocr/bin/python ml/training/ocr/train.py start --run "$(RUN)" --dataset "$(DATASET)/dataset.json" --mode "$(OCR_MODE)" --max-epochs "$(OCR_EPOCHS)" --patience "$(OCR_PATIENCE)"

resume-ocr:
	@test -n "$(RUN)" || { echo 'Set RUN to an existing training run'; exit 2; }
	.local/envs/ocr/bin/python ml/training/ocr/train.py resume --run "$(RUN)"

export-ocr:
	@test -n "$(RUN)" || { echo 'Set RUN to a completed training run'; exit 2; }
	.local/envs/ocr/bin/python ml/training/ocr/export.py --run "$(RUN)"

ASSISTANT_PER_FAMILY ?= 16
ASSISTANT_EPOCHS ?= 20
ASSISTANT_PATIENCE ?= 3
ASSISTANT_LAYERS ?= 8
.PHONY: prepare-assistant-data train-assistant resume-assistant export-assistant
prepare-assistant-data:
	@test -n "$(DATASET)" || { echo 'Set DATASET to a new directory below .local'; exit 2; }
	python3 ml/training/assistant/prepare.py --output "$(DATASET)" --per-family "$(ASSISTANT_PER_FAMILY)"

train-assistant:
	@test -n "$(RUN)" -a -n "$(DATASET)" || { echo 'Set RUN and DATASET'; exit 2; }
	HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 .local/envs/assistant/bin/python ml/training/assistant/train.py start --run "$(RUN)" --dataset "$(DATASET)/dataset.json" --max-epochs "$(ASSISTANT_EPOCHS)" --patience "$(ASSISTANT_PATIENCE)" --num-layers "$(ASSISTANT_LAYERS)"

resume-assistant:
	@test -n "$(RUN)" || { echo 'Set RUN to an existing training run'; exit 2; }
	HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 .local/envs/assistant/bin/python ml/training/assistant/train.py resume --run "$(RUN)"

export-assistant:
	@test -n "$(RUN)" || { echo 'Set RUN to a completed training run'; exit 2; }
	HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 .local/envs/assistant/bin/python ml/training/assistant/export.py --run "$(RUN)"

.PHONY: verify-assistant-interruption
verify-assistant-interruption:
	@test -n "$(RUN)" -a -n "$(SOURCE_RUN)" -a -n "$(CONTINUOUS_RUN)" || { echo 'Set RUN, SOURCE_RUN and CONTINUOUS_RUN to local proof runs'; exit 2; }
	HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 .local/envs/assistant/bin/python ml/training/assistant/verify_interruption.py --source "$(SOURCE_RUN)" --continuous "$(CONTINUOUS_RUN)" --run "$(RUN)"
