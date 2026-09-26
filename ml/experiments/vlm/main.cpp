#include "adapter.h"
#include "nlohmann/json.hpp"
#include <cerrno>
#include <chrono>
#include <fcntl.h>
#include <fstream>
#include <iostream>
#include <memory>
#include <sys/resource.h>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

namespace {
constexpr size_t max_image_bytes = 40 * 1024 * 1024;

bool read_image(const char * path, std::vector<uint8_t> & bytes) {
    // Bound the allocation before reading. Reading one extra byte also detects
    // growth after tellg; a changed input must not be silently truncated.
    std::ifstream input(path, std::ios::binary | std::ios::ate);
    if (!input) return false;
    const auto size = input.tellg();
    if (size <= 0 || size > static_cast<std::streamoff>(max_image_bytes)) return false;
    bytes.resize(static_cast<size_t>(size) + 1);
    input.seekg(0);
    input.read(reinterpret_cast<char *>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
    if (input.bad() || !input.eof() || input.gcount() != size) return false;
    bytes.resize(static_cast<size_t>(size));
    return true;
}

bool publish_report(const char * path, const std::string & text) {
    // Existing evidence and symlinks are never opened for writing. An interrupted
    // or failed publication has a nonzero exit and cannot qualify a candidate.
    const int fd = open(path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR);
    if (fd < 0) return false;
    size_t offset = 0;
    bool success = true;
    while (offset < text.size()) {
        const auto written = write(fd, text.data() + offset, text.size() - offset);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) { success = false; break; }
        offset += static_cast<size_t>(written);
    }
    if (success && fsync(fd) != 0) success = false;
    if (close(fd) != 0) success = false;
    return success;
}
}

int main(int argc, char ** argv) {
    if (argc != 6) {
        std::cerr << "Usage: reha-vlm-read MODEL PROJECTOR FAMILY IMAGE OUTPUT_JSON\n";
        return 2;
    }
    const auto start = std::chrono::steady_clock::now();
    std::vector<uint8_t> bytes;
    if (!read_image(argv[4], bytes)) {
        std::cerr << "Image is missing, empty, changed or larger than 40 MiB.\n";
        return 2;
    }
    std::unique_ptr<reha_vlm, decltype(&reha_vlm_close)> engine(
        reha_vlm_open(argv[1], argv[2], argv[3], 60000), reha_vlm_close);
    std::vector<char> output(32768);
    int tokens = 0;
    const int status = engine ? reha_vlm_read(engine.get(), bytes.data(), bytes.size(), 256,
                                            output.data(), output.size(), &tokens) : -1;
    struct rusage usage{};
    getrusage(RUSAGE_SELF, &usage);
#ifdef __APPLE__
    const auto peak_rss_bytes = usage.ru_maxrss;
#else
    const auto peak_rss_bytes = usage.ru_maxrss * 1024;
#endif
    nlohmann::json report = {
        {"schema_version", 1},
        {"status", status == 0 ? "complete" : status == 1 ? "limited" : "incompatible_or_failed"},
        {"text", output.data()}, {"tokens", tokens}, {"max_tokens", 256}, {"context", 4096},
        {"image_max_tokens", 1024}, {"threads", 2}, {"cpu_only", true}, {"approved", false},
        {"total_ms", std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - start).count()},
        {"peak_rss_bytes", peak_rss_bytes}
    };
    if (!publish_report(argv[5], report.dump(2, ' ', false,
                                          nlohmann::json::error_handler_t::replace) + "\n")) {
        std::cerr << "Result could not be saved to a new file.\n";
        return 3;
    }
    return status < 0 ? 1 : 0;
}
