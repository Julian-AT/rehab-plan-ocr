# Privacy information — publication draft

The app processes plan images/documents, recognized appointments, corrections,
calendar access and voice requests locally. Initial model/tool restoration and
Apple speech-asset preparation can use the network. Local inference does not imply
that operating-system calendar account synchronization is disabled.

Calendar changes require visible confirmation and the relevant system permission.
Reminders need notification permission. Microphone and speech access are requested
for voice interaction. The app's local calendar refresh does not initiate account
synchronization. App Group snapshots expose only the bounded agenda information
needed by the widget and notification extension.

Sources, drafts and settings live in protected local storage. Retention and erasure
are explicit; erasure coordinates producers before deleting their output. Exports
may contain sensitive user-selected data and should be shared deliberately.
Diagnostics are local, bounded and normally omit appointment content and transcripts;
diagnostic exports are sanitized. Device backups remain separate from app erasure.

This draft requires publisher/contact details and review before public publication.
Research consent and data export approval are separate from app permissions; see
[research collection](research/collection-guide.md). No private recordings,
documents, weights or backups are included in the source submission.
