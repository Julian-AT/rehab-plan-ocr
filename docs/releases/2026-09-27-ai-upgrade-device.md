# AI upgrade: physical iPhone update

The user explicitly authorized installation on the connected phone after the
simulator preview and listening samples were prepared. The existing installation
was updated in place to **0.3.0 (2026092701)**; nothing was uninstalled.

## Package and installation

- Source: `2006c25` with a clean checkout. App and extension identities, signing
  team and App Groups are unchanged.
- Xcode's signed arm64 Release archive succeeded. The package verifier passed
  bundle/resources/privacy/runtime provenance, all four signatures and provisioning
  profiles, signer identity and executable/dSYM matching. Every profile authorizes
  the connected phone. The extracted installation app passed strict deep signature
  verification and matched the verified archive binaries.
- IPA SHA-256: `3d919f2cf3f9bf8ac4fd241eed9c1dae17fd9b5a548787d922579da3009254d6`.
- `devicectl` confirmed build `2026092701` after the in-place installation.

The workspace's File Provider reapplied Finder metadata between the cleanup build
phase and CodeSign. Failed attempts remain preserved. The successful archive used
an independent DerivedData/archive directory under `Library/Developer/RehaCalendar`,
outside the synchronized source folder, while retaining the shared native-input
lease. Signing validation was not disabled. The build-phase cleanup alone is not
a reliable workaround for this File Provider behavior.

## Data evidence

The fresh pre-install backup covers App/Documents, Library/Application Support,
Library/Preferences and both App Group containers. OS-managed launch snapshots,
caches and temporary files are outside this durable-data capture. Its 154 files
total 1,134,533,628 bytes, including 31 scans. The schema-8 database passed integrity
and foreign-key checks. Both App Groups contained directories but no files.

The capture verified source file paths, sizes and modification times before and
after transfer. The install preflight rechecked the device inventory and rehashed
the entire backup against its immutable snapshot. An earlier capture remains
preserved separately because reminder/diagnostic state changed before installation.

The first post-install copy changed while the app was running and was rejected.
A second copy after stopping the app passed transfer consistency checks and covers
the first-launch migration. There is no stable separate pre-launch comparison.
The original strict comparison is retained with `review_required: true`; the
following differences were reviewed explicitly rather than suppressed:

- Schema 8 → 11 adds the disposable scan summary and indexes, `source_deletions`
  (empty), and `batch_documents` (verified against existing import batches).
  All original columns and rows in all 15 original tables match the backup.
- All 31 scans, 30 retained source files, existing preferences and other durable
  files are preserved. No preference keys changed or appeared.
- Reminder state only gained `displayCalendarIDs`, matching the unchanged stored
  selection. All 116 existing records, 101 journal entries and reminder preferences
  are unchanged.
- Diagnostics gained 92 events and evicted the 92 oldest entries under the existing
  5,000-event cap. The 4,908 retained original entries are unchanged. This includes
  two failed recognition finalizations; one short transcript finalized successfully.
  These unannotated turns used the legacy provider and do not establish speech
  accuracy or end-to-end conversation reliability.

`persistence-review.json` records the reviewed preservation result separately from
the unchanged strict comparison and failed capture evidence.

App startup and the completed migration were observed on the phone. The app was
then stopped for the consistent copy. iOS rejected automatic reopening because
the device had locked. After the user unlocked it, the app reopened successfully
and its process remained running. The app is left open for the user.

Private evidence: `.local/runs/ai-upgrade-device-20260927-005/`; verified package:
`.local/releases/ai-upgrade-20260927-005/`. No originals, backups, private device
identifiers or recording content are committed.

## Qualification boundary

Installation and startup do not qualify natural microphone-to-answer conversation.
The 100 physical speech cycles, held-out Austrian German task accuracy, latency,
interruption, offline/reboot and sustained thermal/memory scenarios remain pending.
The [implementation record](../development/on-device-ai-upgrade.md) retains the
strict visual comparison discrepancies and host-only listening/evaluation limits.
No challenger speech, assistant, OCR or TTS model is promoted by this installation.
