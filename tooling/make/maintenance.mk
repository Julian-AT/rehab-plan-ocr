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

ARCHIVE_OBJECT_MANIFEST ?= .local/maintenance/archive-objects.json
.PHONY: inventory-archive-objects coalesce-archive-objects
inventory-archive-objects:
	@test -n "$(ARCHIVE_REVIEW)" || { echo 'Set ARCHIVE_REVIEW to a reviewed private static-archive inventory'; exit 2; }
	python3 tooling/dev/archive_objects.py plan --review "$(ARCHIVE_REVIEW)" --manifest "$(ARCHIVE_OBJECT_MANIFEST)"

coalesce-archive-objects:
	python3 tooling/dev/archive_objects.py apply --manifest "$(ARCHIVE_OBJECT_MANIFEST)"

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

.PHONY: artifact-reader-setup inventory-artifacts clean-artifacts check-storage
artifact-reader-setup:
	python3 tooling/dev/llvm_references.py setup $(if $(LLVM_READER_ARCHIVE),--archive "$(LLVM_READER_ARCHIVE)")

inventory-artifacts:
	python3 tooling/dev/artifacts.py plan --manifest "$(CLEANUP_MANIFEST)"

clean-artifacts:
	python3 tooling/dev/artifacts.py apply --manifest "$(CLEANUP_MANIFEST)"

check-storage:
	python3 tooling/dev/artifacts.py space --peak-gib "$(PEAK_GIB)"

.PHONY: ci-status test-ci-monitor
ci-status:
	node tooling/dev/ci_monitor.cjs runs

test-ci-monitor:
	node --test tooling/dev/tests/ci_monitor.test.cjs

MIGRATION ?= .local/migrations/private-storage.json
.PHONY: inventory-private migrate-private
inventory-private:
	python3 tooling/dev/migrate-private.py plan --manifest "$(MIGRATION)"

migrate-private:
	python3 tooling/dev/migrate-private.py apply --manifest "$(MIGRATION)"
