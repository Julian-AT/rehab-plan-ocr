> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# iPhone update — September 26, 2026

The user explicitly requested installing the current app on their connected iPhone.
The existing development signing team and bundle identifier
`at.rehakalender.personal` were reused for an in-place update of **Termine 0.2.0**.
The package contains the new clinic emblem, HEIC/HEIF import, extraction version 7,
source review improvements and optimized recognition pipeline. The frontend, small
OCR model and iOS runtime are bundled, so this is a standalone installation.

## Package verification

- Signed release build and IPA export completed successfully with Tauri and Xcode.
- Package: `artifacts/private/builds/rehab-plan-ocr-lab-0.2.0-20260926-s11.ipa`.
- SHA256: `3dbb2b6e0e8d4154728e9779d465c6394dad6a02a0a192bf2767199351b1267b`.
- Size: 38,627,286 bytes. The unversioned private IPA alias contains this package.
- `codesign --verify --deep --strict` passed on the extracted package outside the
  file-provider-managed workspace. That workspace adds Finder metadata to `.app`
  directories, which interferes with strict signature checks after extraction.
- The signing profile includes the connected iPhone and expires September 26, 2026,
  2026, at 10:57:56 UTC. The existing signing team and app identifier are unchanged.
- The new icon catalog is included and the display name remains **Termine**.

## Device verification

Installation succeeded on the wired iPhone 17 / iOS 26.6. Developer Mode was already
enabled. No app was uninstalled and no calendar write was performed.

Before installation, the app's support directory was copied into ignored local
private storage. The post-install SQLite integrity check returned `ok`; all rows in
the scans (7), imports (32), operations (32), schedules (4), settings (2) and failures
(2) tables were retained byte-for-byte at the serialized row level. The backup also
contains the six originals that were present before the update.

The initial launch request was blocked by the device lock. Unlocking was requested
to complete the startup check; installation itself succeeded.

Detailed build, signature, installation, data-retention and launch evidence is under
`artifacts/private/iphone-install-20260926-s11/`. These checks do not establish physical
OCR accuracy, camera acceptance or repeated-scan performance.
