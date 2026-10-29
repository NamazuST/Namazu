// AZ-Delivery ESP32-WROOM-32, five GY-521 sensors; see README before wiring.
#include <Arduino.h>
#include <Wire.h>
#include <esp_timer.h>
#include <string.h>
#include "rig_data.h"

#ifndef RIG_RATE_HZ
#define RIG_RATE_HZ 500
#endif
#ifndef RIG_BAUD
#define RIG_BAUD 921600
#endif

namespace {
constexpr uint32_t baud = RIG_BAUD;
static_assert(RIG_RATE_HZ == 500 || RIG_RATE_HZ == 333 || RIG_RATE_HZ == 250, "Unsupported rate profile");
constexpr uint32_t periodMs = RIG_RATE_HZ == 333 ? 3 : 1000 / RIG_RATE_HZ;
constexpr double rate = 1000.0 / periodMs;
// 500 Hz fits ordinary rows, but not indefinitely sustained longest rows.
// Bounded queues stop acquisition explicitly if UART throughput is exceeded.
static_assert(RIG_RATE_HZ == 500 || rig::maximumRowBytes * 10000 / periodMs <= baud,
    "Conservative profiles must fit even the longest full-range CSV rows");
constexpr int sda = 32, scl = 33;
// Park every rig select line, including unused ones in the one-sensor profile.
constexpr int ad0[5] = {25, 26, 27, 14, 13};
constexpr uint8_t address = 0x68, dlpf = rate == 500 ? 1 : 2;
constexpr uint8_t divider = periodMs - 1;
constexpr uint32_t pollUs = 8000, noDataUs = 100000;
constexpr uint16_t maxFifo = 480; // below even a 512-byte compatible-part FIFO
constexpr size_t maxCountSkew = 4; // fail rather than silently drop/repeat frames

rig::Queue queues[rig::sensors];
uint8_t identity[rig::sensors]{};
uint64_t frames[rig::sensors]{}, lastSensorUs[rig::sensors]{};
uint64_t totalRows = 0, segmentRows = 0, epochMs = 0, lastRowMs = 0;
uint64_t startedUs = 0, nextPollUs = 0;
uint32_t i2cErrors = 0, fifoOverflows = 0, faults = 0, nearLimit = 0;
uint32_t startSpanUs = 0, maximumSweepUs = 0;
size_t maximumQueue = 0, maximumSkew = 0;
uint16_t maximumFifo = 0;
bool streaming = false, ready = false, haveRow = false;
int selected = -1;
char command[32]{};
size_t commandLength = 0;
bool commandOverflow = false;

uint64_t nowUs() { return uint64_t(esp_timer_get_time()); }
void park() {
    for (int pin : ad0) digitalWrite(pin, HIGH);
    selected = -1;
    delayMicroseconds(20);
}
void select(size_t id) {
    if (selected == int(id)) return;
    if (selected >= 0) digitalWrite(ad0[selected], HIGH); // deselect before selecting
    digitalWrite(ad0[id], LOW);
    selected = int(id);
    delayMicroseconds(20);
}
bool writeReg(uint8_t reg, uint8_t value) {
    Wire.beginTransmission(address); Wire.write(reg); Wire.write(value);
    if (Wire.endTransmission(true) == 0) return true;
    ++i2cErrors; return false;
}
bool readRegs(uint8_t reg, uint8_t *out, uint8_t count) {
    Wire.beginTransmission(address); Wire.write(reg);
    if (Wire.endTransmission(false) != 0 ||
        Wire.requestFrom(address, count, uint8_t(true)) != count) {
        while (Wire.available()) Wire.read();
        ++i2cErrors; return false;
    }
    for (uint8_t i = 0; i < count; ++i) out[i] = uint8_t(Wire.read());
    return true;
}
bool verify(uint8_t reg, uint8_t expected, uint8_t mask = 0xFF) {
    uint8_t value = 0;
    return readRegs(reg, &value, 1) && (value & mask) == expected;
}
bool stopAll() {
    streaming = false;
    bool ok = true;
    for (size_t i = 0; i < rig::sensors; ++i) {
        select(i);
        const bool a = writeReg(0x23, 0); // FIFO_EN
        const bool b = writeReg(0x6A, 0); // USER_CTRL
        ok = a && b && ok;
        queues[i].clear();
    }
    park();
    return ok;
}
void printHeader() {
    Serial.print("t_ms");
    for (unsigned i = 1; i <= rig::sensors; ++i)
        Serial.printf(";S%u_ax_g,S%u_ay_g,S%u_az_g,S%u_mag_g", i, i, i, i);
    Serial.println();
}
void marker(const char *kind, const char *reason, int sensor) {
    uint64_t ms = nowUs() / 1000;
    if (haveRow && ms <= lastRowMs) ms = lastRowMs + periodMs;
    char row[rig::rowCapacity];
    const size_t length = rig::formatRow(row, sizeof(row), ms, nullptr);
    Serial.write(reinterpret_cast<const uint8_t *>(row), length);
    lastRowMs = ms; haveRow = true;
    Serial.printf("# %s reason=%s sensor=%d; stream stopped, send start after checking rig\r\n",
                  kind, reason, sensor);
}
void fail(const char *reason, int sensor = 0) {
    ++faults;
    stopAll(); ready = false;
    marker("STREAM_FAULT", reason, sensor);
}
void settings() {
    Serial.printf("# ESP32 GRUENI %u-sensor FIFO rig\r\n", unsigned(rig::sensors));
    Serial.printf("# sensors=%u sample_rate_hz=%.6f serial_baud=%lu range_g=16 scale_lsb_per_g=2048\r\n",
        unsigned(rig::sensors), rate, static_cast<unsigned long>(baud));
    if (RIG_RATE_HZ == 500 && rig::sensors == 5)
        Serial.println("# 500 Hz requires a delivery test; use 333 Hz profile if long rows exhaust UART capacity");
    Serial.print("# SDA=G32 SCL=G33 AD0=");
    for (size_t i = 0; i < rig::sensors; ++i)
        Serial.printf("%sS%u:G%d", i ? "," : "", unsigned(i+1), ad0[i]);
    Serial.println(" I2C=400000 WiFi=off");
    Serial.printf("# DLPF=%u nominal_accel_bandwidth_hz=%u; verify on non-0x68 parts\r\n",
                  unsigned(dlpf), rate == 500 ? 184u : 94u);
    Serial.println("# t_ms is a nominal frame grid; sensors use independent clocks, not simultaneous sampling");
    Serial.println("# commands: stats, diag, pause, start, resume, validate");
}
void stats() {
    const uint64_t elapsed = streaming ? nowUs() - startedUs : 0;
    const double measured = elapsed ? double(segmentRows) * 1e6 / elapsed : 0;
    Serial.printf("# STATS rows=%llu streaming=%u observed_hz=%.3f i2c_errors=%lu fifo_overflows=%lu faults=%lu near_limit=%lu max_fifo_bytes=%u max_queue=%u max_count_skew=%u start_span_us=%lu max_sweep_us=%lu\r\n",
        static_cast<unsigned long long>(totalRows), unsigned(streaming), measured,
        static_cast<unsigned long>(i2cErrors), static_cast<unsigned long>(fifoOverflows),
        static_cast<unsigned long>(faults), static_cast<unsigned long>(nearLimit), unsigned(maximumFifo),
        unsigned(maximumQueue), unsigned(maximumSkew), static_cast<unsigned long>(startSpanUs),
        static_cast<unsigned long>(maximumSweepUs));
    for (size_t i = 0; i < rig::sensors; ++i)
        Serial.printf("# SENSOR id=%u who=0x%02X frames=%llu observed_hz=%.3f\r\n", unsigned(i+1),
            unsigned(identity[i]), static_cast<unsigned long long>(frames[i]),
            elapsed ? double(frames[i]) * 1e6 / elapsed : 0);
}
bool initialize() {
    ready = false;
    park();
    Wire.beginTransmission(address);
    const uint8_t result = Wire.endTransmission(true);
    if (result != 2) { // with everyone at 0x69, 0x68 must NACK its address
        Serial.printf("# ERROR parked_address_check result=%u; check each AD0 wire\r\n", unsigned(result));
        return false;
    }
    bool allOK = true;
    for (size_t i = 0; i < rig::sensors; ++i) {
        select(i);
        uint8_t who = 0;
        bool ok = readRegs(0x75, &who, 1);
        identity[i] = who;
        ok = ok && (who == 0x68 || who == 0x70 || who == 0x72);
        if (ok) ok = writeReg(0x6B, 0x80);
        delay(100);
        if (ok) ok = writeReg(0x6B, 0x01) && writeReg(0x6C, 0x00);
        delay(100);
        if (ok) ok = writeReg(0x23, 0) && writeReg(0x6A, 0) &&
            writeReg(0x19, divider) && writeReg(0x1A, dlpf) && writeReg(0x1C, 0x18) &&
            writeReg(0x37, 0) && writeReg(0x38, 0x10) &&
            verify(0x19, divider) && verify(0x1A, dlpf, 0x07) && verify(0x1C, 0x18, 0xF8);
        Serial.printf("# SENSOR_INIT id=%u who=0x%02X result=%s\r\n", unsigned(i+1), unsigned(who), ok ? "OK" : "FAILED");
        if (ok && who != 0x68)
            Serial.printf("# WARNING S%u has compatible ID; sensitivity/filter/timing are unverified\r\n", unsigned(i+1));
        allOK = allOK && ok;
    }
    ready = allOK;
    park();
    return allOK;
}
bool startFifos() {
    if (!ready || !stopAll()) return false;
    for (size_t i = 0; i < rig::sensors; ++i) {
        select(i);
        if (!writeReg(0x6A, 0x04)) return false;
        delay(1);
        uint8_t ignored;
        if (!readRegs(0x3A, &ignored, 1) || !writeReg(0x6A, 0x40) || !verify(0x6A, 0x40, 0x40)) return false;
        frames[i] = 0;
    }
    // Prepare all FIFOs first, then enable them in one short sweep. This reduces
    // start skew but cannot synchronize five independent sensor clocks.
    const uint64_t firstEnableUs = nowUs();
    for (size_t i = 0; i < rig::sensors; ++i) {
        select(i);
        if (!writeReg(0x23, 0x08)) return false; // six-byte acceleration-only frames
    }
    startedUs = nowUs();
    startSpanUs = uint32_t(startedUs - firstEnableUs);
    for (size_t i = 0; i < rig::sensors; ++i) {
        select(i);
        if (!verify(0x23, 0x08)) return false;
        lastSensorUs[i] = startedUs;
    }
    epochMs = startedUs / 1000;
    if (haveRow && epochMs <= lastRowMs) epochMs = lastRowMs + periodMs;
    segmentRows = 0;
    nextPollUs = nowUs() + pollUs;
    streaming = true;
    printHeader(); Serial.println("# Streaming");
    return true;
}
void validateStill() {
    Serial.printf("# STATIC VALIDATION: keep %u active sensor(s) still until Validation finished.\r\n", unsigned(rig::sensors));
    delay(2000);
    int64_t sums[rig::sensors][3]{};
    double magnitudes[rig::sensors]{};
    unsigned valid[rig::sensors]{};
    for (unsigned n = 0; n < 200; ++n) {
        for (size_t i = 0; i < rig::sensors; ++i) {
            select(i); uint8_t b[6];
            if (!readRegs(0x3B, b, 6)) continue;
            const rig::Sample s{rig::decode(b[0], b[1]), rig::decode(b[2], b[3]), rig::decode(b[4], b[5])};
            sums[i][0] += s.x; sums[i][1] += s.y; sums[i][2] += s.z;
            magnitudes[i] += sqrt(double(s.x)*s.x + double(s.y)*s.y + double(s.z)*s.z) / rig::scale;
            ++valid[i];
        }
        delay(5);
    }
    for (size_t i = 0; i < rig::sensors; ++i) {
        Serial.printf("Sensor %u:\r\n", unsigned(i+1));
        if (valid[i] == 200) {
            Serial.printf("Mean ax [g]: %.4f\r\nMean ay [g]: %.4f\r\nMean az [g]: %.4f\r\nMean |a| [g]: %.4f\r\n",
                double(sums[i][0])/valid[i]/rig::scale, double(sums[i][1])/valid[i]/rig::scale,
                double(sums[i][2])/valid[i]/rig::scale, magnitudes[i]/valid[i]);
        }
        Serial.printf("# VALIDATION id=%u valid=%u/200\r\n", unsigned(i+1), valid[i]);
    }
    Serial.println("Validation finished.");
}
void acquire() {
    if (nowUs() < nextPollUs) return;
    const uint64_t sweepStart = nowUs();
    nextPollUs = sweepStart + pollUs;
    for (size_t i = 0; i < rig::sensors; ++i) {
        select(i);
        uint8_t status, bytes[2];
        if (!readRegs(0x3A, &status, 1) || !readRegs(0x72, bytes, 2)) { fail("i2c_count", i+1); return; }
        const uint16_t count = uint16_t(bytes[0]) << 8 | bytes[1];
        maximumFifo = max(maximumFifo, count);
        if (status & 0x10) { ++fifoOverflows; fail("fifo_overflow", i+1); return; }
        if (count >= maxFifo) { fail("fifo_backlog", i+1); return; }
        unsigned remaining = count / 6;
        if (queues[i].size() + remaining > rig::queueCapacity) { fail("queue_full", i+1); return; }
        if (remaining == 0 && nowUs() - lastSensorUs[i] > noDataUs) { fail("sensor_stalled", i+1); return; }
        while (remaining) {
            const uint8_t batch = remaining > 10 ? 10 : remaining;
            uint8_t b[60];
            if (!readRegs(0x74, b, batch * 6)) { fail("i2c_fifo", i+1); return; }
            for (unsigned n = 0; n < batch; ++n) {
                const uint8_t *p = b + n*6;
                const rig::Sample s{rig::decode(p[0],p[1]), rig::decode(p[2],p[3]), rig::decode(p[4],p[5])};
                if (!queues[i].push(s)) { fail("queue_full", i+1); return; }
                if (abs(int32_t(s.x)) >= 32112 || abs(int32_t(s.y)) >= 32112 || abs(int32_t(s.z)) >= 32112) ++nearLimit;
                ++frames[i];
            }
            remaining -= batch;
            lastSensorUs[i] = nowUs();
        }
    }
    size_t smallest = rig::queueCapacity, largest = 0;
    for (const auto &q : queues) { smallest = min(smallest, q.size()); largest = max(largest, q.size()); }
    maximumQueue = max(maximumQueue, largest);
    maximumSkew = max(maximumSkew, largest - smallest);
    maximumSweepUs = max(maximumSweepUs, uint32_t(nowUs() - sweepStart));
    // Includes sweep latency and clock drift; this is not a phase accuracy bound.
    if (largest - smallest > maxCountSkew) fail("sample_count_skew");
}
void emitRows() {
    // Bounded work; return regularly to the I2C service and command parser.
    for (unsigned budget = 0; streaming && budget < 16; ++budget) {
        if (nowUs() >= nextPollUs) return;
        rig::Sample samples[rig::sensors];
        for (size_t i = 0; i < rig::sensors; ++i) {
            if (!queues[i].size()) return;
            samples[i] = queues[i].front();
        }
        char row[rig::rowCapacity];
        const uint64_t ms = epochMs + segmentRows * periodMs;
        const size_t length = rig::formatRow(row, sizeof(row), ms, samples);
        if (!length) { fail("format_overflow"); return; }
        if (Serial.availableForWrite() < int(length)) return; // never block FIFO draining
        if (Serial.write(reinterpret_cast<const uint8_t *>(row), length) != length) { fail("serial_write"); return; }
        for (auto &q : queues) q.pop();
        lastRowMs = ms; haveRow = true;
        ++totalRows; ++segmentRows;
    }
}
void processCommand() {
    command[commandLength] = '\0';
    if (!strcmp(command, "stats")) stats();
    else if (!strcmp(command, "diag")) { settings(); stats(); }
    else if (!strcmp(command, "pause")) {
        const bool wasStreaming = streaming;
        if (!stopAll()) { fail("pause_failed"); return; }
        if (wasStreaming) marker("STREAM_BREAK", "pause", 0);
        Serial.println("# Paused");
    } else if (!strcmp(command, "start") || !strcmp(command, "resume")) {
        if (streaming) { stopAll(); marker("STREAM_BREAK", "restart_requested", 0); }
        if (!initialize() || !startFifos()) fail("start_failed");
    } else if (!strcmp(command, "validate")) {
        const bool wasStreaming = streaming;
        if (!stopAll() || !ready) { fail("validation_unavailable"); return; }
        if (wasStreaming) marker("STREAM_BREAK", "validation", 0);
        const uint32_t beforeErrors = i2cErrors;
        validateStill();
        if (i2cErrors != beforeErrors) fail("validation_reads");
        else if (wasStreaming && !startFifos()) fail("validation_restart");
    } else if (commandLength) Serial.println("# Unknown command: stats, diag, pause, start, resume, validate");
}
void commands() {
    for (unsigned budget = 0; budget < 64 && Serial.available(); ++budget) {
        const char c = char(Serial.read());
        if (c == '\n' || c == '\r') {
            if (commandOverflow) Serial.println("# Command too long; discarded");
            else if (commandLength) processCommand();
            commandLength = 0; commandOverflow = false;
        } else if (!commandOverflow && commandLength < sizeof(command)-1) command[commandLength++] = c;
        else commandOverflow = true;
    }
}
} // namespace

void setup() {
    // Neither WiFi nor Bluetooth is initialized in this USB-only acquisition.
    Serial.setTxBufferSize(8192);
    Serial.begin(baud);
    Serial.setDebugOutput(false);
    for (int pin : ad0) { digitalWrite(pin, HIGH); pinMode(pin, OUTPUT); }
    delay(200);
    settings();
    if (!Wire.begin(sda, scl, 400000)) { ++faults; Serial.println("# STREAM_FAULT reason=i2c_begin; reboot required"); return; }
    Wire.setTimeOut(3);
    if (!initialize()) { fail("initialization"); return; }
    const uint32_t beforeErrors = i2cErrors;
    validateStill();
    if (i2cErrors != beforeErrors) { fail("validation_reads"); return; }
    if (!startFifos()) fail("startup_fifo");
}
void loop() {
    commands();
    if (streaming) { acquire(); emitRows(); }
    delay(1); // FreeRTOS/USB service; FIFO sampling continues independently
}
