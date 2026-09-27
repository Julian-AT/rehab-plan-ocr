# System speech output

The default build uses installed Apple voices and bundles no speech weights or
eSpeak phonemizer. The user selects available system voices; installed availability
can differ by device and operating system. Initial speech-recognition asset setup
can require Internet. The optional [Victoria profile](personal-victoria.md) has a
separate build and preserves the original personal voice preference.

The output queue owns playback ordering, interruption and heard-word progress.
Rendering and PCM validation run outside the UI actor. Cancellation and generation
ownership are checked before delivery so obsolete output cannot start speaking.
Foreground conversation temporarily prevents automatic sleep while active;
explicit backgrounding still ends capture.

Run `make test-system-speech`, `make test-victoria-pcm`, `make test-recognition-turn`
and the voice-flow probes for lifecycle/endpoint behavior. `make prepare-listening
RUN=.local/runs/<new-run>` creates host listening samples. Human listening,
installed voice availability and real microphone-to-answer reliability need
separate device evidence; synthetic samples are not quality qualification.
