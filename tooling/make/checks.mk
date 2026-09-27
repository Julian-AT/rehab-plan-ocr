.PHONY: test-product-generation
test-product-generation:
	python3 tooling/build/tests/test-product-generation.py

test-ios:
	python3 tooling/dev/quality.py test-ios

.PHONY: verify-ui-result
verify-ui-result:
	@test -n "$(RESULT_BUNDLE)" -a -n "$(RUN)" || { echo 'Set RESULT_BUNDLE and a new RUN verification directory'; exit 2; }
	python3 tooling/checks/ui-test-result.py --bundle "$(RESULT_BUNDLE)" --output "$(RUN)" $(foreach test,$(UI_TESTS),--only-test "$(test)")

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

# Python retrieval and replay use the existing tools interpreter without env sync.
.PHONY: download-python-advisories audit-python-dependencies test-python-dependency-audit
download-python-advisories:
	@test -n "$(strip $(PYTHON_AUDIT_SNAPSHOT))" || { echo 'Set PYTHON_AUDIT_SNAPSHOT to a new directory below .local/audits (explicit online download)'; exit 2; }
	"$(UV_PROJECT_ENVIRONMENT)/bin/python" tooling/release/audit_python.py download --output "$(PYTHON_AUDIT_SNAPSHOT)"

audit-python-dependencies:
	@test -n "$(strip $(PYTHON_AUDIT_SNAPSHOT))" -a -n "$(strip $(PYTHON_AUDIT_SHA256))" -a -n "$(strip $(PYTHON_AUDIT_RUN))" || { echo 'Set PYTHON_AUDIT_SNAPSHOT, its exact PYTHON_AUDIT_SHA256 and a new PYTHON_AUDIT_RUN below .local/audits'; exit 2; }
	"$(UV_PROJECT_ENVIRONMENT)/bin/python" tooling/release/audit_python.py offline --snapshot "$(PYTHON_AUDIT_SNAPSHOT)" --snapshot-sha256 "$(PYTHON_AUDIT_SHA256)" --output "$(PYTHON_AUDIT_RUN)"

test-python-dependency-audit:
	"$(UV_PROJECT_ENVIRONMENT)/bin/python" tooling/release/tests/test-audit-python.py

test-agenda:
	sh tooling/checks/test-agenda.sh

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
