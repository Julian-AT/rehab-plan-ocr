// Diagnostic only: two fixed ARM64 reciprocal implementations, no model rewrite.
#include <arm_neon.h>
#include <cfenv>
#include <cmath>
#include <cstddef>
#include <cstdint>

static bool supported(float value) {
    return std::isfinite(value) && (value == 0 || std::isnormal(value));
}

extern "C" int batchnorm_reciprocal(
    const float * input, const float * scale, const float * bias,
    const float * mean, const float * variance, float epsilon,
    std::size_t channels, std::size_t plane, int mode,
    float * coefficients, float * output) {
    std::uint64_t fpcr;
    __asm__ volatile("mrs %0, fpcr" : "=r"(fpcr));
    if (!input || !scale || !bias || !mean || !variance || !coefficients || !output ||
        channels == 0 || channels % 4 || plane == 0 || channels > 1000000 ||
        plane > 1000000 / channels || mode < 0 || mode > 1 ||
        std::fegetround() != FE_TONEAREST || (fpcr & ((1ULL << 24) | 1ULL)) ||
        !supported(epsilon) || epsilon < 0) return 1;
    for (std::size_t c = 0; c < channels; ++c) {
        const float denominator = variance[c] + epsilon;
        if (!supported(scale[c]) || !supported(bias[c]) || !supported(mean[c]) ||
            !supported(variance[c]) || variance[c] < 0 ||
            !std::isnormal(denominator) || denominator <= 0) return 1;
    }
    for (std::size_t i = 0; i < channels * plane; ++i) {
        if (!supported(input[i])) return 1;
    }
    for (std::size_t c = 0; c < channels; c += 4) {
        const auto stddev = vsqrtq_f32(vaddq_f32(vld1q_f32(variance + c), vdupq_n_f32(epsilon)));
        float32x4_t inverse;
        if (mode == 0) {
            inverse = vrecpeq_f32(stddev);
            inverse = vmulq_f32(vrecpsq_f32(stddev, inverse), inverse);
            inverse = vmulq_f32(vrecpsq_f32(stddev, inverse), inverse);
        } else {
            inverse = vdivq_f32(vdupq_n_f32(1), stddev);
        }
        const auto adjusted_scale = vmulq_f32(inverse, vld1q_f32(scale + c));
        const auto mean_inverse = vmulq_f32(vld1q_f32(mean + c), inverse);
        const auto offset = vmulq_f32(mean_inverse, vld1q_f32(scale + c));
        const auto adjusted_bias = vsubq_f32(vld1q_f32(bias + c), offset);
        vst1q_f32(coefficients + c, inverse);
        vst1q_f32(coefficients + channels + c, adjusted_scale);
        vst1q_f32(coefficients + 2 * channels + c, mean_inverse);
        vst1q_f32(coefficients + 3 * channels + c, adjusted_bias);
    }
    for (std::size_t c = 0; c < channels; ++c) {
        for (std::size_t p = 0; p < plane; ++p) {
            const auto index = c * plane + p;
            const float product = input[index] * coefficients[channels + c];
            output[index] = product + coefficients[3 * channels + c];
        }
    }
    return 0;
}
