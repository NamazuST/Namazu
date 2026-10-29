#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <math.h>

#ifndef RIG_NUM_SENSORS
#define RIG_NUM_SENSORS 5
#endif

namespace rig {
static_assert(RIG_NUM_SENSORS >= 1 && RIG_NUM_SENSORS <= 5, "Supported sensor count is 1..5");
constexpr size_t sensors = RIG_NUM_SENSORS;
constexpr size_t queueCapacity = 64;
constexpr int32_t scale = 2048; // +/-16 g
// uint64 timestamp (20) + semicolon/groups (35 each) + CRLF (2).
constexpr size_t maximumRowBytes = 22 + sensors * 35;
constexpr size_t rowCapacity = maximumRowBytes + 1;
struct Sample { int16_t x, y, z; };

constexpr int16_t decode(uint8_t hi, uint8_t lo) {
    return (uint16_t(hi) << 8 | lo) < 32768
        ? int16_t(uint16_t(hi) << 8 | lo)
        : int16_t(int32_t(uint16_t(hi) << 8 | lo) - 65536);
}
constexpr uint32_t scaledAbsolute(int16_t raw) {
    return (uint32_t(raw < 0 ? -int32_t(raw) : raw) * 10000UL + scale / 2) / scale;
}
static_assert(decode(0x80, 0x00) == -32768, "Signed big-endian decoding");
static_assert(scaledAbsolute(-32768) == 160000, "Negative full scale cannot overflow");
static_assert(scaledAbsolute(2048) == 10000, "One g conversion");

class Queue {
    Sample data[queueCapacity]{};
    size_t head = 0, used = 0;
public:
    void clear() { head = used = 0; }
    size_t size() const { return used; }
    bool push(Sample value) {
        if (used == queueCapacity) return false;
        data[(head + used) % queueCapacity] = value;
        ++used;
        return true;
    }
    const Sample &front() const { return data[head]; } // caller checks size()
    void pop() { if (used) { head = (head + 1) % queueCapacity; --used; } }
};

inline void axis(char *out, size_t capacity, int16_t raw) {
    const uint32_t value = scaledAbsolute(raw);
    snprintf(out, capacity, "%s%lu.%04lu", raw < 0 ? "-" : "",
        static_cast<unsigned long>(value / 10000), static_cast<unsigned long>(value % 10000));
}
inline size_t formatRow(char *out, size_t capacity, uint64_t ms, const Sample *samples,
                        const bool *valid = nullptr) {
    int length = snprintf(out, capacity, "%llu", static_cast<unsigned long long>(ms));
    if (length <= 0 || size_t(length) >= capacity) return 0;
    size_t used = size_t(length);
    for (size_t i = 0; i < sensors; ++i) {
        if (!samples || (valid && !valid[i])) {
            length = snprintf(out + used, capacity - used, ";nan,nan,nan,nan");
        } else {
            const Sample &s = samples[i];
            char x[12], y[12], z[12];
            axis(x, sizeof(x), s.x); axis(y, sizeof(y), s.y); axis(z, sizeof(z), s.z);
            const uint32_t mag = uint32_t(sqrtf(float(s.x)*s.x + float(s.y)*s.y + float(s.z)*s.z)
                * (10000.0f / scale) + 0.5f);
            length = snprintf(out + used, capacity - used, ";%s,%s,%s,%lu.%04lu", x, y, z,
                static_cast<unsigned long>(mag / 10000), static_cast<unsigned long>(mag % 10000));
        }
        if (length <= 0 || size_t(length) >= capacity - used) return 0;
        used += size_t(length);
    }
    if (capacity - used < 3) return 0;
    out[used++] = '\r'; out[used++] = '\n'; out[used] = '\0';
    return used;
}
} // namespace rig
