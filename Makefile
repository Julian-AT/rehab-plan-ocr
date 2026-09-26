.PHONY: bootstrap doctor format lint test test-ios build verify bindings check-bindings test-agenda restore
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
