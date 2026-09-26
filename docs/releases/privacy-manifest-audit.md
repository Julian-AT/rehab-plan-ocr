> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Privacy manifest audit — 2026-09-26

The app and its three extensions each bundle `PrivacyInfo.xcprivacy`. The source
audit found app-private preferences, container/selected-file metadata and elapsed
speech timing. The declarations use Apple's current reasons for those purposes:
CA92.1, C617.1/3B52.1 and 35F9.1 respectively. The Share extension declares selected
file/container metadata. Widgets and notification content have no direct required
reason APIs in their current source and carry empty accessed-API arrays.
[Apple's API categories and reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype),
[manifest structure](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest).

| Evidence | Declared use |
|---|---|
| `dedicated-calendar.swift`, `ConversationReply.swift`, `NeuralSpeech.swift`, SwiftUI app preferences | App-private UserDefaults; no cross-app preferences |
| Rust filesystem/SQLite and native intake | Metadata for owned containers and explicitly selected files |
| `LocalSpeech.swift` | System uptime differences for speech buffering, timers and interruption detection |
| `Shared/Intake/IntakeReceipt.swift` in Share | Validate selected-file type/size and stage a receipt in the app group |

The simulator app's linked executable was checked for `stat`, `fstat`, `fstatat`
and `lstat` imports. No app-level disk-space or active-keyboard query was found;
developer build disk checks are not shipping APIs. App Group snapshots use files,
not shared UserDefaults, so the cross-app UserDefaults reason is not declared.

The manifests declare no tracking, tracking domains or automatic developer data
collection. This reflects the current local implementation, not permission to
add telemetry. Explicit exports through the system share sheet, user calendar
account synchronization and system services are described separately in the
[privacy draft](../product/privacy.md).

Packaging now requires all four declarations to match source and rejects missing,
altered, duplicated or unexpected components. The standalone checker is:

```sh
make verify-privacy APP_BUNDLE=path/to/Laßnitzhöhe.app
```

Verification: the current simulator app and all three extensions build successfully;
their four bundled manifests match the reviewed source declarations. Four packaging
regressions pass, including missing/altered declarations and unexpected extensions.
No signed device archive or public upload was produced by this check.

This audit does not establish App Store acceptance, third-party distribution
clearance, completed publisher/contact details or final privacy-label review.
Repeat the source/binary audit whenever dependencies or data flows change.
