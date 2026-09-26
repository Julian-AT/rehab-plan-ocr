.PHONY: help bootstrap doctor format lint test test-tools test-ios build verify bindings check-bindings test-agenda restore restore-rust convert verify-assets package restore-ocr-training restore-assistant-training restore-assistant-export
WORKSPACE_TOOLS := $(shell python3 tooling/dev/workspace.py path tools)
export PATH := $(WORKSPACE_TOOLS)/bin:$(HOME)/.cargo/bin:$(PATH)
export RUSTUP_TOOLCHAIN := $(shell python3 tooling/dev/workspace.py toolchain)
export CARGO_INCREMENTAL := 0
export CARGO_PROFILE_DEV_DEBUG := 0
ifndef CARGO_TARGET_DIR
export CARGO_TARGET_DIR := $(shell python3 tooling/dev/workspace.py path cargo)
endif
ifndef UV_PROJECT_ENVIRONMENT
export UV_PROJECT_ENVIRONMENT := $(shell python3 tooling/dev/workspace.py path python)
endif
export REHA_IOS_BUILD_DIR := $(shell python3 tooling/dev/workspace.py path ios)
ifeq ($(strip $(WORKSPACE_TOOLS)),)
$(error Workspace tools path is unresolved; run python3 tooling/dev/workspace.py check)
endif
ifeq ($(strip $(CARGO_TARGET_DIR)),)
$(error Workspace Cargo path is unresolved; run python3 tooling/dev/workspace.py check)
endif
ifeq ($(strip $(UV_PROJECT_ENVIRONMENT)),)
$(error Workspace Python path is unresolved; run python3 tooling/dev/workspace.py check)
endif
ifeq ($(strip $(REHA_IOS_BUILD_DIR)),)
$(error Workspace iOS path is unresolved; run python3 tooling/dev/workspace.py check)
endif
# Apple Make resolves bare executables before applying this exported PATH.
# env performs lookup in the recipe environment, including bootstrapped tools.
TARGET ?= simulator
export RELEASE_RUN
.DEFAULT_GOAL := help

WORKSPACE_MANIFEST ?= .local/migrations/workspace.json
.PHONY: check-workspace inventory-workspace migrate-workspace
check-workspace:
	python3 tooling/dev/workspace.py check --canonical

inventory-workspace:
	python3 tooling/dev/workspace.py plan --manifest "$(WORKSPACE_MANIFEST)"

migrate-workspace:
	python3 tooling/dev/workspace.py apply --manifest "$(WORKSPACE_MANIFEST)"

.PHONY: inventory-repository
inventory-repository:
	python3 tooling/dev/repository_inventory.py $(if $(INVENTORY),--output "$(INVENTORY)")

CLEANUP_MANIFEST ?= .local/maintenance/cleanup.json
MODEL_OBJECT_MANIFEST ?= .local/maintenance/model-objects.json
.PHONY: inventory-model-objects coalesce-model-objects
inventory-model-objects:
	python3 tooling/dev/model_objects.py plan --manifest "$(MODEL_OBJECT_MANIFEST)"

coalesce-model-objects:
	python3 tooling/dev/model_objects.py apply --manifest "$(MODEL_OBJECT_MANIFEST)"

# Metadata inventory is read-only; plan/apply require a quiet model/build window.
.PHONY: inventory-checkpoints plan-checkpoints clean-checkpoints test-checkpoints
inventory-checkpoints:
	@test -n "$(RUN)" || { echo 'Set RUN to an existing .local/runs training directory'; exit 2; }
	python3 tooling/dev/checkpoints.py inventory --run "$(RUN)" $(if $(CHECKPOINT_MANIFEST),--manifest "$(CHECKPOINT_MANIFEST)")

plan-checkpoints:
	@test -n "$(RUN)" -a -n "$(CHECKPOINT_MANIFEST)" || { echo 'Set RUN and a new CHECKPOINT_MANIFEST below .local/maintenance/checkpoints'; exit 2; }
	python3 tooling/dev/checkpoints.py plan --run "$(RUN)" --manifest "$(CHECKPOINT_MANIFEST)"

clean-checkpoints:
	@test -n "$(CHECKPOINT_MANIFEST)" || { echo 'Set CHECKPOINT_MANIFEST to the checked plan'; exit 2; }
	python3 tooling/dev/checkpoints.py apply --manifest "$(CHECKPOINT_MANIFEST)"

test-checkpoints:
	python3 tooling/dev/tests/test-checkpoints.py

PEAK_GIB ?= 0
.PHONY: probe-document probe-speech-availability benchmark-voice-rules
PROBE_MODE ?= text
probe-document:
	@test -n "$(RUN)" -a -n "$(INPUT)" || { echo 'Set RUN below .local/runs and INPUT to a local image'; exit 2; }
	python3 tooling/dev/probes.py document --run "$(RUN)" --mode "$(PROBE_MODE)" --input "$(INPUT)"

probe-speech-availability:
	@test -n "$(RUN)" || { echo 'Set RUN to a new directory below .local/runs'; exit 2; }
	python3 tooling/dev/probes.py speech-availability --run "$(RUN)"

benchmark-voice-rules:
	@test -n "$(RUN)" || { echo 'Set RUN to a new directory below .local/runs'; exit 2; }
	python3 tooling/dev/probes.py voice-rules --run "$(RUN)"

.PHONY: inventory-artifacts clean-artifacts check-storage
inventory-artifacts:
	python3 tooling/dev/artifacts.py plan --manifest "$(CLEANUP_MANIFEST)"

clean-artifacts:
	python3 tooling/dev/artifacts.py apply --manifest "$(CLEANUP_MANIFEST)"

check-storage:
	python3 tooling/dev/artifacts.py space --peak-gib "$(PEAK_GIB)"


# Reserve is additional to the expected temporary build/export/checkpoint peak.
# Direct low-level scripts retain their historical recovery contracts; supported
# heavy workflows enter here before generating any new artifacts.
build test-ios build-assistant-native build-assistant-runtime build-assistant-trial: PEAK_GIB = 4
train-ocr resume-ocr: PEAK_GIB = 4
train-assistant resume-assistant: PEAK_GIB = 3
export-ocr export-assistant assistant-smoke: PEAK_GIB = 8
build test-ios build-assistant-native build-assistant-runtime build-assistant-trial \
train-ocr resume-ocr train-assistant resume-assistant export-ocr export-assistant assistant-smoke: check-storage

help:
	@echo 'Workspace: make check-workspace; make inventory-workspace migrate-workspace WORKSPACE_MANIFEST=<new-local-manifest>'
	@echo 'Inventory: make inventory-repository; make inventory-artifacts; make clean-artifacts; make check-storage PEAK_GIB=4'
	@echo 'Checkpoints: make inventory-checkpoints RUN=<training-run>; plan-checkpoints/clean-checkpoints CHECKPOINT_MANIFEST=<new-plan>'
	@echo 'Apple probes: make probe-document probe-speech-availability benchmark-voice-rules RUN=<new-local-run> (document needs INPUT)'
	@echo 'Setup: make bootstrap restore convert [TARGET=simulator|device|all]'
	@echo 'Rust downloads only: make restore-rust; offline repeat: CARGO_NET_OFFLINE=true UV_OFFLINE=true make build'
	@echo 'Build: make build [TARGET=simulator|device]; make bindings; make check-bindings'
	@echo 'Checks: make lint test test-tools test-ios verify-assets; make test-<probe>'
	@echo 'Visual baseline: make test-visual-baseline TEST_ARGS="--run .local/runs/<new-run>" (serial disposable simulator)'
	@echo 'Accessibility: make test-reduced-motion (actual system setting, restored after the test)'
	@echo 'Audio isolation: make test-audio-runtime TEST_ARGS="--run .local/runs/<new-run>" (serial simulator use)'
	@echo 'Listening samples: make prepare-listening RUN=.local/runs/<new-run> (host previews, human assessment pending)'
	@echo 'Experimental Victoria: make restore-experimental-speech convert-experimental-speech; make prepare-listening-experimental RUN=<new-local-run>'
	@echo 'Archive: make archive RELEASE_RUN=.local/releases/<new-name>; package again only into a new run with explicit RELEASE_ARCHIVE=<existing-archive>'
	@echo 'Packaging: make verify-bundle APP_BUNDLE=<built-app> [TARGET=simulator|device]; make package RELEASE_RUN=<reserved-run>'
	@echo 'Dependencies: make inventory-runtime (explicit update); make verify-runtime-inventory; make check-runtime-inventory'
	@echo 'Dependency audit: make download-dependency-audit setup-dependency-audit; update-dependency-advisories AUDIT_DB=<new-snapshot>; audit-dependencies additionally requires AUDIT_COMMIT and AUDIT_RUN'
	@echo 'Hosted CI: make ci-status; make test-ci-monitor; node tooling/dev/ci_monitor.cjs --help'
	@echo 'Model development: make restore-ocr-training restore-assistant-training restore-assistant-export'
	@echo 'Assistant smoke: make restore-assistant-assets build-assistant-runtime; make assistant-smoke RUN=<new-directory>'
	@echo 'Native assistant trial: make build-assistant-native; make test-assistant-native TEST_ARGS="--run .local/runs/<new-run> [--simulator <disposable-id>]"'
	@echo 'Common provider app trial: make build-assistant-trial; make test-assistant-app-trial TEST_ARGS="--run .local/runs/<new-run> --simulator <disposable-id>"'
	@echo 'OCR app trial: make test-recognition-app-trial TEST_ARGS="--run .local/runs/<new-run> --simulator <disposable-id>" (baseline and frozen experiment)'
	@echo 'OCR synthetic training data: make prepare-ocr-synthetic SOURCE_DATASET=<generated-tables> DATASET=<new-directory>'
	@echo 'Isolated OCR convolution fixture: make prepare-ocr-convolution-lowering DIAGNOSTIC_RUN=.local/runs/<new-experiment> (preparation only)'
	@echo 'Execute prepared OCR convolution fixture: make diagnose-ocr-convolution-lowering DIAGNOSTIC_RUN=.local/runs/<prepared-experiment>'
	@echo 'Human reference review: make reference-review-packet DATASET=<private-root> RUN=.local/runs/<new-packet> (creates no approvals)'
	@echo 'Reference privacy: make reference-privacy-draft DATASET=<reference-root>; reference-privacy-approve additionally requires SOURCE_SHA256 and REVIEWER'

.PHONY: reference-review-packet
reference-review-packet:
	@test -n "$(DATASET)" -a -n "$(RUN)" || { echo 'Set DATASET to the private root and RUN to a new private review packet'; exit 2; }
	/usr/bin/env uv run --locked python ml/data/annotation/review_packet.py --root "$(DATASET)" --output "$(RUN)"

.PHONY: reference-privacy-draft reference-privacy-approve
reference-privacy-draft:
	@test -n "$(DATASET)" || { echo 'Set DATASET to the private reference root'; exit 2; }
	/usr/bin/env uv run --locked python ml/data/annotation/reference-data.py --root "$(DATASET)" privacy-draft

reference-privacy-approve:
	@test -n "$(DATASET)" -a -n "$(SOURCE_SHA256)" -a -n "$(REVIEWER)" || { echo 'Set DATASET, SOURCE_SHA256 and REVIEWER after human privacy review'; exit 2; }
	/usr/bin/env uv run --locked python ml/data/annotation/reference-data.py --root "$(DATASET)" privacy-approve "$(SOURCE_SHA256)" --reviewer "$(REVIEWER)"

bootstrap doctor format lint test:
	python3 tooling/dev/quality.py $@

test-tools:
	python3 tooling/dev/quality.py test-tools

# Audit tool restoration and advisory updates are explicit network/setup steps.
.PHONY: download-dependency-audit setup-dependency-audit update-dependency-advisories audit-dependencies test-dependency-audit
download-dependency-audit:
	python3 tooling/release/audit_dependencies.py download

setup-dependency-audit:
	python3 tooling/release/audit_dependencies.py setup $(if $(AUDIT_ARCHIVE),--archive "$(AUDIT_ARCHIVE)")

update-dependency-advisories:
	@test -n "$(AUDIT_DB)" || { echo 'Set AUDIT_DB to a new advisory snapshot directory'; exit 2; }
	python3 tooling/release/audit_dependencies.py update --db "$(AUDIT_DB)"

audit-dependencies:
	@test -n "$(AUDIT_DB)" -a -n "$(AUDIT_COMMIT)" -a -n "$(AUDIT_RUN)" || { echo 'Set AUDIT_DB, its exact AUDIT_COMMIT and a new AUDIT_RUN'; exit 2; }
	python3 tooling/release/audit_dependencies.py run --db "$(AUDIT_DB)" --commit "$(AUDIT_COMMIT)" --output "$(AUDIT_RUN)"

test-dependency-audit:
	/usr/bin/env uv run --locked python tooling/release/tests/test-audit-dependencies.py

.PHONY: ci-status test-ci-monitor
ci-status:
	node tooling/dev/ci_monitor.cjs runs

test-ci-monitor:
	node --test tooling/dev/tests/ci_monitor.test.cjs

test-ios:
	python3 tooling/dev/quality.py test-ios

.PHONY: test-product-generation
test-product-generation:
	python3 tooling/build/tests/test-product-generation.py

build:
	python3 tooling/dev/quality.py build $(TARGET)

verify: lint test build

bindings check-bindings:
	sh tooling/build/build-native.sh $@

test-agenda:
	sh tooling/checks/test-agenda.sh

.PHONY: prepare-listening prepare-listening-experimental refresh-listening transcribe-listening setup-speech-evaluation
SPEECH_LOCALE ?= de-AT
prepare-listening:
	@test -n "$(RUN)" || { echo 'Set RUN to a new directory below .local/runs'; exit 2; }
	/usr/bin/env cargo build --locked -p reha-cli --example voice_samples
	/usr/bin/env uv run --locked python ml/evaluation/speech/listening.py --run "$(RUN)"

prepare-listening-experimental:
	@test -n "$(RUN)" || { echo 'Set RUN to a new directory below .local/runs'; exit 2; }
	/usr/bin/env cargo build --locked -p reha-cli --example voice_samples --features voice
	/usr/bin/env uv run --locked python ml/evaluation/speech/listening.py --run "$(RUN)" --include-victoria

refresh-listening:
	@test -n "$(RUN)" || { echo 'Set RUN to an existing listening export'; exit 2; }
	/usr/bin/env uv run --locked python ml/evaluation/speech/listening_form.py --run "$(RUN)"

transcribe-listening:
	@test -n "$(RUN)" -a -n "$(LISTENING)" || { echo 'Set RUN and LISTENING to local evaluation directories'; exit 2; }
	/usr/bin/env uv run --locked python ml/evaluation/speech/transcribe.py --run "$(RUN)" --listening "$(LISTENING)" --locale "$(SPEECH_LOCALE)"

setup-speech-evaluation:
	@test -n "$(RUN)" || { echo 'Set RUN to a new local setup directory'; exit 2; }
	/usr/bin/env uv run --locked python ml/evaluation/speech/transcribe.py --run "$(RUN)" --setup --locale "$(SPEECH_LOCALE)"

restore-rust:
	/usr/bin/env cargo fetch --locked

restore: restore-rust
	/usr/bin/env uv sync --locked
	/usr/bin/env uv run --locked python tooling/build/fetch-models.py --tier small
	/usr/bin/env uv run --locked python tooling/build/fetch-ios-runtime.py

# Deployment OCR is already pinned ONNX; no speech conversion belongs to setup.
convert:
	python3 tooling/build/verify-native-assets.py $(TARGET)

.PHONY: restore-experimental-speech convert-experimental-speech
restore-experimental-speech:
	/usr/bin/env uv sync --locked --script tooling/build/export-victoria.py
	/usr/bin/env uv run --locked --with cmake==3.31.6 cmake --version
	python3 tooling/build/build-phonemizer.py --source-only
	python3 tooling/build/fetch-speech-model.py restore

convert-experimental-speech:
	@case "$(TARGET)" in \
	  simulator) python3 tooling/build/build-phonemizer.py --offline host aarch64-apple-ios-sim ;; \
	  device) python3 tooling/build/build-phonemizer.py --offline host aarch64-apple-ios ;; \
	  all) python3 tooling/build/build-phonemizer.py --offline host aarch64-apple-ios aarch64-apple-ios-sim ;; \
	  *) echo 'TARGET must be simulator, device or all' >&2; exit 2 ;; \
	esac
	python3 tooling/build/fetch-speech-model.py convert

verify-assets:
	python3 tooling/build/verify-native-assets.py $(TARGET)

.PHONY: archive
archive: TARGET = archive
archive: build

package:
	@test -n "$(RELEASE_RUN)" || { echo 'Set RELEASE_RUN below .local/releases'; exit 2; }
	python3 tooling/release/package-native.py --run "$(RELEASE_RUN)" $(if $(RELEASE_ARCHIVE),--archive "$(RELEASE_ARCHIVE)")

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

.PHONY: restore-ocr-assets prepare-ocr-smoke prepare-ocr-data prepare-ocr-synthetic train-ocr resume-ocr export-ocr register-ocr
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

register-ocr:
	@test -n "$(RUN)" -a -n "$(MODEL_CARD)" || { echo 'Set RUN and a new ml/registry MODEL_CARD path'; exit 2; }
	.local/envs/ocr/bin/python ml/training/ocr/model_card.py --run "$(RUN)" $(if $(COMPARE_RUN),--run "$(COMPARE_RUN)") --output "$(MODEL_CARD)"

.PHONY: diagnose-ocr-parity diagnose-ocr-baseline-parity diagnose-ocr-stage-parity
PARITY_OPTIMIZATION ?= disabled
diagnose-ocr-parity:
	@test -n "$(RUN)" -a -n "$(PARITY_REPORT)" || { echo 'Set RUN and a new private PARITY_REPORT path'; exit 2; }
	OMP_NUM_THREADS=2 OPENBLAS_NUM_THREADS=2 MKL_NUM_THREADS=2 .local/envs/ocr/bin/python ml/evaluation/recognition/export_parity.py --run "$(RUN)" --onnx "$(RUN)/deployment/recognizer.onnx" --failures-from "$(RUN)/deployment/parity.json" --graph-optimization "$(PARITY_OPTIMIZATION)" --report "$(PARITY_REPORT)"

diagnose-ocr-baseline-parity:
	@test -n "$(RUN)" -a -n "$(PARITY_REPORT)" || { echo 'Set RUN and a new private PARITY_REPORT path'; exit 2; }
	OMP_NUM_THREADS=2 OPENBLAS_NUM_THREADS=2 MKL_NUM_THREADS=2 .local/envs/ocr/bin/python ml/evaluation/recognition/export_parity.py --run "$(RUN)" --baseline --report "$(PARITY_REPORT)"

diagnose-ocr-stage-parity:
	@test -n "$(RUN)" -a -n "$(PARITY_REPORT)" || { echo 'Set RUN and a new private PARITY_REPORT path'; exit 2; }
	OMP_NUM_THREADS=2 OPENBLAS_NUM_THREADS=2 MKL_NUM_THREADS=2 .local/envs/ocr/bin/python ml/evaluation/recognition/stage_parity.py --run "$(RUN)" --report "$(PARITY_REPORT)" $(if $(UNFUSED_EXPORT),--unfused-export "$(UNFUSED_EXPORT)")

ASSISTANT_PER_FAMILY ?= 16
.PHONY: diagnose-assistant-parity
diagnose-assistant-parity:
	@test -n "$(RUN)" -a -n "$(DIAGNOSTIC_RUN)" || { echo 'Set RUN and a new private DIAGNOSTIC_RUN directory'; exit 2; }
	.local/envs/assistant/bin/python ml/evaluation/conversation/runtime_parity.py --run "$(RUN)" --output "$(DIAGNOSTIC_RUN)"

# Prompt/token diagnosis preserves all historical generation/parity evidence.
.PHONY: diagnose-assistant-token-parity
diagnose-assistant-token-parity: PEAK_GIB = 8
diagnose-assistant-token-parity: check-storage
	@test -n "$(RUN)" -a -n "$(DIAGNOSTIC_RUN)" -a -n "$(WEIGHTS_EVIDENCE)" || { echo 'Set RUN, a new DIAGNOSTIC_RUN and the existing WEIGHTS_EVIDENCE JSON'; exit 2; }
	.local/envs/assistant/bin/python ml/evaluation/conversation/token_parity.py --run "$(RUN)" --output "$(DIAGNOSTIC_RUN)" --weights-evidence "$(WEIGHTS_EVIDENCE)" $(if $(REUSE_MLX),--reuse-mlx "$(REUSE_MLX)")

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

OCR_TRACE_BATCH ?= 32
.PHONY: diagnose-ocr-operation-parity
diagnose-ocr-operation-parity: PEAK_GIB = 8
diagnose-ocr-operation-parity: check-storage
	@test -n "$(RUN)" -a -n "$(DIAGNOSTIC_RUN)" || { echo 'Set RUN and a new DIAGNOSTIC_RUN below .local/runs'; exit 2; }
	.local/envs/ocr/bin/python ml/evaluation/recognition/operation_parity.py --run "$(RUN)" --output "$(DIAGNOSTIC_RUN)" --batch-size "$(OCR_TRACE_BATCH)" $(if $(ALL_FAILURES),--all-failures)

.PHONY: prepare-ocr-convolution-lowering diagnose-ocr-convolution-lowering
prepare-ocr-convolution-lowering:
	@test -n "$(DIAGNOSTIC_RUN)" || { echo 'Set DIAGNOSTIC_RUN to a new private experiment directory'; exit 2; }
	.local/envs/ocr/bin/python ml/evaluation/recognition/convolution_lowering.py prepare --output "$(DIAGNOSTIC_RUN)"

diagnose-ocr-convolution-lowering: PEAK_GIB = 1
diagnose-ocr-convolution-lowering: check-storage
	@test -n "$(DIAGNOSTIC_RUN)" || { echo 'Set DIAGNOSTIC_RUN to the prepared private experiment directory'; exit 2; }
	.local/envs/ocr/bin/python ml/evaluation/recognition/convolution_lowering.py execute --output "$(DIAGNOSTIC_RUN)"

.PHONY: prepare-ocr-convolution-stage diagnose-ocr-convolution-stage
prepare-ocr-convolution-stage:
	@test -n "$(DIAGNOSTIC_RUN)" || { echo 'Set DIAGNOSTIC_RUN to a new private experiment directory'; exit 2; }
	.local/envs/ocr/bin/python ml/evaluation/recognition/convolution_stage.py prepare --output "$(DIAGNOSTIC_RUN)"

diagnose-ocr-convolution-stage: PEAK_GIB = 2
diagnose-ocr-convolution-stage: check-storage
	@test -n "$(DIAGNOSTIC_RUN)" || { echo 'Set DIAGNOSTIC_RUN to the prepared private experiment directory'; exit 2; }
	.local/envs/ocr/bin/python ml/evaluation/recognition/convolution_stage.py execute --output "$(DIAGNOSTIC_RUN)"
