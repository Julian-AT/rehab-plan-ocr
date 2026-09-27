bindings check-bindings:
	sh tooling/build/build-native.sh $@

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
