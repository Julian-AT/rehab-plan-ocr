.PHONY: help bootstrap doctor format lint test test-tools test-ios build verify bindings check-bindings test-agenda restore convert verify-assets package restore-ocr-training restore-assistant-training restore-assistant-export
export PATH := $(CURDIR)/.tools/bin:$(HOME)/.cargo/bin:$(PATH)
# Apple Make resolves bare executables before applying this exported PATH.
# env performs lookup in the recipe environment, including bootstrapped tools.
TARGET ?= simulator

help:
	@echo 'Setup: make bootstrap restore convert [TARGET=simulator|device|all]'
	@echo 'Build: make build [TARGET=simulator|device]; make bindings; make check-bindings'
	@echo 'Checks: make lint test test-tools test-ios verify-assets; make test-<probe>'
	@echo 'Visual baseline: make test-visual-baseline TEST_ARGS="--run .local/runs/<new-run>" (serial disposable simulator)'
	@echo 'Accessibility: make test-reduced-motion (actual system setting, restored after the test)'
	@echo 'Audio isolation: make test-audio-runtime TEST_ARGS="--run .local/runs/<new-run>" (serial simulator use)'
	@echo 'Listening samples: make prepare-listening RUN=.local/runs/<new-run> (host previews, human assessment pending)'
	@echo 'Packaging: make verify-bundle APP_BUNDLE=<built-app> [TARGET=simulator|device]; make package'
	@echo 'Dependencies: make inventory-runtime (explicit update); make verify-runtime-inventory; make check-runtime-inventory'
	@echo 'Hosted CI: make ci-status; make test-ci-monitor; node tooling/dev/ci_monitor.cjs --help'
	@echo 'Model development: make restore-ocr-training restore-assistant-training restore-assistant-export'
	@echo 'Assistant smoke: make restore-assistant-assets build-assistant-runtime; make assistant-smoke RUN=<new-directory>'
	@echo 'Native assistant trial: make build-assistant-native; make test-assistant-native TEST_ARGS="--run .local/runs/<new-run> [--simulator <disposable-id>]"'
	@echo 'Common provider app trial: make build-assistant-trial; make test-assistant-app-trial TEST_ARGS="--run .local/runs/<new-run> --simulator <disposable-id>"'
	@echo 'OCR app trial: make test-recognition-app-trial TEST_ARGS="--run .local/runs/<new-run> --simulator <disposable-id>" (baseline and frozen experiment)'
	@echo 'OCR synthetic training data: make prepare-ocr-synthetic SOURCE_DATASET=<generated-tables> DATASET=<new-directory>'

bootstrap doctor format lint test:
	python3 tooling/dev/quality.py $@

test-tools:
	python3 tooling/dev/quality.py test-tools

.PHONY: ci-status test-ci-monitor
ci-status:
	node tooling/dev/ci_monitor.cjs runs

test-ci-monitor:
	node --test tooling/dev/tests/ci_monitor.test.cjs

test-ios:
	python3 tooling/dev/quality.py test-ios

build:
	python3 tooling/dev/quality.py build $(TARGET)

verify: lint test build

bindings check-bindings:
	sh tooling/build/build-native.sh $@

test-agenda:
	sh tooling/checks/test-agenda.sh

.PHONY: prepare-listening refresh-listening transcribe-listening setup-speech-evaluation
prepare-listening:
	@test -n "$(RUN)" || { echo 'Set RUN to a new directory below .local/runs'; exit 2; }
	/usr/bin/env cargo build --locked -p reha-cli --example voice_samples --features voice
	/usr/bin/env uv run --locked python ml/evaluation/speech/listening.py --run "$(RUN)"

refresh-listening:
	@test -n "$(RUN)" || { echo 'Set RUN to an existing listening export'; exit 2; }
	/usr/bin/env uv run --locked python ml/evaluation/speech/listening_form.py --run "$(RUN)"

transcribe-listening:
	@test -n "$(RUN)" -a -n "$(LISTENING)" || { echo 'Set RUN and LISTENING to local evaluation directories'; exit 2; }
	/usr/bin/env uv run --locked python ml/evaluation/speech/transcribe.py --run "$(RUN)" --listening "$(LISTENING)"

setup-speech-evaluation:
	@test -n "$(RUN)" || { echo 'Set RUN to a new local setup directory'; exit 2; }
	/usr/bin/env uv run --locked python ml/evaluation/speech/transcribe.py --run "$(RUN)" --setup

restore:
	/usr/bin/env uv sync --locked
	/usr/bin/env uv sync --locked --script tooling/build/export-victoria.py
	/usr/bin/env uv run --locked --with cmake==3.31.6 cmake --version
	/usr/bin/env uv run --locked python tooling/build/fetch-models.py --tier small
	/usr/bin/env uv run --locked python tooling/build/fetch-ios-runtime.py
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

.PHONY: verify-bundle
verify-bundle:
	@test -n "$(APP_BUNDLE)" || { echo 'Set APP_BUNDLE to a built app directory'; exit 2; }
	python3 tooling/release/bundle.py "$(APP_BUNDLE)" --target "$(TARGET)"

.PHONY: inventory-runtime verify-runtime-inventory check-runtime-inventory
inventory-runtime:
	python3 tooling/release/runtime_inventory.py generate

verify-runtime-inventory:
	python3 tooling/release/runtime_inventory.py verify $(if $(APP_BUNDLE),--bundle "$(APP_BUNDLE)")

check-runtime-inventory:
	python3 tooling/release/runtime_inventory.py check

.PHONY: verify-privacy
verify-privacy:
	@test -n "$(APP_BUNDLE)" || { echo 'Set APP_BUNDLE to a built app directory'; exit 2; }
	python3 tooling/release/privacy.py "$(APP_BUNDLE)"

.PHONY: snapshot-persistence compare-persistence
snapshot-persistence:
	@test -n "$(SNAPSHOT_ROOT)" -a -n "$(OUTPUT)" || { echo 'Set SNAPSHOT_ROOT to copied containers and OUTPUT below .local'; exit 2; }
	/usr/bin/env uv run --locked python tooling/release/persistence.py snapshot --root "$(SNAPSHOT_ROOT)" --output "$(OUTPUT)"

compare-persistence:
	@test -n "$(BEFORE)" -a -n "$(SNAPSHOT)" -a -n "$(AFTER)" -a -n "$(OUTPUT)" || { echo 'Set BEFORE, SNAPSHOT, AFTER and a new OUTPUT below .local'; exit 2; }
	/usr/bin/env uv run --locked python tooling/release/persistence.py compare --before "$(BEFORE)" --snapshot "$(SNAPSHOT)" --after "$(AFTER)" --output "$(OUTPUT)"

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

ASSISTANT_NATIVE_TARGETS ?= host simulator
.PHONY: build-assistant-native build-assistant-trial
build-assistant-native:
	python3 tooling/build/build-assistant-native.py $(ASSISTANT_NATIVE_TARGETS)

build-assistant-trial:
	python3 tooling/build/build-assistant-trial.py --model "$(or $(ASSISTANT_TRIAL_MODEL),tuned)"

assistant-smoke:
	@test -n "$(RUN)" || { echo 'Set RUN to a new directory below .local/runs'; exit 2; }
	HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 .local/envs/assistant/bin/python ml/training/assistant/smoke.py --output "$(RUN)" --execute

evaluate-assistant:
	@test -n "$(RUN)" || { echo 'Set RUN to the completed smoke directory'; exit 2; }
	HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 .local/envs/assistant/bin/python ml/evaluation/conversation/compare.py --run "$(RUN)" --output "$(RUN)/evaluation"

.PHONY: audit-assistant-pairs
audit-assistant-pairs:
	@test -n "$(RUN)" -a -n "$(MODEL_CARD)" -a -n "$(OUTPUT)" || { echo 'Set RUN, MODEL_CARD and a new OUTPUT below .local/runs'; exit 2; }
	/usr/bin/env uv run --locked python ml/evaluation/conversation/paired.py --run "$(RUN)" --model-card "$(MODEL_CARD)" --output "$(OUTPUT)"

MIGRATION ?= .local/migrations/private-storage.json
.PHONY: inventory-private migrate-private
inventory-private:
	python3 tooling/dev/migrate-private.py plan --manifest "$(MIGRATION)"

migrate-private:
	python3 tooling/dev/migrate-private.py apply --manifest "$(MIGRATION)"

.PHONY: intake
intake:
	@test -n "$(REQUEST)" -a -n "$(BATCH)" || { echo 'Set REQUEST and a new BATCH below .local/datasets/incoming'; exit 2; }
	/usr/bin/env uv run --locked python ml/data/annotation/intake.py "$(REQUEST)" "$(BATCH)"

OCR_MODE ?= frozen-backbone
OCR_EPOCHS ?= 100
OCR_PATIENCE ?= 5
FONT ?= /System/Library/Fonts/Supplemental/Arial.ttf
SYNTHETIC_COUNT ?= 200
SYNTHETIC_SOURCES ?= 2
FOLD ?= 0
.PHONY: generate-synthetic
generate-synthetic:
	@test -n "$(DATASET)" || { echo 'Set DATASET to a new synthetic export directory'; exit 2; }
	/usr/bin/env uv run --locked python ml/data/synthesis/synthetic-plans.py "$(DATASET)" --font "$(FONT)" --count "$(SYNTHETIC_COUNT)"

.PHONY: verify-augmentation
verify-augmentation:
	@test -n "$(SOURCE_DATASET)" -a -n "$(RUN)" || { echo 'Set SOURCE_DATASET and a new verification RUN directory'; exit 2; }
	/usr/bin/env uv run --locked python ml/data/augmentation/verify.py --source "$(SOURCE_DATASET)" --output "$(RUN)" --font "$(FONT)" --limit "$(SYNTHETIC_SOURCES)"

.PHONY: restore-ocr-assets prepare-ocr-smoke prepare-ocr-data prepare-ocr-synthetic train-ocr resume-ocr export-ocr
restore-ocr-assets: restore-ocr-training
	.local/envs/ocr/bin/python ml/training/ocr/restore.py

prepare-ocr-smoke:
	@test -n "$(DATASET)" || { echo 'Set DATASET to a new directory below .local'; exit 2; }
	.local/envs/ocr/bin/python ml/training/ocr/prepare.py --output "$(DATASET)" --smoke-font "$(FONT)"

prepare-ocr-data:
	@test -n "$(DATASET)" -a -n "$(SOURCE_DATASET)" || { echo 'Set DATASET and SOURCE_DATASET to reviewed local references'; exit 2; }
	.local/envs/ocr/bin/python ml/training/ocr/prepare.py --output "$(DATASET)" --references "$(SOURCE_DATASET)" --fold "$(FOLD)"

prepare-ocr-synthetic:
	@test -n "$(DATASET)" -a -n "$(SOURCE_DATASET)" || { echo 'Set DATASET and SOURCE_DATASET to local synthetic tables'; exit 2; }
	.local/envs/ocr/bin/python ml/training/ocr/prepare.py --output "$(DATASET)" --synthetic "$(SOURCE_DATASET)" --font "$(FONT)"

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
