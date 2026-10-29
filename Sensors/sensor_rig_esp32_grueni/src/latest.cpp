// Continuous latest-register polling, as on the older rig; no FIFO pairing.
#include <Arduino.h>
#include <Wire.h>
#include <esp_timer.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <string.h>
#include "rig_data.h"

namespace {
constexpr uint32_t baud = 921600, periodUs = 2000;
// Leave room for UART driver's ring-buffer item headers and alignment as well
// as the payload. Also avoids availableForWrite's 128-byte FIFO fallback when
// the configured TX ring is completely full (even an all-NaN row + 64 > 128).
constexpr size_t uartReserve = 64;
constexpr int sda = 32, scl = 33, ad0[5] = {25, 26, 27, 14, 13};
constexpr uint8_t address = 0x68;
static_assert(rig::sensors == 4 || rig::sensors == 5, "Use a four- or five-sensor latest profile");
esp_timer_handle_t timer = nullptr;
TaskHandle_t acquisitionTask = nullptr;
bool streaming = false, busReady = false, configured[rig::sensors]{};
uint8_t identity[rig::sensors]{};
uint64_t startedUs = 0, stoppedUs = 0, nextDueUs = 0, rows = 0, sweeps = 0;
uint64_t frames[rig::sensors]{}, readErrors[rig::sensors]{};
uint64_t i2cErrors = 0, missedSweeps = 0, uartDroppedRows = 0, formatErrors = 0, nearLimit = 0;
uint32_t maximumSweepUs = 0, maximumCycleUs = 0, maximumLatenessUs = 0;
int selected = -1;
char command[32]{};
size_t commandLength = 0;
bool commandOverflow = false;

uint64_t nowUs() { return uint64_t(esp_timer_get_time()); }
void timerTick(void *) {
    // ESP_TIMER_TASK callback: no Wire, formatting, serial writes, or ISR API.
    xTaskNotifyGive(acquisitionTask);
}
void park() {
    for (int pin : ad0) digitalWrite(pin, HIGH);
    selected = -1;
    delayMicroseconds(20);
}
void select(size_t id) {
    if (selected == int(id)) return;
    if (selected >= 0) digitalWrite(ad0[selected], HIGH);
    digitalWrite(ad0[id], LOW);
    selected = int(id);
    delayMicroseconds(20);
}
bool writeReg(uint8_t reg, uint8_t value) {
    Wire.beginTransmission(address); Wire.write(reg); Wire.write(value);
    if (Wire.endTransmission(true) == 0) return true;
    ++i2cErrors;
    return false;
}
bool readRegs(uint8_t reg, uint8_t *out, uint8_t count) {
    Wire.beginTransmission(address); Wire.write(reg);
    if (Wire.endTransmission(false) != 0 ||
        Wire.requestFrom(address, count, uint8_t(true)) != count) {
        while (Wire.available()) Wire.read();
        ++i2cErrors;
        return false;
    }
    for (uint8_t i = 0; i < count; ++i) out[i] = uint8_t(Wire.read());
    return true;
}
bool verify(uint8_t reg, uint8_t expected, uint8_t mask = 0xFF) {
    uint8_t value = 0;
    return readRegs(reg, &value, 1) && (value & mask) == expected;
}
bool readSample(size_t id, rig::Sample &sample) {
    if (!configured[id]) return false;
    select(id);
    uint8_t b[6];
    if (!readRegs(0x3B, b, sizeof(b))) return false;
    sample = {rig::decode(b[0], b[1]), rig::decode(b[2], b[3]), rig::decode(b[4], b[5])};
    return true;
}
void pause() {
    if (streaming) {
        esp_timer_stop(timer);
        stoppedUs = nowUs();
        streaming = false;
    }
    ulTaskNotifyTake(pdTRUE, 0);
    park();
}
void settings() {
    Serial.printf("# ESP32 GRUENI %u-sensor latest-register rig\r\n", unsigned(rig::sensors));
    Serial.printf("# acquisition=latest sensors=%u sample_rate_hz=500 serial_baud=921600 range_g=16 scale_lsb_per_g=2048\r\n", unsigned(rig::sensors));
    Serial.print("# SDA=G32 SCL=G33 AD0=");
    for (size_t i = 0; i < rig::sensors; ++i)
        Serial.printf("%sS%u:G%d", i ? "," : "", unsigned(i + 1), ad0[i]);
    Serial.println(" I2C=400000 WiFi=off");
    Serial.println("# DLPF=1 nominal_accel_bandwidth_hz=184; verify on compatible IDs");
    Serial.println("# t_ms=actual_sweep_start_ms; sequential latest reads, not synchronized conversions");
    Serial.println("# Read failures emit per-sensor nan and retry next sweep; missed periods are not backfilled");
    Serial.println("# commands: stats, diag, pause, start, resume, validate");
}
void stats() {
    // Snapshot before formatting diagnostics: printing itself can cost time.
    const uint64_t elapsed = startedUs ? (streaming ? nowUs() : stoppedUs) - startedUs : 0;
    const double rate = elapsed ? double(rows) * 1e6 / elapsed : 0;
    Serial.printf("# STATS rows=%llu streaming=%u observed_hz=%.3f i2c_errors=%llu missed_sweeps=%llu uart_dropped_rows=%llu format_errors=%llu near_limit=%llu max_sweep_us=%lu max_cycle_us=%lu max_lateness_us=%lu sweeps=%llu\r\n",
        (unsigned long long)rows, unsigned(streaming), rate, (unsigned long long)i2cErrors,
        (unsigned long long)missedSweeps, (unsigned long long)uartDroppedRows,
        (unsigned long long)formatErrors, (unsigned long long)nearLimit,
        (unsigned long)maximumSweepUs, (unsigned long)maximumCycleUs,
        (unsigned long)maximumLatenessUs, (unsigned long long)sweeps);
    for (size_t i = 0; i < rig::sensors; ++i)
        Serial.printf("# SENSOR id=%u who=0x%02X frames=%llu observed_hz=%.3f read_errors=%llu configured=%u\r\n",
            unsigned(i + 1), unsigned(identity[i]), (unsigned long long)frames[i],
            elapsed ? double(frames[i]) * 1e6 / elapsed : 0,
            (unsigned long long)readErrors[i], unsigned(configured[i]));
}
bool initialize() {
    if (!busReady || !timer) return false;
    park();
    Wire.beginTransmission(address);
    const uint8_t result = Wire.endTransmission(true);
    // Address isolation must work even in the continuous mode. Reading two
    // simultaneously selected sensors could otherwise look like valid data.
    if (result != 2) {
        Serial.printf("# STREAM_FAULT reason=parked_address_check result=%u; check AD0 wiring\r\n", unsigned(result));
        return false;
    }
    for (size_t i = 0; i < rig::sensors; ++i) {
        select(i);
        uint8_t who = 0;
        bool ok = readRegs(0x75, &who, 1);
        identity[i] = who;
        ok = ok && (who == 0x68 || who == 0x70 || who == 0x72);
        if (ok) ok = writeReg(0x6B, 0x80);
        delay(100);
        if (ok) ok = writeReg(0x6B, 0x01) && writeReg(0x6C, 0);
        delay(100);
        // Disable FIFO and interrupts; only burst-read the six acceleration bytes.
        if (ok) ok = writeReg(0x23, 0) && writeReg(0x6A, 0) && writeReg(0x38, 0) &&
            writeReg(0x37, 0) && writeReg(0x19, 1) && writeReg(0x1A, 1) && writeReg(0x1C, 0x18) &&
            verify(0x19, 1) && verify(0x1A, 1, 7) && verify(0x1C, 0x18, 0xF8) &&
            verify(0x23, 0) && verify(0x6A, 0, 0x40);
        configured[i] = ok;
        Serial.printf("# SENSOR_INIT id=%u who=0x%02X result=%s\r\n", unsigned(i + 1), unsigned(who), ok ? "OK" : "FAILED");
        if (!ok) Serial.printf("# WARNING S%u will emit nan; fix wiring and send start to reinitialize\r\n", unsigned(i + 1));
        else if (who != 0x68) Serial.printf("# WARNING S%u compatible ID: scale/filter/timing unverified\r\n", unsigned(i + 1));
    }
    park();
    return true; // An unavailable sensor does not prevent the others streaming.
}
void validateStill() {
    Serial.println("# STATIC VALIDATION: keep sensors still until Validation finished.");
    delay(2000);
    int64_t sums[rig::sensors][3]{};
    double magnitudes[rig::sensors]{};
    unsigned valid[rig::sensors]{};
    for (unsigned n = 0; n < 200; ++n) {
        for (size_t i = 0; i < rig::sensors; ++i) {
            rig::Sample s;
            if (!readSample(i, s)) continue;
            sums[i][0] += s.x; sums[i][1] += s.y; sums[i][2] += s.z;
            magnitudes[i] += sqrt(double(s.x)*s.x + double(s.y)*s.y + double(s.z)*s.z) / rig::scale;
            ++valid[i];
        }
        delay(5);
    }
    for (size_t i = 0; i < rig::sensors; ++i) {
        Serial.printf("Sensor %u:\r\n", unsigned(i + 1));
        if (valid[i] == 200)
            Serial.printf("Mean ax [g]: %.4f\r\nMean ay [g]: %.4f\r\nMean az [g]: %.4f\r\nMean |a| [g]: %.4f\r\n",
                double(sums[i][0])/valid[i]/rig::scale, double(sums[i][1])/valid[i]/rig::scale,
                double(sums[i][2])/valid[i]/rig::scale, magnitudes[i]/valid[i]);
        Serial.printf("# VALIDATION id=%u valid=%u/200\r\n", unsigned(i + 1), valid[i]);
    }
    Serial.println("Validation finished.");
}
void start() {
    // Counters describe this segment; initialization results remain in the log.
    rows = sweeps = i2cErrors = missedSweeps = uartDroppedRows = formatErrors = nearLimit = 0;
    maximumSweepUs = maximumCycleUs = maximumLatenessUs = 0;
    for (size_t i = 0; i < rig::sensors; ++i) frames[i] = readErrors[i] = 0;
    Serial.println("# acquisition=latest");
    Serial.print("t_ms");
    for (unsigned i = 1; i <= rig::sensors; ++i)
        Serial.printf(";S%u_ax_g,S%u_ay_g,S%u_az_g,S%u_mag_g", i, i, i, i);
    Serial.println();
    Serial.println("# Streaming");
    Serial.flush(); // Drain startup diagnostics before starting the acquisition timer.
    ulTaskNotifyTake(pdTRUE, 0);
    startedUs = nowUs();
    nextDueUs = startedUs + periodUs;
    streaming = esp_timer_start_periodic(timer, periodUs) == ESP_OK;
    if (!streaming) {
        stoppedUs = nowUs();
        Serial.println("# STREAM_FAULT reason=timer_start");
    }
}
void acquire(uint64_t sweepStart) {
    const uint64_t late = sweepStart - nextDueUs;
    maximumLatenessUs = max(maximumLatenessUs, uint32_t(min(late, uint64_t(UINT32_MAX))));
    missedSweeps += late / periodUs;
    nextDueUs += (late / periodUs + 1) * periodUs;
    rig::Sample samples[rig::sensors]{};
    bool valid[rig::sensors]{};
    for (size_t i = 0; i < rig::sensors; ++i) {
        valid[i] = readSample(i, samples[i]);
        if (!valid[i]) { ++readErrors[i]; continue; } // retry next sweep; no stale substitution
        ++frames[i];
        const auto &s = samples[i];
        if (abs(int32_t(s.x)) >= 32112 || abs(int32_t(s.y)) >= 32112 || abs(int32_t(s.z)) >= 32112) ++nearLimit;
    }
    ++sweeps;
    maximumSweepUs = max(maximumSweepUs, uint32_t(nowUs() - sweepStart));
    char row[rig::rowCapacity];
    const size_t length = rig::formatRow(row, sizeof(row), sweepStart / 1000, samples, valid);
    if (!length) ++formatErrors;
    else if (Serial.availableForWrite() < int(length + uartReserve)) ++uartDroppedRows;
    else if (Serial.write(reinterpret_cast<const uint8_t *>(row), length) != length) ++uartDroppedRows;
    else ++rows;
    maximumCycleUs = max(maximumCycleUs, uint32_t(nowUs() - sweepStart));
}
void processCommand() {
    command[commandLength] = '\0';
    if (!strcmp(command, "stats")) stats();
    else if (!strcmp(command, "diag")) { settings(); stats(); }
    else if (!strcmp(command, "pause")) {
        const bool wasStreaming = streaming;
        pause();
        if (wasStreaming) Serial.println("# STREAM_BREAK reason=pause");
        Serial.println("# Paused");
    } else if (!strcmp(command, "start") || !strcmp(command, "resume")) {
        if (streaming) Serial.println("# STREAM_BREAK reason=restart_requested");
        pause();
        if (initialize()) start();
        else Serial.println("# STREAM_FAULT reason=start_failed");
    } else if (!strcmp(command, "validate")) {
        const bool wasStreaming = streaming;
        pause();
        if (wasStreaming) Serial.println("# STREAM_BREAK reason=validation");
        validateStill();
        if (wasStreaming) start();
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
    Serial.setTxBufferSize(8192);
    Serial.begin(baud);
    Serial.setDebugOutput(false);
    for (int pin : ad0) { digitalWrite(pin, HIGH); pinMode(pin, OUTPUT); }
    delay(200);
    settings();
    busReady = Wire.begin(sda, scl, 400000);
    Wire.setTimeOut(3);
    acquisitionTask = xTaskGetCurrentTaskHandle();
    esp_timer_create_args_t config{};
    config.callback = timerTick;
    config.dispatch_method = ESP_TIMER_TASK;
    config.name = "rig_poll";
    // Missed callbacks are coalesced; skipped acquisition slots are counted from
    // elapsed time, not from callback count. Never replay historical latest reads.
    config.skip_unhandled_events = true;
    if (!busReady || esp_timer_create(&config, &timer) != ESP_OK) {
        Serial.println("# STREAM_FAULT reason=setup; reboot required");
        return;
    }
    if (initialize()) { validateStill(); start(); }
}
void loop() {
    commands();
    if (!streaming) { delay(1); return; }
    // Block between timer notifications, leaving CPU time for USB/FreeRTOS.
    ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(10));
    const uint64_t current = nowUs();
    if (current >= nextDueUs) acquire(current);
}
