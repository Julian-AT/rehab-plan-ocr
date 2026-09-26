> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# iOS source ownership

`apps/ios/project.yml` remains the authoritative Xcode project specification.
The target names, bundle identifiers, App Groups and deployment target remain
unchanged. Generate the ignored Xcode project through `make build`.

| Directory | Responsibility |
| --- | --- |
| `App` | App lifecycle, native bridge, bundle resources and metadata |
| `Features/Agenda` | Visible calendars, calendar presentation and event editing |
| `Features/Capture` | Capture UI and intake admission |
| `Features/PlanReview` | Recognition review, source evidence and import confirmation |
| `Features/Archive` | Stored plans, import history and activity |
| `Features/Conversation` | Conversation state, interpretation, audio and spoken responses |
| `Features/Settings` | Preferences, diagnostics and voice settings |
| `Shared/DesignSystem` | Existing visual tokens and reusable visual components |
| `Shared/Intake` | Receipt and admission types shared with the share extension |
| `Extensions` | Share, widget and notification targets with their own metadata |
| `Tests/Support` | Explicit simulator-only fixtures compiled into debug builds |
| `Tests/UI` | Simulator UI tests |
| `Tests` | Standalone probes for app logic |

Native service implementations remain under `packages/apple`. Domain behavior
stays with its feature; a utility moves to `Shared` only when multiple consumers
actually need it. Training code is never an application dependency.

The initial mechanical move preserved the SHA-256 of all 93 moved files,
including plists, entitlements, strings and artwork. Verification: simulator
build, eleven app-logic probe targets, and three simulator UI tests covering
dark calendar presentation, archive/settings/cold launch and voice cancellation.
This is source-preservation evidence, not a complete pixel-baseline comparison.
