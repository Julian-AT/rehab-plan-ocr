# Concurrency ownership

SwiftUI state and system dialogs belong to the main actor. Apple platform effects
use their service-owned serialized queues. Rust blocking work uses the application's
worker runtime, and recognition jobs own cancellation flags until work drains.
Generation/revision tickets prevent late results from mutating newer state.

`VoiceModel.swift` owns the conversation state machine. Stopping, superseding,
backgrounding or leaving a conversation invalidates pending work. Foreground
listening/thinking/speaking temporarily holds the idle timer; leaving these states
restores the previous setting. The recognition endpoint distinguishes silence,
recognized completion, duplicates and cancellation. Output rendering and PCM
preparation run off the UI actor; ordered playback owns interruption and progress.

Full erasure stops new intake, cancels and drains active producers, then removes
data. The share extension's persistent lock coordinates cross-process intake.
Notification callbacks carry request ownership so a late test completion cannot
remove a newer request. Calendar refresh has no write or synchronization effect.

Relevant probes include `test-conversation-state`, `test-voice-flow`,
`test-recognition-turn`, `test-speech-input`, `test-system-speech`,
`test-victoria-pcm`, `test-service-request`, `test-notification-deadline` and
`test-intake-erasure`. Full app tests exercise integration separately. Mocked
callbacks and simulator audio do not establish physical microphone reliability.
