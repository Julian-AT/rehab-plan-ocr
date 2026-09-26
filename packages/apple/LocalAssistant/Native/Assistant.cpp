#include "RehaAssistantNative.h"
#include "llama.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

using Clock = std::chrono::steady_clock;

struct reha_assistant_operation {
    std::atomic<bool> cancelled{false};
    Clock::time_point deadline;
    explicit reha_assistant_operation(uint32_t timeout_ms)
        : deadline(Clock::now() + std::chrono::milliseconds(timeout_ms)) {}
    reha_assistant_status status() const {
        if (cancelled.load(std::memory_order_relaxed)) return REHA_ASSISTANT_CANCELLED;
        return Clock::now() >= deadline ? REHA_ASSISTANT_DEADLINE : REHA_ASSISTANT_OK;
    }
};

struct reha_assistant_model {
    std::unique_ptr<llama_model, decltype(&llama_model_free)> model{nullptr, llama_model_free};
    std::mutex use;
};

static bool abort_generation(void *context) {
    return static_cast<reha_assistant_operation *>(context)->status() != REHA_ASSISTANT_OK;
}

static bool continue_loading(float, void *context) { return !abort_generation(context); }

extern "C" reha_assistant_operation *reha_assistant_operation_create(uint32_t timeout_ms) {
    if (timeout_ms == 0 || timeout_ms > 120000) return nullptr;
    try { return new reha_assistant_operation(timeout_ms); } catch (...) { return nullptr; }
}

extern "C" void reha_assistant_operation_cancel(reha_assistant_operation *operation) {
    if (operation) operation->cancelled.store(true, std::memory_order_relaxed);
}

extern "C" reha_assistant_status reha_assistant_operation_status(const reha_assistant_operation *operation) {
    return operation ? operation->status() : REHA_ASSISTANT_INVALID_INPUT;
}

extern "C" void reha_assistant_operation_free(reha_assistant_operation *operation) { delete operation; }
extern "C" void reha_assistant_model_free(reha_assistant_model *model) { delete model; }

extern "C" reha_assistant_model *reha_assistant_load(
    const char *path, reha_assistant_operation *operation, reha_assistant_status *status) {
    if (!status) return nullptr;
    *status = REHA_ASSISTANT_INVALID_INPUT;
    if (!path || !*path || !operation) return nullptr;
    if ((*status = operation->status()) != REHA_ASSISTANT_OK) return nullptr;
    try {
        static std::once_flag initialized;
        std::call_once(initialized, [] { llama_backend_init(); });
        auto result = std::make_unique<reha_assistant_model>();
        auto parameters = llama_model_default_params();
        // CPU is the initial parity/cancellation route. Metal is a separately
        // measured backend candidate; never report these results as device speed.
        parameters.n_gpu_layers = 0;
        parameters.progress_callback = continue_loading;
        parameters.progress_callback_user_data = operation;
        result->model.reset(llama_model_load_from_file(path, parameters));
        if ((*status = operation->status()) != REHA_ASSISTANT_OK) return nullptr;
        if (!result->model) { *status = REHA_ASSISTANT_MODEL_ERROR; return nullptr; }
        *status = REHA_ASSISTANT_OK;
        return result.release();
    } catch (...) {
        *status = REHA_ASSISTANT_MODEL_ERROR;
        return nullptr;
    }
}

extern "C" reha_assistant_status reha_assistant_generate(
    reha_assistant_model *model, reha_assistant_operation *operation,
    const char *prompt, size_t prompt_bytes, uint32_t maximum_tokens,
    char *output, size_t output_capacity, size_t *output_bytes) {
    if (output_bytes) *output_bytes = 0;
    if (output && output_capacity) output[0] = 0;
    if (!model || !operation || !prompt || !prompt_bytes || prompt_bytes > 131072 ||
        !output || output_capacity < 2 || output_capacity > 8193 || !output_bytes ||
        !maximum_tokens || maximum_tokens > 192) return REHA_ASSISTANT_INVALID_INPUT;
    if (operation->status() != REHA_ASSISTANT_OK) return operation->status();
    try {
        std::unique_lock<std::mutex> ownership(model->use, std::try_to_lock);
        if (!ownership.owns_lock()) return REHA_ASSISTANT_BUSY;
        const auto *vocab = llama_model_get_vocab(model->model.get());
        const int needed = llama_tokenize(vocab, prompt, static_cast<int>(prompt_bytes), nullptr, 0, true, true);
        if (needed >= 0 || needed < -2048) return REHA_ASSISTANT_CONTEXT_LIMIT;
        const int count = -needed;
        if (count + maximum_tokens > 2048) return REHA_ASSISTANT_CONTEXT_LIMIT;
        std::vector<llama_token> tokens(count);
        if (llama_tokenize(vocab, prompt, static_cast<int>(prompt_bytes), tokens.data(), count, true, true) != count)
            return REHA_ASSISTANT_GENERATION_ERROR;

        auto parameters = llama_context_default_params();
        parameters.n_ctx = 2048;
        parameters.n_batch = 512;
        parameters.n_ubatch = 128;
        parameters.n_threads = 4;
        parameters.n_threads_batch = 4;
        parameters.abort_callback = abort_generation;
        parameters.abort_callback_data = operation;
        std::unique_ptr<llama_context, decltype(&llama_free)> context(
            llama_init_from_model(model->model.get(), parameters), llama_free);
        if (operation->status() != REHA_ASSISTANT_OK) return operation->status();
        if (!context) return REHA_ASSISTANT_GENERATION_ERROR;
        std::unique_ptr<llama_sampler, decltype(&llama_sampler_free)> sampler(
            llama_sampler_init_greedy(), llama_sampler_free);
        if (!sampler) return REHA_ASSISTANT_GENERATION_ERROR;

        for (int position = 0; position < count; position += 512) {
            if (operation->status() != REHA_ASSISTANT_OK) return operation->status();
            const auto batch = llama_batch_get_one(tokens.data() + position, std::min(512, count - position));
            if (llama_decode(context.get(), batch))
                return operation->status() == REHA_ASSISTANT_OK ? REHA_ASSISTANT_GENERATION_ERROR : operation->status();
        }
        std::string text;
        for (uint32_t index = 0; index < maximum_tokens; ++index) {
            if (operation->status() != REHA_ASSISTANT_OK) return operation->status();
            auto token = llama_sampler_sample(sampler.get(), context.get(), -1);
            if (llama_vocab_is_eog(vocab, token)) {
                // Deliver complete output once. Partial/canceled JSON has no delivery path.
                if (operation->status() != REHA_ASSISTANT_OK) return operation->status();
                std::memcpy(output, text.data(), text.size());
                output[text.size()] = 0;
                *output_bytes = text.size();
                return REHA_ASSISTANT_OK;
            }
            char piece[512];
            const int length = llama_token_to_piece(vocab, token, piece, sizeof(piece), 0, true);
            if (length < 0 || text.size() + length >= output_capacity) return REHA_ASSISTANT_OUTPUT_LIMIT;
            text.append(piece, length);
            if (llama_decode(context.get(), llama_batch_get_one(&token, 1)))
                return operation->status() == REHA_ASSISTANT_OK ? REHA_ASSISTANT_GENERATION_ERROR : operation->status();
        }
        return REHA_ASSISTANT_OUTPUT_LIMIT;
    } catch (...) { return REHA_ASSISTANT_GENERATION_ERROR; }
}
