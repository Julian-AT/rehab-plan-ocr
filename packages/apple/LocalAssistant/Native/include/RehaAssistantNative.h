#ifndef REHA_ASSISTANT_NATIVE_H
#define REHA_ASSISTANT_NATIVE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct reha_assistant_model reha_assistant_model;
typedef struct reha_assistant_operation reha_assistant_operation;

typedef enum {
    REHA_ASSISTANT_OK = 0,
    REHA_ASSISTANT_INVALID_INPUT = 1,
    REHA_ASSISTANT_MODEL_ERROR = 2,
    REHA_ASSISTANT_CONTEXT_LIMIT = 3,
    REHA_ASSISTANT_CANCELLED = 4,
    REHA_ASSISTANT_DEADLINE = 5,
    REHA_ASSISTANT_GENERATION_ERROR = 6,
    REHA_ASSISTANT_OUTPUT_LIMIT = 7,
    REHA_ASSISTANT_BUSY = 8
} reha_assistant_status;

// Operations have independent cancellation/deadline state. cancel is thread-safe;
// free must happen after its load/generation call has returned.
reha_assistant_operation *reha_assistant_operation_create(uint32_t timeout_ms);
reha_assistant_status reha_assistant_operation_status(const reha_assistant_operation *operation);
void reha_assistant_operation_cancel(reha_assistant_operation *operation);
void reha_assistant_operation_free(reha_assistant_operation *operation);

// Blocking native calls belong on a background executor. Models may be reused;
// each generation has fresh context/sampler state. Concurrent calls return BUSY.
reha_assistant_model *reha_assistant_load(const char *path, reha_assistant_operation *operation,
                                        reha_assistant_status *status);
void reha_assistant_model_free(reha_assistant_model *model);
reha_assistant_status reha_assistant_generate(
    reha_assistant_model *model, reha_assistant_operation *operation,
    const char *prompt, size_t prompt_bytes, uint32_t maximum_tokens,
    char *output, size_t output_capacity, size_t *output_bytes);

#ifdef __cplusplus
}
#endif
#endif
