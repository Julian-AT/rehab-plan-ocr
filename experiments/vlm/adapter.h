#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// A narrow in-process interface. No calendar or network capability. Model paths must
// be verified against the experiment lock by the caller before loading.
typedef struct reha_vlm reha_vlm;
reha_vlm * reha_vlm_open(const char * model, const char * projector, const char * family, int budget_ms);
// Image bytes are decoded locally. All output is an unapproved crop reading.
// status: 0 complete, 1 budget/cancel/output limit, -1 incompatible/invalid.
int reha_vlm_read(reha_vlm *, const uint8_t * image, size_t image_size,
                  int max_tokens, char * output, size_t capacity, int * tokens);
void reha_vlm_cancel(reha_vlm *);
void reha_vlm_close(reha_vlm *);
#ifdef __cplusplus
}
#endif
