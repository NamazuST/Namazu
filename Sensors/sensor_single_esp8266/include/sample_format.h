#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <math.h>

namespace sample_format {
constexpr int32_t scaleLsbPerG = 2048; // +/-16 g
constexpr uint32_t scaledMagnitude(int16_t raw) {
    const int32_t wide = raw;
    const uint32_t absolute = wide < 0 ? uint32_t(-wide) : uint32_t(wide);
    return (absolute * 10000UL + scaleLsbPerG / 2) / scaleLsbPerG;
}
constexpr int16_t decodeAxis(uint8_t high, uint8_t low) {
    const uint16_t bits = (uint16_t(high) << 8) | low;
    return bits < 32768 ? int16_t(bits) : int16_t(int32_t(bits) - 65536);
}
inline void formatAxis(char *output, size_t capacity, int16_t raw) {
    const uint32_t scaled = scaledMagnitude(raw);
    snprintf(output, capacity, "%s%lu.%04lu", raw < 0 ? "-" : "",
             static_cast<unsigned long>(scaled / 10000),
             static_cast<unsigned long>(scaled % 10000));
}
inline size_t formatRow(char *output, size_t capacity, uint64_t timestampMs,
                        int16_t x, int16_t y, int16_t z) {
    char ax[12], ay[12], az[12];
    formatAxis(ax, sizeof(ax), x);
    formatAxis(ay, sizeof(ay), y);
    formatAxis(az, sizeof(az), z);
    const float magRaw = sqrtf(float(x) * x + float(y) * y + float(z) * z);
    const uint32_t mag = uint32_t(magRaw * (10000.0f / scaleLsbPerG) + 0.5f);
    const int length = snprintf(output, capacity, "%llu;%s,%s,%s,%lu.%04lu\r\n",
        static_cast<unsigned long long>(timestampMs), ax, ay, az,
        static_cast<unsigned long>(mag / 10000), static_cast<unsigned long>(mag % 10000));
    return length > 0 && size_t(length) < capacity ? size_t(length) : 0;
}
static_assert(scaledMagnitude(-32768) == 160000, "Negative full scale must not overflow.");
static_assert(scaledMagnitude(32767) == 159995, "Positive full scale must retain resolution.");
static_assert(scaledMagnitude(2048) == 10000, "One g must map to 1.0000.");
static_assert(decodeAxis(0x80, 0x00) == -32768 && decodeAxis(0x7F, 0xFF) == 32767,
              "FIFO axes must decode signed big-endian values.");
} // namespace sample_format
