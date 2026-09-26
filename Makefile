.PHONY: bootstrap doctor format lint test test-ios build verify
bootstrap doctor format lint test:
	python3 scripts/quality.py $@

test-ios:
	python3 scripts/quality.py test-ios

build:
	python3 scripts/quality.py build simulator

verify: lint test build
