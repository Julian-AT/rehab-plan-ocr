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

.PHONY: restore-vlm-runtime restore-vlm-models build-vlm
restore-vlm-runtime:
	python3 ml/experiments/vlm/build.py restore

restore-vlm-models:
	/usr/bin/env uv run --locked python ml/experiments/vlm/fetch-vlm.py

build-vlm: PEAK_GIB = 4
build-vlm: check-storage
	@test -n "$(RUN)" || { echo 'Set RUN to a new directory below .local/runs'; exit 2; }
	python3 ml/experiments/vlm/build.py build --run "$(RUN)"


# Reserve is additional to the expected temporary build/export/checkpoint peak.
# Direct low-level scripts retain their historical recovery contracts; supported
# heavy workflows enter here before generating any new artifacts.
build build-assistant-native build-assistant-runtime build-assistant-trial: PEAK_GIB = 4
# Disposable simulator creation plus test products exceeded the app-only build
# budget locally. Keep 16 GiB headroom in addition to the 20 GiB working reserve.
SIMULATOR_CHECKS := test-ios test-native-ui test-calendar-events test-visual-baseline test-reduced-motion test-audio-runtime
$(SIMULATOR_CHECKS): PEAK_GIB = 16
$(SIMULATOR_CHECKS): check-storage
train-ocr resume-ocr: PEAK_GIB = 4
train-assistant resume-assistant: PEAK_GIB = 3
export-ocr export-assistant assistant-smoke: PEAK_GIB = 8
build test-ios build-assistant-native build-assistant-runtime build-assistant-trial \
train-ocr resume-ocr train-assistant resume-assistant export-ocr export-assistant assistant-smoke: check-storage

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

# Integrated development-002 voice UI trial: 24 GiB peak + 20 GiB reserve.
# Keep this fixed budget even if a caller supplies a lower generic PEAK_GIB.
.PHONY: build-assistant-voice-trial test-assistant-voice-trial
build-assistant-voice-trial test-assistant-voice-trial: override PEAK_GIB = 24
build-assistant-voice-trial test-assistant-voice-trial: check-storage

build-assistant-voice-trial:
	@test -z "$(strip $(ASSISTANT_TRIAL_MODEL))" -o "$(ASSISTANT_TRIAL_MODEL)" = tuned-v2 || { echo 'The integrated voice trial supports only tuned-v2'; exit 2; }
	python3 tooling/build/build-assistant-trial.py --model tuned-v2 --voice-ui-tests

test-assistant-voice-trial:
	@test -n "$(strip $(RUN))" -a -n "$(strip $(SIMULATOR))" -a -n "$(strip $(SOURCE_COMMIT))" || { echo 'Set a new RUN below .local/runs, an owned fresh SIMULATOR UUID and the exact clean SOURCE_COMMIT'; exit 2; }
	@test -z "$(strip $(ASSISTANT_TRIAL_MODEL))" -o "$(ASSISTANT_TRIAL_MODEL)" = tuned-v2 || { echo 'The integrated voice trial supports only tuned-v2'; exit 2; }
	python3 ml/evaluation/conversation/voice_trial.py --run "$(RUN)" --simulator "$(SIMULATOR)" --source-commit "$(SOURCE_COMMIT)"

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

.PHONY: intake
intake:
	@test -n "$(REQUEST)" -a -n "$(BATCH)" || { echo 'Set REQUEST and a new BATCH below .local/datasets/incoming'; exit 2; }
	/usr/bin/env uv run --locked python ml/data/annotation/intake.py "$(REQUEST)" "$(BATCH)"

OCR_MODE ?= frozen-backbone
OCR_EPOCHS ?= 100
OCR_PATIENCE ?= 5
.PHONY: recognition-fixture
recognition-fixture: PEAK_GIB = 4
recognition-fixture: check-workspace check-storage
	@test -n "$(CROP)" -a -n "$(FIXTURE_OUTPUT)" || { echo 'Set CROP to a rectified PNG and FIXTURE_OUTPUT to a new directory below .local'; exit 2; }
	/usr/bin/env cargo run --offline --locked -p reha-cli -- recognition-fixture "$(CROP)" "$(FIXTURE_OUTPUT)"

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
ASSISTANT_EPOCHS ?= 20
ASSISTANT_PATIENCE ?= 3
ASSISTANT_LAYERS ?= 8
.PHONY: prepare-assistant-data train-assistant resume-assistant export-assistant
prepare-assistant-data:
	@test -n "$(DATASET)" || { echo 'Set DATASET to a new directory below .local'; exit 2; }
	python3 ml/training/assistant/prepare.py --output "$(DATASET)" --per-family "$(ASSISTANT_PER_FAMILY)"

.PHONY: prepare-assistant-development-data
prepare-assistant-development-data:
	@test -n "$(DATASET)" -a -n "$(SOURCE_DATASET)" || { echo 'Set DATASET (new) and SOURCE_DATASET (existing dataset.json)'; exit 2; }
	python3 ml/training/assistant/development_data.py --source "$(SOURCE_DATASET)" --output "$(DATASET)"

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

.PHONY: prepare-assistant-router-replay assess-assistant-router-replay
prepare-assistant-router-replay:
	@test -n "$(RUN)" -a -n "$(APP_RUN)" -a -n "$(DEPLOYMENT_RUN)" -a -n "$(NATIVE_RUN)" || { echo 'Set RUN (new), APP_RUN, DEPLOYMENT_RUN and NATIVE_RUN'; exit 2; }
	python3 ml/evaluation/conversation/router_replay.py prepare --output "$(RUN)" --app "$(APP_RUN)" --deployment "$(DEPLOYMENT_RUN)" --native "$(NATIVE_RUN)"

assess-assistant-router-replay:
	@test -n "$(RUN)" || { echo 'Set RUN to the prepared and executed router replay'; exit 2; }
	python3 ml/evaluation/conversation/router_replay.py summarize --output "$(RUN)"
