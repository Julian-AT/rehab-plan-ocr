# Native architecture

The SwiftUI app and extensions live in `apps/ios`. `reha-core` owns image
preparation, parsing, validation, source lineage, calendar proposals, undo, ICS
and SQLite storage. `reha-ffi` exposes typed UniFFI records and callbacks.
`AppleServices` owns EventKit, notifications, protected files and local diagnostics.
See [source ownership](ios-layout.md) and [build setup](../../apps/ios/README.md).

## Interaction and effects

The UI creates proposals. The core checks revisions and journals intent before
native calendar writes. Unknown outcomes block further writes until an explicitly
confirmed recovery flow. Refresh is read-only. Foreign notes, alarms, recurring
series and invitations remain protected; see [calendar protection](calendar-protection.md).
EventKit refresh reads local data without requesting account synchronization.

UI and permission dialogs run on the main actor. EventKit effects use serialized
queues. Blocking Rust work runs outside the UI. Recognition has cooperative
cancellation between stages/crops and ONNX run options; this is not a hard deadline
for system codecs. Generation tickets discard obsolete camera, document and voice
callbacks. Erasure stops intake, waits for producers, then removes content. The
share extension also uses a persistent file lock to prevent resurrection of data.

## Persistence

SQLite schema 11 retains migrations: shared event links (8), resumable source
erasure (9), and indexed/paginated archives (10/11). JSON document schema 3 is a
separate boundary. Import evidence and settings remain compatible. Deletion keeps
lineage and undo associations. Event links distinguish missing association, missing
access and deleted events.

App reminders replace calendar alarms only after confirmed system scheduling.
Uncertain completion retains the calendar fallback. Scheduling allows 60 normal
requests, one test and three snoozes. Planned, pending and delivered are distinct
states; background refresh is an additional opportunity, not a delivery guarantee.

## Recognition and conversation

Photo, file, PDF and share intake use bounded source handling. OCR combines the
pinned local runtime with selective native text recognition. Users review extracted
fields before import. [Input fixtures](recognition-input.md) remain synthetic.

Conversation uses typed interpretation and the same proposal/confirmation boundary.
The [provider guide](ai-providers.md) distinguishes rules, Apple services and the
optional local assistant. The default output is system speech; the personal
Victoria overlay preserves its original stored voice preference. Cancellation,
foreground ownership and ordered playback prevent stale work from speaking.
See [assistant safety](../development/assistant-safety.md),
[concurrency](../development/concurrency-ownership.md) and
[typed boundaries](../development/typed-boundaries.md).
