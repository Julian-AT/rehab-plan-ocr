> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Calendar mutation protection

All calendar mutations require the existing visible confirmation. Native checks
run again immediately before EventKit writes; a preview alone never grants a
later write against changed data.

| Route | Protection at the final write |
|---|---|
| Import, revision, replacement, import undo | Exact owner/calendar marker and approved values; shared import policy rejects invitations, birthdays, recurrence/detached occurrences, all-day entries, location geometry and unsupported availability; alarm ownership rejects changed or additional alarm metadata |
| Manual and voice update/delete | Exact current occurrence and full snapshot/fingerprint; invitations/birthdays go to the system editor; only the explicit patch changes, and recurrence uses `.thisEvent` |
| Manual and voice undo | Durable original receipt plus unchanged saved snapshot; later external changes block undo; deletion restoration recovers notes, URL, all-day/availability, structured location and alarms from the original receipt |
| Reminder maintenance | Shared invitation/birthday and alarm policy; recurrence, unavailable/nonwritable calendars and foreign alarm changes retain calendar alarms |

Compact import approvals cannot represent additional location geometry, all-day
semantics or free/tentative/unavailable status. Such events are therefore protected
even if their title/time/location text still matches. EventKit represents plain
room text as an `EKStructuredLocation` too; that alone does not block imports.
Proximity alarms remain external even when their offset resembles the app reminder.

Native evidence includes actual EventKit occurrence edits/undo, additional alarms,
external notes and URLs, managed-alarm handoff, durable saves during alarm-journal
failure, and import update/removal with all-day or location-geometry changes. The
metadata regression first reproduced an incorrectly accepted update. The corrected
suite passes 17 tests with one expected simulator file-protection skip. The pure
alarm/agenda probe passes 57 checks, including proximity protection.

Local simulator calendars do not expose availability choices, so those values are
covered through the same account-independent policy used by the native adapter.
Invitation handoff/confirmation and stale undo also have Rust service regressions.
Physical account synchronization, actual invitations and interruption/persistence
acceptance remain part of release qualification.
