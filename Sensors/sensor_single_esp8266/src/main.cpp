// Single MPU6050/GY-521 on the photographed ESP8266 NodeMCU-style board.
// Live protocol stays: t_ms;S1_ax_g,S1_ay_g,S1_az_g,S1_mag_g + CR/LF.
#include <Arduino.h>
#include <ESP8266WiFi.h>
#include <Wire.h>
#include <string.h>
#include "sample_format.h"

#ifndef SENSOR_SAMPLE_RATE_HZ
#define SENSOR_SAMPLE_RATE_HZ 1000
#endif

namespace {
constexpr uint32_t SAMPLE_RATE_HZ = SENSOR_SAMPLE_RATE_HZ;
static_assert(SAMPLE_RATE_HZ == 1000 || SAMPLE_RATE_HZ == 500,
              "Use the supported 1000 or 500 Hz build configuration.");
constexpr uint32_t SAMPLE_INTERVAL_US = 1000000UL / SAMPLE_RATE_HZ;
constexpr uint32_t SERIAL_BAUD = 1000000;
constexpr uint32_t I2C_CLOCK_HZ = 400000;
constexpr int SDA_PIN = 4; // NodeMCU D2, not GPIO2
constexpr int SCL_PIN = 5; // NodeMCU D1, not GPIO1
constexpr uint8_t MPU_ADDR = 0x68; // AD0 physically tied to GND
constexpr uint8_t DLPF_CONFIG = 1; // MPU6050: 184 Hz accel bandwidth, 1 kHz base clock
constexpr uint8_t ACCEL_CONFIG = 0x18; // +/-16 g, 2048 LSB/g
constexpr uint8_t SAMPLE_DIVIDER = 1000 / SAMPLE_RATE_HZ - 1;
constexpr uint16_t MAX_BACKLOG_BYTES = 480; // also below 512-byte compatible-part FIFOs
constexpr uint32_t POLL_INTERVAL_US = 2000;
constexpr uint32_t NO_DATA_TIMEOUT_US = 100000;
constexpr uint8_t REG_SAMPLE_DIVIDER = 0x19;
constexpr uint8_t REG_CONFIG = 0x1A;
constexpr uint8_t REG_ACCEL_CONFIG = 0x1C;
constexpr uint8_t REG_FIFO_EN = 0x23;
constexpr uint8_t REG_INT_PIN_CFG = 0x37;
constexpr uint8_t REG_INT_ENABLE = 0x38;
constexpr uint8_t REG_INT_STATUS = 0x3A;
constexpr uint8_t REG_ACCEL_OUT = 0x3B;
constexpr uint8_t REG_USER_CTRL = 0x6A;
constexpr uint8_t REG_PWR_MGMT_1 = 0x6B;
constexpr uint8_t REG_PWR_MGMT_2 = 0x6C;
constexpr uint8_t REG_FIFO_COUNT = 0x72;
constexpr uint8_t REG_FIFO_DATA = 0x74;
constexpr uint8_t REG_WHO_AM_I = 0x75;

bool requestedStreaming = true;
bool streaming = false;
bool sensorReady = false;
uint8_t whoAmI = 0;
uint64_t nextPollUs = 0;
uint64_t retryAtUs = 0;
uint64_t nextSampleUs = 0;
uint64_t lastRowMs = 0;
bool haveRow = false;
bool timestampAnchored = false;
uint64_t lastDataUs = 0;
uint64_t streamStartedUs = 0;
uint32_t segmentSamples = 0;
uint32_t totalSamples = 0;
uint32_t i2cErrors = 0;
uint32_t fifoOverflows = 0;
uint32_t backlogResets = 0;
uint32_t streamFaults = 0;
uint32_t nearLimitSamples = 0;
uint16_t maximumFifoBytes = 0;
char command[32];
size_t commandLength = 0;
bool commandOverflow = false;

// Extend micros() across its roughly 71-minute wrap; called on every loop,
// including while paused. The CSV timestamp therefore never wraps at 71 min.
uint64_t clockUs() {
    static uint32_t previous = 0;
    static uint64_t extended = 0;
    const uint32_t current = micros();
    extended += uint32_t(current - previous);
    previous = current;
    return extended;
}

bool writeByte(uint8_t reg, uint8_t value) {
    Wire.beginTransmission(MPU_ADDR);
    Wire.write(reg);
    Wire.write(value);
    if (Wire.endTransmission(true) == 0) return true;
    ++i2cErrors;
    return false;
}

bool readBytes(uint8_t reg, uint8_t *data, uint8_t count) {
    Wire.beginTransmission(MPU_ADDR);
    Wire.write(reg);
    if (Wire.endTransmission(false) != 0 ||
        Wire.requestFrom(MPU_ADDR, count, uint8_t(true)) != count) {
        while (Wire.available()) Wire.read();
        ++i2cErrors;
        return false;
    }
    for (uint8_t i = 0; i < count; ++i) data[i] = uint8_t(Wire.read());
    return true;
}

bool readByte(uint8_t reg, uint8_t &value) { return readBytes(reg, &value, 1); }

bool verifyByte(uint8_t reg, uint8_t expected, uint8_t mask = 0xFF) {
    uint8_t actual = 0;
    return readByte(reg, actual) && (actual & mask) == expected;
}

void printHeader() {
    Serial.println(F("t_ms;S1_ax_g,S1_ay_g,S1_az_g,S1_mag_g"));
}

void printSettings() {
    Serial.println(F("# NodeMCU ESP8266 single MPU6050 FIFO acceleration rig"));
    Serial.printf("# sensors=1 sample_rate_hz=%lu range_g=16 scale_lsb_per_g=2048\r\n",
                  static_cast<unsigned long>(SAMPLE_RATE_HZ));
    Serial.println(F("# serial_baud=1000000 SDA=D2/GPIO4 SCL=D1/GPIO5 AD0=GND"));
    Serial.println(F("# I2C=400000 Hz DLPF=1 nominal_accel_bandwidth=184 Hz WiFi=off"));
    Serial.println(F("# commands: stats, diag, validate, pause, resume, start"));
}

bool initializeSensor() {
    streaming = false;
    sensorReady = false;
    if (!readByte(REG_WHO_AM_I, whoAmI)) return false;
    // Retain IDs supported by the existing rig. Non-0x68 parts need a measured
    // rate check: identity alone does not prove the same FIFO/filter behavior.
    if (whoAmI != 0x68 && whoAmI != 0x70 && whoAmI != 0x72) {
        Serial.printf("# ERROR unsupported WHO_AM_I=0x%02X\r\n", whoAmI);
        return false;
    }
    if (!writeByte(REG_PWR_MGMT_1, 0x80)) return false;
    delay(100);
    if (!writeByte(REG_PWR_MGMT_1, 0x01) || !writeByte(REG_PWR_MGMT_2, 0x00)) return false;
    delay(100); // let the gyro PLL selected as sensor clock settle
    const bool configured = writeByte(REG_FIFO_EN, 0x00) &&
        writeByte(REG_USER_CTRL, 0x00) && writeByte(REG_CONFIG, DLPF_CONFIG) &&
        writeByte(REG_SAMPLE_DIVIDER, SAMPLE_DIVIDER) &&
        writeByte(REG_ACCEL_CONFIG, ACCEL_CONFIG) &&
        writeByte(REG_INT_PIN_CFG, 0x00) && writeByte(REG_INT_ENABLE, 0x10) &&
        verifyByte(REG_CONFIG, DLPF_CONFIG, 0x07) &&
        verifyByte(REG_SAMPLE_DIVIDER, SAMPLE_DIVIDER) &&
        verifyByte(REG_ACCEL_CONFIG, ACCEL_CONFIG, 0xF8);
    sensorReady = configured;
    if (configured) {
        Serial.printf("# Connection OK WHO_AM_I=0x%02X range/divider/filter readback OK\r\n", whoAmI);
        if (whoAmI != 0x68) Serial.println(F("# Compatible ID: MPU6050 rate/bandwidth must be verified on this module."));
    }
    return configured;
}

bool stopFifo() {
    streaming = false;
    // Attempt both writes even if the first fails.
    const bool disabled = writeByte(REG_FIFO_EN, 0x00);
    const bool stopped = writeByte(REG_USER_CTRL, 0x00);
    return disabled && stopped;
}

bool startFifo() {
    if (!sensorReady || !stopFifo() || !writeByte(REG_USER_CTRL, 0x04)) return false;
    delay(1);
    uint8_t ignored;
    if (!readByte(REG_INT_STATUS, ignored) || !writeByte(REG_USER_CTRL, 0x40) ||
        !writeByte(REG_FIFO_EN, 0x08) || // acceleration only: six bytes per frame
        !verifyByte(REG_USER_CTRL, 0x40, 0x40) || !verifyByte(REG_FIFO_EN, 0x08)) return false;
    streamStartedUs = clockUs();
    lastDataUs = streamStartedUs;
    nextPollUs = streamStartedUs + POLL_INTERVAL_US;
    segmentSamples = 0;
    timestampAnchored = false;
    streaming = true;
    return true;
}

void fault(const char *reason) {
    ++streamFaults;
    stopFifo();
    sensorReady = false;
    const uint64_t now = clockUs();
    uint64_t markerMs = now / 1000;
    if (haveRow && markerMs <= lastRowMs) markerMs = lastRowMs + SAMPLE_INTERVAL_US / 1000;
    // Keep the established invalid-reading structure and expose a discontinuity.
    Serial.printf("%llu;nan,nan,nan,nan\r\n", static_cast<unsigned long long>(markerMs));
    lastRowMs = markerMs;
    haveRow = true;
    Serial.printf("# STREAM_FAULT %s; next stream segment will be re-anchored\r\n", reason);
    retryAtUs = now + 1000000;
}

void acquireFifo() {
    const uint64_t now = clockUs();
    if (now < nextPollUs) return;
    nextPollUs = now + POLL_INTERVAL_US;
    uint8_t status = 0, countBytes[2];
    if (!readByte(REG_INT_STATUS, status) || !readBytes(REG_FIFO_COUNT, countBytes, 2)) {
        fault("i2c_count");
        return;
    }
    const uint16_t count = (uint16_t(countBytes[0]) << 8) | countBytes[1];
    if (count > maximumFifoBytes) maximumFifoBytes = count;
    if (status & 0x10) {
        ++fifoOverflows;
        fault("fifo_overflow");
        return;
    }
    if (count >= MAX_BACKLOG_BYTES) {
        ++backlogResets;
        fault("fifo_backlog");
        return;
    }
    const uint16_t frames = count / 6;
    // A partially written frame is left until the following poll.
    if (frames == 0) {
        if (now - lastDataUs > NO_DATA_TIMEOUT_US) fault("no_sensor_samples");
        return;
    }
    if (!timestampAnchored) {
        const uint64_t readTimeUs = clockUs();
        const uint64_t ageUs = uint64_t(frames - 1) * SAMPLE_INTERVAL_US;
        nextSampleUs = readTimeUs > ageUs ? readTimeUs - ageUs : 0;
        if (haveRow && nextSampleUs / 1000 <= lastRowMs)
            nextSampleUs = (lastRowMs + SAMPLE_INTERVAL_US / 1000) * 1000;
        timestampAnchored = true;
    }
    // Burst reads stay below 32 bytes. Drain the snapshot before the next poll.
    uint16_t remaining = frames;
    while (remaining) {
        const uint8_t batch = remaining > 5 ? 5 : uint8_t(remaining);
        uint8_t bytes[30];
        if (!readBytes(REG_FIFO_DATA, bytes, batch * 6)) {
            // A short FIFO read consumes an unknown number of bytes. Reset;
            // continuing would risk shifting axis/sample boundaries.
            fault("i2c_fifo");
            return;
        }
        for (uint8_t i = 0; i < batch; ++i) {
            const uint8_t *p = bytes + i * 6;
            const int16_t x = sample_format::decodeAxis(p[0], p[1]);
            const int16_t y = sample_format::decodeAxis(p[2], p[3]);
            const int16_t z = sample_format::decodeAxis(p[4], p[5]);
            if (abs(int32_t(x)) >= 32112 || abs(int32_t(y)) >= 32112 || abs(int32_t(z)) >= 32112)
                ++nearLimitSamples; // >=98% of range; possible clipping, not proof
            char row[96];
            const uint64_t timeMs = nextSampleUs / 1000;
            const size_t length = sample_format::formatRow(row, sizeof(row), timeMs, x, y, z);
            if (!length || Serial.write(reinterpret_cast<const uint8_t *>(row), length) != length) {
                fault("serial_write");
                return;
            }
            lastRowMs = timeMs;
            haveRow = true;
            nextSampleUs += SAMPLE_INTERVAL_US;
            ++totalSamples;
            ++segmentSamples;
        }
        remaining -= batch;
        clockUs();
        yield();
    }
    lastDataUs = clockUs();
}

void printStats() {
    const uint64_t elapsed = streaming ? clockUs() - streamStartedUs : 0;
    const double observedRate = elapsed ? double(segmentSamples) * 1000000.0 / double(elapsed) : 0;
    Serial.printf("# STATS samples=%lu i2c_errors=%lu fifo_overflows=%lu backlog_resets=%lu faults=%lu near_limit=%lu max_fifo_bytes=%u observed_hz=%.2f\r\n",
        static_cast<unsigned long>(totalSamples), static_cast<unsigned long>(i2cErrors),
        static_cast<unsigned long>(fifoOverflows), static_cast<unsigned long>(backlogResets),
        static_cast<unsigned long>(streamFaults), static_cast<unsigned long>(nearLimitSamples),
        unsigned(maximumFifoBytes), observedRate);
}

void validateStill() {
    if (!sensorReady) { Serial.println(F("# Validation unavailable: sensor not initialized.")); return; }
    stopFifo();
    Serial.println(F("# STATIC VALIDATION: keep the sensor still for two seconds."));
    delay(2000);
    int64_t sums[3] = {0, 0, 0};
    double magnitudeSum = 0;
    uint16_t valid = 0;
    for (uint16_t i = 0; i < 200; ++i) {
        uint8_t data[6];
        if (readBytes(REG_ACCEL_OUT, data, sizeof(data))) {
            float squared = 0;
            for (uint8_t axis = 0; axis < 3; ++axis) {
                const int16_t raw = sample_format::decodeAxis(data[2 * axis], data[2 * axis + 1]);
                sums[axis] += raw;
                squared += float(raw) * raw;
            }
            magnitudeSum += sqrtf(squared) / sample_format::scaleLsbPerG;
            ++valid;
        }
        delay(5);
    }
    // These exact labels are recognized by the current NAMAZU MATLAB parsers.
    Serial.println(F("Sensor 1:"));
    if (valid) {
        Serial.printf("Mean ax [g]: %.4f\r\n", double(sums[0]) / valid / sample_format::scaleLsbPerG);
        Serial.printf("Mean ay [g]: %.4f\r\n", double(sums[1]) / valid / sample_format::scaleLsbPerG);
        Serial.printf("Mean az [g]: %.4f\r\n", double(sums[2]) / valid / sample_format::scaleLsbPerG);
        Serial.printf("Mean |a| [g]: %.4f\r\n", magnitudeSum / valid);
        Serial.printf("# Validation valid=%u/200; stationary magnitude should be near 1 g.\r\n", unsigned(valid));
    } else Serial.println(F("# Validation failed: no valid readings."));
    Serial.println(F("Validation finished."));
}

void processCommand() {
    command[commandLength] = '\0';
    if (strcmp(command, "stats") == 0 || strcmp(command, "diag") == 0) {
        if (strcmp(command, "diag") == 0) printSettings();
        printStats();
    } else if (strcmp(command, "pause") == 0) {
        requestedStreaming = false;
        stopFifo();
        Serial.println(F("# Paused"));
    } else if (strcmp(command, "start") == 0 || strcmp(command, "resume") == 0) {
        requestedStreaming = true;
        if ((!sensorReady && !initializeSensor()) || !startFifo()) fault("start_failed");
        else { printHeader(); Serial.println(F("# Streaming")); }
    } else if (strcmp(command, "validate") == 0) {
        validateStill();
        if (requestedStreaming && (!sensorReady || !startFifo())) fault("validation_restart");
    } else if (commandLength) Serial.println(F("# Unknown command. Use stats, diag, validate, pause, resume, start."));
}

void pollCommands() {
    for (uint8_t budget = 0; budget < 64 && Serial.available(); ++budget) {
        const char c = char(Serial.read());
        if (c == '\r' || c == '\n') {
            if (commandOverflow) Serial.println(F("# Command too long; discarded."));
            else if (commandLength) processCommand();
            commandLength = 0;
            commandOverflow = false;
        } else if (!commandOverflow && commandLength < sizeof(command) - 1) command[commandLength++] = c;
        else commandOverflow = true;
    }
}
} // namespace

void setup() {
    WiFi.persistent(false);
    WiFi.mode(WIFI_OFF);
    WiFi.forceSleepBegin();
    delay(1);
    Serial.begin(SERIAL_BAUD);
    Serial.setDebugOutput(false);
    Wire.begin(SDA_PIN, SCL_PIN);
    Wire.setClock(I2C_CLOCK_HZ);
    Wire.setClockStretchLimit(1500);
    delay(200);
    printSettings();
    if (initializeSensor()) {
        validateStill();
        printHeader();
        if (!startFifo()) fault("startup_fifo");
    } else fault("startup_sensor");
}

void loop() {
    clockUs();
    pollCommands();
    if (requestedStreaming) {
        if (streaming) acquireFifo();
        else if (clockUs() >= retryAtUs) {
            if (initializeSensor() && startFifo()) {
                Serial.println(F("# Streaming recovered; a new timestamp segment starts."));
            } else {
                retryAtUs = clockUs() + 2000000;
                Serial.println(F("# Sensor unavailable; retrying in two seconds."));
            }
        }
    }
    yield();
}
