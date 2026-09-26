// Diagnostic-only CPU logits trace against the pinned local llama.cpp library.
#include "llama.h"
#include "ggml-backend.h"
#include "json.hpp"

#include <algorithm>
#include <cmath>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>
#include <numeric>
#include <stdexcept>
#include <string>
#include <sys/resource.h>
#include <vector>

using json = nlohmann::ordered_json;

static json read_json(const std::filesystem::path &path) {
    if (!std::filesystem::is_regular_file(path) || std::filesystem::file_size(path) > 1000000)
        throw std::runtime_error("Invalid diagnostic request file");
    std::ifstream input(path);
    if (!input) throw std::runtime_error("Cannot read diagnostic request");
    return json::parse(input);
}

static std::string read_prompt(const std::filesystem::path &path) {
    if (!std::filesystem::is_regular_file(path) || std::filesystem::file_size(path) > 100000)
        throw std::runtime_error("Invalid diagnostic prompt file");
    std::ifstream stream(path, std::ios::binary);
    return std::string(std::istreambuf_iterator<char>(stream), {});
}

static json rank_logits(const float *values, int count) {
    std::vector<int> order(count);
    std::iota(order.begin(), order.end(), 0);
    for (int i = 0; i < count; ++i)
        if (!std::isfinite(values[i])) throw std::runtime_error("Nonfinite logits");
    const int take = std::min(10, count);
    std::partial_sort(order.begin(), order.begin() + take, order.end(), [&](int a, int b) {
        return values[a] == values[b] ? a < b : values[a] > values[b];
    });
    json result = json::array();
    for (int i = 0; i < take; ++i)
        result.push_back({{"token", order[i]}, {"logit", values[order[i]]}});
    return result;
}

static json trace(llama_model *model, const json &request, const std::filesystem::path &output) {
    const auto *vocab = llama_model_get_vocab(model);
    const int vocabulary_size = llama_vocab_n_tokens(vocab);
    const std::string prompt = read_prompt(request.at("prompt").get<std::string>());
    const int needed = llama_tokenize(vocab, prompt.data(), prompt.size(), nullptr, 0, true, true);
    if (needed >= 0 || needed < -2048) throw std::runtime_error("Prompt token limit");
    std::vector<llama_token> input(-needed);
    if (llama_tokenize(vocab, prompt.data(), prompt.size(), input.data(), input.size(), true, true) != -needed)
        throw std::runtime_error("Tokenization length changed");
    const int limit = request.at("max_tokens");
    const bool forced = request.contains("prefix");
    const auto prefix = request.value("prefix", std::vector<llama_token>{});
    if (limit < 1 || limit > 256 || input.size() + limit > 2048 || prefix.size() >= size_t(limit))
        throw std::runtime_error("Diagnostic generation limit");
    for (int token : prefix)
        if (token < 0 || token >= vocabulary_size) throw std::runtime_error("Invalid forced token");

    auto parameters = llama_context_default_params();
    parameters.n_ctx = 2048;
    parameters.n_batch = 512;
    parameters.n_ubatch = 128;
    parameters.n_threads = 4;
    parameters.n_threads_batch = 4;
    parameters.offload_kqv = false;
    parameters.op_offload = false;
    parameters.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO;
    parameters.type_k = GGML_TYPE_F16;
    parameters.type_v = GGML_TYPE_F16;
    std::unique_ptr<llama_context, decltype(&llama_free)> context(
        llama_init_from_model(model, parameters), llama_free);
    std::unique_ptr<llama_sampler, decltype(&llama_sampler_free)> sampler(
        llama_sampler_init_greedy(), llama_sampler_free);
    if (!context || !sampler) throw std::runtime_error("Cannot initialize diagnostic context");
    for (size_t offset = 0; offset < input.size(); offset += 512) {
        auto batch = llama_batch_get_one(input.data() + offset, std::min<size_t>(512, input.size() - offset));
        if (llama_decode(context.get(), batch)) throw std::runtime_error("Prompt decode failed");
    }
    json result = {{"id", request.at("id")}, {"input_tokens", input}, {"tokens", json::array()},
                   {"steps", json::array()}, {"text", ""}, {"eos", false},
                   {"vocabulary_size", vocabulary_size}, {"logits_dtype", "float32"}};
    std::string text;
    for (int position = 0; position < limit; ++position) {
        const float *logits = llama_get_logits_ith(context.get(), -1);
        if (!logits) throw std::runtime_error("Missing logits");
        const auto ranked = rank_logits(logits, vocabulary_size);
        const llama_token greedy = llama_sampler_sample(sampler.get(), context.get(), -1);
        llama_token token = size_t(position) < prefix.size() ? prefix[position] : greedy;
        result["steps"].push_back({{"greedy", greedy}, {"selected", token}, {"top", ranked}});
        result["tokens"].push_back(token);
        if (forced && size_t(position) == prefix.size()) {
            const auto filename = "case-" + request.at("id").get<std::string>() + ".logits.f32";
            const auto path = output / filename;
            if (std::filesystem::exists(path)) throw std::runtime_error("Logits already exist");
            std::ofstream stream(path, std::ios::binary);
            stream.write(reinterpret_cast<const char *>(logits), sizeof(float) * vocabulary_size);
            if (!stream) throw std::runtime_error("Cannot save logits");
            result["logits_file"] = filename;
        }
        if (llama_vocab_is_eog(vocab, token)) {
            result["eos"] = true;
            break;
        }
        char piece[4096];
        const int size = llama_token_to_piece(vocab, token, piece, sizeof(piece), 0, true);
        if (size < 0) throw std::runtime_error("Diagnostic token piece limit");
        text.append(piece, size);
        if (position + 1 < limit && llama_decode(context.get(), llama_batch_get_one(&token, 1)))
            throw std::runtime_error("Continuation decode failed");
    }
    result["text"] = text;
    return result;
}

int main(int argc, char **argv) {
    try {
        if (argc != 4) throw std::runtime_error("Usage: token-trace MODEL REQUEST_JSON NEW_OUTPUT_DIRECTORY");
        const std::filesystem::path output(argv[3]);
        if (std::filesystem::exists(output)) throw std::runtime_error("Preserve previous output");
        const auto request = read_json(argv[2]);
        if (!request.is_array() || request.empty() || request.size() > 40)
            throw std::runtime_error("Expected one to forty retained diagnostic cases");
        for (const auto &row : request) {
            const std::string id = row.at("id");
            if (id.empty() || id.find_first_not_of("0123456789") != std::string::npos)
                throw std::runtime_error("Case identity must be a decimal index");
        }
        std::filesystem::create_directory(output);
        std::filesystem::permissions(output, std::filesystem::perms::owner_all);
        ggml_backend_load_all();
        auto parameters = llama_model_default_params();
        parameters.n_gpu_layers = 0;
        std::unique_ptr<llama_model, decltype(&llama_model_free)> model(
            llama_model_load_from_file(argv[1], parameters), llama_model_free);
        if (!model) throw std::runtime_error("Cannot load diagnostic model");
        json report = {{"diagnostic", true}, {"qualified", false}, {"cases", json::array()}};
        for (const auto &row : request) {
            const auto started = std::chrono::steady_clock::now();
            auto result = trace(model.get(), row, output);
            result["elapsed_seconds"] = std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count();
            report["cases"].push_back(result);
            std::cerr << "Traced CPU case " << row.at("id") << '\n';
        }
        rusage usage{};
        getrusage(RUSAGE_SELF, &usage);
        report["host_peak_rss_bytes"] = usage.ru_maxrss; // This helper targets the pinned macOS runtime.
        std::ofstream stream(output / "report.json");
        stream << report.dump(2) << '\n';
        if (!stream) throw std::runtime_error("Cannot save diagnostic report");
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
