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

include tooling/make/build.mk
include tooling/make/checks.mk
include tooling/make/research.mk
include tooling/make/maintenance.mk

.PHONY: help
help:
	@echo 'Setup: make bootstrap doctor restore; make convert TARGET=all'
	@echo 'Build: make build [TARGET=simulator|device]; make check-bindings'
	@echo 'Checks: make lint test test-tools test-ios inventory-repository'
	@echo 'Source: make source-zip; make verify-source SOURCE_ZIP=<archive>'
	@echo 'Research and maintenance: see ml/README.md and docs/development/README.md'

bootstrap doctor format lint test:
	python3 tooling/dev/quality.py $@

test-tools:
	python3 tooling/dev/quality.py test-tools

build:
	python3 tooling/dev/quality.py build $(TARGET)

verify: lint test build

.PHONY: source-zip verify-source
source-zip:
	python3 tooling/dev/source_zip.py create

verify-source:
	@test -n "$(SOURCE_ZIP)" || { echo 'Set SOURCE_ZIP to the source archive'; exit 2; }
	python3 tooling/dev/source_zip.py verify "$(SOURCE_ZIP)"
