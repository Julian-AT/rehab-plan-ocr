> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Native iPhone update procedure

The product is the SwiftUI iOS 26+ app under `apps/ios`. The old Tauri build and
installation commands are obsolete. Current setup/build commands are in the
[repository guide](../../README.md) and [native build guide](../../apps/ios/README.md).

The last documented physical installation is build **2026092624**; see the
[retained-data update record](history/zitrus-device-update.md). The device was unavailable
for a fresh installed-build check during the current implementation. Development
simulator builds do not update the phone.

1. Finish relevant tests and prepare current simulator screenshots and listening
   samples. Record build/source/model identities and remaining limitations.
2. Obtain the user's explicit approval of those previews and samples, as required
   by [AGENTS.md](../../AGENTS.md). A historical approval covers its historical update.
3. Take a fresh local backup of the app container and App Group. Keep the existing
   signed package. Record database integrity/schema, serialized table hashes,
   original-source hashes, preferences, event ownership and pending journals.
4. Build/package the native app with the existing identifiers and signing team.
   Verify signatures, entitlements, provisioning expiry, model/dependency inventory
   and packaging checks against the actual candidate. Do not reuse old expiry claims.
5. Update the existing installation without uninstalling. Compare persistent data
   before and after first launch, accounting explicitly for the tested migration.
6. Run the approved physical acceptance scenarios, including permissions, airplane
   mode, backgrounding, interruptions and recovery. Record results and failures.

Preserve `at.rehakalender.personal`, its extension identifiers,
`group.at.rehakalender.personal`, and
`Library/Application Support/at.rehakalender.personal`. Restore an older binary
only with its matching verified data backup; it cannot read a newer schema safely.

## Comparing local copies

After copying a stopped app and both App Groups, retain this layout in each
backup/after directory: `App/Documents`, `App/Library/Application Support`,
`App/Library/Preferences`, `AgendaGroup`, and `IntakeGroup`. The comparison tool
does not capture a device, establish transfer completeness, stop an app or install
anything. A successful old-copy comparison cannot authorize a new update.

```sh
make snapshot-persistence SNAPSHOT_ROOT=.local/runs/<delivery>/backup \
  OUTPUT=.local/runs/<delivery>/before.json
make compare-persistence BEFORE=.local/runs/<delivery>/backup \
  SNAPSHOT=.local/runs/<delivery>/before.json \
  AFTER=.local/runs/<delivery>/after-install \
  OUTPUT=.local/runs/<delivery>/after-install-comparison.json
```

The tool supports native schemas 8–11. It hashes every supplied file and hashes
typed database rows without storing their values. SQLite, WAL and SHM inspection
runs only on temporary copies. Integrity/foreign-key failures, missing containers,
unknown schemas, symlinks and changes during reading fail. Comparison first
reverifies the complete original backup against its immutable snapshot.

All original table columns are compared together per row, preserving event/value
associations even when a later schema adds disposable summaries. Schema changes,
new tables/files or added preferences remain explicit review items; preservation
of projected old columns alone does not approve a migration. Existing preferences,
approved values, ownership, pending journals and sources must remain intact.
Equivalent JSON/plist serialization is distinguished from changed content.
Changed diagnostics are reported for review rather than silently excluded.

Evidence files stay under ignored `.local` with mode 0600 and cannot overwrite
an earlier report or be written inside a source container. A review-required
comparison exits nonzero and retains its report. Do not edit a failed snapshot to
make it pass; retain the evidence and explain each expected migration/maintenance
change alongside the migration tests and actual post-launch comparison.

The current [implementation ledger](../development/implementation-plan.md) defines the complete
release gates. No current device update, TestFlight upload or public submission
has been performed by the implementation work recorded there.
