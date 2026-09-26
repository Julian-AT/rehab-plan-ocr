#include <assert.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "fvad.h"

// Invented harmonic bursts exercise the pinned detector without recordings,
// installed voices, converters or private assets. This is not a speech-quality test.
static void synthetic_frame(int index, int16_t frame[320]) {
    memset(frame, 0, 320 * sizeof(int16_t));
    if (index < 50 || index >= 250 || index % 50 >= 35) return;
    for (int sample = 0; sample < 320; sample++) {
        double t = (index * 320 + sample) / 16000.0;
        double phase = 2.0 * 3.141592653589793 * (130.0 * t + 12.0 * sin(2.0 * t));
        double envelope = 0.6 + 0.4 * sin(19.0 * t);
        frame[sample] = (int16_t)(envelope * (6500.0 * sin(phase)
            + 2500.0 * sin(2.0 * phase) + 1200.0 * sin(5.0 * phase)));
    }
}

int main(int argc, char **argv) {
    assert(argc == 1 || argc == 2);
    Fvad *vad = fvad_new(); assert(vad);
    assert(fvad_set_sample_rate(vad, 16000) == 0);
    assert(fvad_set_mode(vad, 2) == 0);
    int16_t frame[320] = {0};
    for (int i = 0; i < 150; i++) assert(fvad_process(vad, frame, 320) == 0);
    assert(fvad_process(vad, frame, 319) == -1);
    int voiced = 0, frames = 0;
    if (argc == 2) {
        FILE *file = fopen(argv[1], "rb"); assert(file);
        while (fread(frame, sizeof(int16_t), 320, file) == 320) {
            int result = fvad_process(vad, frame, 320); assert(result >= 0);
            voiced += result; frames++;
        }
        assert(!ferror(file));
        fclose(file);
    } else {
        for (int index = 0; index < 350; index++) {
            synthetic_frame(index, frame);
            int result = fvad_process(vad, frame, 320); assert(result >= 0);
            if (index < 50 || index >= 300) assert(result == 0);
            voiced += result; frames++;
        }
    }
    fvad_free(vad);
    assert(frames > 100 && voiced > 50 && voiced < frames);
    printf("Pinned libfvad: silence and invalid windows rejected; %s %d/%d voiced 20ms frames\n",
        argc == 1 ? "synthetic harmonic bursts" : "supplied local audio", voiced, frames);
}
