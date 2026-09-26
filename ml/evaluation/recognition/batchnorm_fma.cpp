// Diagnostic only: explicit FP32 contraction of two source-derived affine steps.
// Compile without implicit contraction; only std::fma may fuse operations.
#include <cfenv>
#include <cmath>
#include <cstddef>

extern "C" int batchnorm_affine(
    const float * input, const float * adjusted_scale, const float * adjusted_bias,
    const float * mean_inverse, const float * scale, const float * bias,
    std::size_t channels, std::size_t plane, int mode, float * output) {
    if (!input || !adjusted_scale || !adjusted_bias || !mean_inverse || !scale || !bias ||
        !output || channels == 0 || plane == 0 || channels > 1000000 ||
        plane > 1000000 / channels || mode < 0 || mode > 3 ||
        std::fegetround() != FE_TONEAREST) return 1;
    for (std::size_t c = 0; c < channels; ++c) {
        const float offset = mode & 2
            ? std::fma(-mean_inverse[c], scale[c], bias[c]) : adjusted_bias[c];
        for (std::size_t p = 0; p < plane; ++p) {
            const auto index = c * plane + p;
            if (mode & 1) {
                output[index] = std::fma(input[index], adjusted_scale[c], offset);
            } else {
                const float product = input[index] * adjusted_scale[c];
                output[index] = product + offset;
            }
        }
    }
    return 0;
}
