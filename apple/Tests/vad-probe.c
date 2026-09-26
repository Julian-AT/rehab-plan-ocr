#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include "fvad.h"
int main(int argc, char **argv) {
    assert(argc == 2);
    Fvad *vad = fvad_new(); assert(vad);
    assert(fvad_set_sample_rate(vad, 16000) == 0);
    assert(fvad_set_mode(vad, 2) == 0);
    int16_t frame[320] = {0};
    for (int i = 0; i < 150; i++) assert(fvad_process(vad, frame, 320) == 0);
    assert(fvad_process(vad, frame, 319) == -1);
    FILE *file = fopen(argv[1], "rb"); assert(file);
    int voiced = 0, frames = 0;
    while (fread(frame, sizeof(int16_t), 320, file) == 320) {
        int result = fvad_process(vad, frame, 320); assert(result >= 0);
        voiced += result; frames++;
    }
    fclose(file); fvad_free(vad);
    assert(frames > 100 && voiced > 50 && voiced < frames);
    printf("Pinned libfvad: silence and invalid windows rejected; real Victoria audio %d/%d voiced 20ms frames\n", voiced, frames);
}
