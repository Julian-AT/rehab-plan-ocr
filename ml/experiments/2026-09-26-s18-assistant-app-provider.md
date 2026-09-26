> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Custom provider in the app binary — 2026-09-26

The actual common provider now runs the unqualified custom GGUF in a separate
Debug simulator build. The normal project retains Apple Intelligence plus complete
rules. This verifies integration, not model quality or full voice interaction.

Run: `.local/runs/assistant-app-provider-20260926-s17-002`.
Report SHA-256: `0b2ff06c7c7bd6a3a6a329bee9d49e59c0050bd3fd2fe0fef9e93c01f07e11c3`.
App binary: `657c28a50c3ef4dfebf428075b72143caf32a868e981157188b3a9bdfc1cb42b`.
The copied build receipt records exact sources, compiler, model/prompt/native
identities and bundled notices. The source revision starts at `3962ffc`; the
receipt's file hashes describe this additional implementation.

| Check | Result |
|---|---|
| Exact common prompt matches training template | Pass |
| Complete ordinary question selects rules | Pass |
| Both non-rule cases select custom GGUF | Pass |
| Complete native output crosses typed Rust/Swift boundary | Pass |
| Exact expected operations | 0/2 |
| Unsafe mutation proposals | 1/2 |
| Calendar operations executed | 0 |
| Regular release packaging accepts trial app | Rejected as required |

The date correction still becomes the wrong day and detail. The room question
still becomes an unwanted date update. These are the same two previously exposed
development families; there are no additional independent or human-reviewed
dialogues. Compatibility does not qualify their output.

The simulator-only probe uses the real `AssistantProviderSelection`, router,
custom provider, pinned model and typed decoder in the app binary. It opens neither
`NativeApplication` nor an audio session. Therefore it bypasses the unresolved
simulator CoreAudio failure and cannot establish a complete spoken workflow,
calendar confirmation behavior, first-audio latency or physical resources.

The first combined build exposed a collision between flat native libraries named
`module.modulemap`. The assistant now uses a namespaced static framework inside
its XCFramework. Its private generated Info.plist also requires explicitly excluding
the ordinary source plist from copied resources. Both normal and trial builds pass.
The first probe (`001`) requested 180 seconds, exceeding the native maximum of
120 seconds. The corrected probe uses the same 30-second deadline as the app.

`CustomAssistantProvider` keeps the current request when context overflows and
removes only whole oldest historical turns. It never retries another provider.
History template delimiters are escaped as JSON data; current delimiter-bearing
input is rejected. Missing assets leave complete-rule questions available. Task
cancellation and the existing monotonic deadline still prevent late delivery.

The native library now unloads cached weights after queued work. Run
`.local/runs/assistant-native-20260926-s17-003` verifies actual host/simulator unload,
reload and unchanged output as well as cancellation/deadline/state isolation.
Report: `013646891e5ceec8916deede43d1732547d4deed4f7162faf2187ba365d2ca7e`.
Both completion reports: `c341875d4f4f153e48de8c88ee64e7d62e0e8208a86da0f75556b8d56d7520dd`.
That earlier package-only run preceded framework repackaging; the later app run
verifies the packaged framework. No memory/energy improvement is inferred.

Reproduction, with private model assets already restored and a disposable booted
`Termine-Native-Test-*` simulator, running simulator work serially:

```sh
make build-assistant-native ASSISTANT_NATIVE_TARGETS='host simulator device'
make build-assistant-trial
make test-assistant-app-trial TEST_ARGS='--run .local/runs/<new-run> --simulator <id>'
make test-custom-assistant-provider test-assistant-request test-interpretation-provider
make test-tools
```

The trial's `qualified: false` manifest and Info.plist marker exclude ordinary
packaging. The builder restores the normal generated Xcode project even on failure.
No physical device was installed or updated. Full provider comparison, independently
checked German dialogues, model qualification, complete speech/UI flows and real
hardware evaluation remain open.
