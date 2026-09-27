# Conversation cancellation follow-up

The user confirmed Victoria is correct but still reported cancellations and basic
question failures on build 2026092702. The content-free trace shows successive
SpeechAnalyzer finalizations and several interrupted replies. It does not identify
which interruptions were real speech, echo, navigation or system events. No new
ASR failure is recorded in the captured turns; this does not rule out other turns.

Build **0.3.0 (2026092703)**, source `9dd7000`, adds:

- A foreground idle-timer override during listening, thinking and playback,
  restored when that activity ends or the app leaves the foreground. Previously
  Auto-Lock could trigger the app's explicit background cancellation. The exact
  cause of the user's observed cancellations is not yet established.
- Typed cancellation/interruption codes and interpretation result/error codes.
  Routine diagnostics still exclude arbitrary error text and conversation content.
- An opt-in personal-build assistant probe with synthetic input, comparing plain
  generation, a small guided schema and the app's actual interpretation provider.
  It bypasses calendar/database opening and microphone capture.

Conversation/wake-policy, voice-flow and interpretation-provider checks pass,
including cancellation, provider deadlines and late-result isolation. Lint and the
private simulator build pass. The final signed Release archive also compiles the
probe's scoped idle-timer override. The host advertises Apple Intelligence disabled,
so no host generation result establishes phone behavior. Token counting alone
reports 804 tokens for the full schema and 485 for the read schema against a
4,096-token capacity; schema size alone does not explain the failures.

The archive was built from clean source outside synchronized storage. Private
package verification passed model/native/notices checks, all four signatures and
profiles, App Groups and matching executable/dSYM identities. IPA SHA-256:
`aa5fb6684b205a55afc1b1d2fa6ad84ad7e8b54e4b4a16dc444ac7cd1418c971`.
The existing phone app was updated in place, preserving Victoria. Version 2703
was verified; nothing was uninstalled.

A fresh consistent backup reuses only previously verified file transfers whose
metadata still matches the device, rehashes the copied bytes, recopies changed
files, and checks all container inventories again. Install preflight rechecks
both the entire backup and fresh phone inventories. The strict post-install
comparison passes without review: all 17 tables, schema 11, 31 scans, 30 originals,
preferences and other durable files are unchanged.

After the user unlocked the phone, the synthetic probe completed. Plain and small
guided greetings succeeded in 1.87 and 0.49 seconds. The app's greeting succeeded,
but “Wie geht es dir?” and “Was kannst du?” failed with
`CalendarUnderstandingError.invalidRequest` after generation. The first-appointment
question returned clarification. This establishes an app interpretation failure;
it does not establish which optional output field caused rejection because the
initial probe did not retain raw synthetic generations. The model itself can
generate German answers on this phone.

The subsequent normal launch was rejected because the phone had locked again.
Fresh routine diagnostics include a background cancellation (code 4), but no new
active microphone session qualifying the foreground idle-timer fix. The assistant
schema follow-up retains raw fixed synthetic output separately from routine logs.
Physical microphone conversation and Auto-Lock behavior remain unqualified. A
concrete failed utterance was also requested from the user and remains unanswered.

Private evidence: `.local/runs/victoria-cancellation-20260927-001/` and
`.local/runs/assistant-runtime-device-20260927-001/`; package:
`.local/releases/assistant-runtime-20260927-001/`.
