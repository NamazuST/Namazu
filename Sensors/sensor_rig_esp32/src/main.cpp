/*
 * ESP32 MPU6050 sensor rig firmware.
 *
 * Output format, compatible with the MATLAB/Python sensor-rig parsers:
 *
 *   t_ms;S1_ax_g,S1_ay_g,S1_az_g,S1_mag_g;S2_ax_g,...
 *
 * Hardware approach:
 *   - all MPU6050 boards share ESP32 SDA/SCL
 *   - every MPU6050 AD0 pin is connected to a separate ESP32 GPIO
 *   - the selected sensor is pulled LOW and read at I2C address 0x68
 *   - all other sensors are parked HIGH at address 0x69
 */

#include <Arduino.h>
#include <Wire.h>
#include <math.h>
#include <string.h>

/* ================= USER SETTINGS ================= */

static constexpr uint8_t MAX_SENSORS = 5;
static constexpr uint8_t NUM_SENSORS = 5;

static_assert(NUM_SENSORS >= 1, "NUM_SENSORS must be at least 1.");
static_assert(NUM_SENSORS <= MAX_SENSORS, "NUM_SENSORS exceeds MAX_SENSORS.");

// Classic ESP32-WROOM defaults. Boards labelled with D names usually map
// D13 -> GPIO13, D14 -> GPIO14, D25 -> GPIO25, etc.
//
// If your board exposes RX2/TX2 but not D13/D14, use this alternative:
//   static constexpr int AD0_PINS[MAX_SENSORS] = {16, 17, 25, 26, 27};
//
// Avoid GPIO6-GPIO11: they are used for flash. Avoid GPIO34-GPIO39 for AD0:
// they are input-only and cannot drive the MPU6050 address pin.
static constexpr int I2C_SDA_PIN = 21;
static constexpr int I2C_SCL_PIN = 22;
static constexpr int AD0_PINS[MAX_SENSORS] = {13, 14, 25, 26, 27};

static constexpr uint32_t SERIAL_BAUD = 1000000;
static constexpr uint32_t I2C_CLOCK_HZ = 400000;
static constexpr uint32_t SAMPLE_RATE_HZ = 250;
static constexpr uint32_t SAMPLE_INTERVAL_US = 1000000UL / SAMPLE_RATE_HZ;

// Increase this to 50-100 us if switching between sensors is unreliable.
static constexpr uint32_t AD0_SETTLE_US = 20;

// Set false after the rig is proven if you want a faster boot.
static constexpr bool RUN_STATIC_VALIDATION = true;

// Prints a short address-selection check before MPU initialization.
static constexpr bool RUN_I2C_DIAGNOSTIC = true;

// Gives you time to copy the startup diagnostic before live data starts.
static constexpr uint32_t STARTUP_LOG_HOLD_MS = 3000;

// Set true while debugging if you want the rig to wait for "start" over serial.
static constexpr bool WAIT_FOR_START_COMMAND = false;

// Set false if serial throughput becomes the limiting factor.
static constexpr bool PRINT_MAGNITUDE = true;

// MPU6050 sample rate = 1 kHz / (1 + divider) when DLPF is enabled.
// 1 kHz / (1 + 3) = 250 Hz.
static constexpr uint8_t MPU_SAMPLE_RATE_DIVIDER = 3;

// DLPF config 1 gives high bandwidth for vibration work while filtering noise.
static constexpr uint8_t MPU_DLPF_CONFIG = 1;

// +/-4 g => 8192 LSB/g.
static constexpr int32_t ACCEL_SCALE_LSB_PER_G = 8192;

/* ============== MPU6050 REGISTERS ============== */

static constexpr uint8_t MPU_ADDR = 0x68;

static constexpr uint8_t REG_SMPLRT_DIV = 0x19;
static constexpr uint8_t REG_CONFIG = 0x1A;
static constexpr uint8_t REG_ACCEL_CONFIG = 0x1C;
static constexpr uint8_t REG_ACCEL_XOUT_H = 0x3B;
static constexpr uint8_t REG_PWR_MGMT_1 = 0x6B;
static constexpr uint8_t REG_WHO_AM_I = 0x75;

/* ============== DATA STORAGE ============== */

static bool sensorOK[MAX_SENSORS] = {false};

static int16_t axRaw[MAX_SENSORS] = {0};
static int16_t ayRaw[MAX_SENSORS] = {0};
static int16_t azRaw[MAX_SENSORS] = {0};

static uint32_t nextSampleUs = 0;
static uint32_t overrunCount = 0;
static bool liveStreamingPaused = false;

static char serialCommand[32] = {0};
static uint8_t serialCommandLength = 0;

/* ============== LOW-LEVEL HELPERS ============== */

static void parkAllSensors()
{
    for (uint8_t i = 0; i < MAX_SENSORS; ++i) {
        digitalWrite(AD0_PINS[i], HIGH);
    }
}

static void selectMPU(uint8_t id)
{
    parkAllSensors();
    digitalWrite(AD0_PINS[id], LOW);
    delayMicroseconds(AD0_SETTLE_US);
}

static bool writeByte(uint8_t reg, uint8_t value)
{
    Wire.beginTransmission(MPU_ADDR);
    Wire.write(reg);
    Wire.write(value);
    return Wire.endTransmission(true) == 0;
}

static bool i2cAddressResponds(uint8_t address)
{
    Wire.beginTransmission(address);
    return Wire.endTransmission(true) == 0;
}

static bool readBytes(uint8_t reg, uint8_t count, uint8_t *buffer)
{
    Wire.beginTransmission(MPU_ADDR);
    Wire.write(reg);

    if (Wire.endTransmission(false) != 0) {
        return false;
    }

    const uint8_t nRead = Wire.requestFrom(MPU_ADDR, count, static_cast<uint8_t>(true));

    if (nRead != count) {
        while (Wire.available()) {
            Wire.read();
        }
        return false;
    }

    for (uint8_t i = 0; i < count; ++i) {
        buffer[i] = Wire.read();
    }

    return true;
}

static bool readByte(uint8_t reg, uint8_t &value)
{
    uint8_t buffer[1] = {0};

    if (!readBytes(reg, 1, buffer)) {
        return false;
    }

    value = buffer[0];
    return true;
}

static bool readByteFromAddress(uint8_t address, uint8_t reg, uint8_t &value)
{
    Wire.beginTransmission(address);
    Wire.write(reg);

    if (Wire.endTransmission(false) != 0) {
        return false;
    }

    if (Wire.requestFrom(address, static_cast<uint8_t>(1), static_cast<uint8_t>(true)) != 1) {
        while (Wire.available()) {
            Wire.read();
        }
        return false;
    }

    value = Wire.read();
    return true;
}

static bool readMPUAccelRaw(uint8_t id)
{
    if (!sensorOK[id]) {
        return false;
    }

    selectMPU(id);

    uint8_t buffer[6] = {0};

    if (!readBytes(REG_ACCEL_XOUT_H, 6, buffer)) {
        return false;
    }

    axRaw[id] = static_cast<int16_t>((buffer[0] << 8) | buffer[1]);
    ayRaw[id] = static_cast<int16_t>((buffer[2] << 8) | buffer[3]);
    azRaw[id] = static_cast<int16_t>((buffer[4] << 8) | buffer[5]);

    return true;
}

static bool initializeMPU(uint8_t id)
{
    selectMPU(id);

    bool ok = true;

    // Reset, then wake using the X gyro PLL clock for a stable sample clock.
    ok = ok && writeByte(REG_PWR_MGMT_1, 0x80);
    delay(100);
    ok = ok && writeByte(REG_PWR_MGMT_1, 0x01);
    delay(20);

    ok = ok && writeByte(REG_CONFIG, MPU_DLPF_CONFIG);
    ok = ok && writeByte(REG_SMPLRT_DIV, MPU_SAMPLE_RATE_DIVIDER);

    // ACCEL_CONFIG bits [4:3] = 01 => +/-4 g.
    ok = ok && writeByte(REG_ACCEL_CONFIG, 0x08);

    uint8_t whoAmI = 0;
    ok = ok && readByte(REG_WHO_AM_I, whoAmI);

    // Most MPU6050 boards return 0x68. Common compatible modules have also
    // been seen returning 0x70 or 0x72 while using the same accel registers.
    ok = ok && (whoAmI == 0x68 || whoAmI == 0x70 || whoAmI == 0x72);

    return ok;
}

/* ============== PRINTING ============== */

static void printFixedG(int16_t raw)
{
    int32_t value = raw;

    if (value < 0) {
        Serial.print('-');
        value = -value;
    }

    const uint32_t scaled =
        (static_cast<uint32_t>(value) * 10000UL + (ACCEL_SCALE_LSB_PER_G / 2)) /
        ACCEL_SCALE_LSB_PER_G;
    const uint32_t whole = scaled / 10000UL;
    const uint16_t frac = scaled % 10000UL;

    Serial.print(whole);
    Serial.print('.');

    if (frac < 1000) Serial.print('0');
    if (frac < 100) Serial.print('0');
    if (frac < 10) Serial.print('0');

    Serial.print(frac);
}

static void printMagnitudeG(uint8_t id)
{
    if (!PRINT_MAGNITUDE) {
        Serial.print("0.0000");
        return;
    }

    const float ax = static_cast<float>(axRaw[id]) / static_cast<float>(ACCEL_SCALE_LSB_PER_G);
    const float ay = static_cast<float>(ayRaw[id]) / static_cast<float>(ACCEL_SCALE_LSB_PER_G);
    const float az = static_cast<float>(azRaw[id]) / static_cast<float>(ACCEL_SCALE_LSB_PER_G);

    Serial.print(sqrtf(ax * ax + ay * ay + az * az), 4);
}

static void printLiveOutputHeader()
{
    Serial.print("t_ms;");

    for (uint8_t i = 0; i < NUM_SENSORS; ++i) {
        Serial.print("S");
        Serial.print(i + 1);
        Serial.print("_ax_g,S");
        Serial.print(i + 1);
        Serial.print("_ay_g,S");
        Serial.print(i + 1);
        Serial.print("_az_g,S");
        Serial.print(i + 1);
        Serial.print("_mag_g");

        if (i < NUM_SENSORS - 1) {
            Serial.print(";");
        }
    }

    Serial.println();
}

static void printSettings()
{
    Serial.println("ESP32 MPU6050 Multi-Sensor CSV Acceleration Rig");
    Serial.print("Sensors: ");
    Serial.println(NUM_SENSORS);
    Serial.print("Target sample rate [Hz]: ");
    Serial.println(SAMPLE_RATE_HZ);
    Serial.print("Serial baud: ");
    Serial.println(SERIAL_BAUD);
    Serial.print("I2C SDA/SCL pins: ");
    Serial.print(I2C_SDA_PIN);
    Serial.print("/");
    Serial.println(I2C_SCL_PIN);
    Serial.print("I2C clock [Hz]: ");
    Serial.println(I2C_CLOCK_HZ);
    Serial.print("AD0 pins: ");

    for (uint8_t i = 0; i < NUM_SENSORS; ++i) {
        Serial.print(AD0_PINS[i]);

        if (i < NUM_SENSORS - 1) {
            Serial.print(", ");
        }
    }

    Serial.println();
}

static void printAddressStatus()
{
    uint8_t who68 = 0;
    uint8_t who69 = 0;
    const bool found68 = i2cAddressResponds(0x68);
    const bool found69 = i2cAddressResponds(0x69);
    const bool gotWho68 = found68 && readByteFromAddress(0x68, REG_WHO_AM_I, who68);
    const bool gotWho69 = found69 && readByteFromAddress(0x69, REG_WHO_AM_I, who69);

    Serial.print("0x68=");
    Serial.print(found68 ? "ACK" : "--");
    if (gotWho68) {
        Serial.print("(WHO=0x");
        if (who68 < 0x10) Serial.print('0');
        Serial.print(who68, HEX);
        Serial.print(")");
    }
    Serial.print(", 0x69=");
    Serial.print(found69 ? "ACK" : "--");
    if (gotWho69) {
        Serial.print("(WHO=0x");
        if (who69 < 0x10) Serial.print('0');
        Serial.print(who69, HEX);
        Serial.print(")");
    }
    Serial.println();
}

static void runI2CDiagnostic()
{
    uint8_t selectedCount = 0;

    Serial.println();
    Serial.println("==============================================");
    Serial.println("I2C / AD0 DIAGNOSTIC");
    Serial.println("Expected with all sensors wired:");
    Serial.println("  parked high: 0x68=--, 0x69=ACK");
    Serial.println("  selected S#: 0x68=ACK");
    Serial.println("If parked high still shows 0x68=ACK, at least one AD0");
    Serial.println("line is not wired, is shorted to GND, or cannot be driven.");
    Serial.println("==============================================");

    parkAllSensors();
    delay(5);
    Serial.print("All AD0 high / parked: ");
    printAddressStatus();

    for (uint8_t i = 0; i < NUM_SENSORS; ++i) {
        selectMPU(i);
        Serial.print("Selected sensor ");
        Serial.print(i + 1);
        Serial.print(" on AD0 GPIO ");
        Serial.print(AD0_PINS[i]);
        Serial.print(": ");
        printAddressStatus();

        if (i2cAddressResponds(0x68)) {
            ++selectedCount;
        }

    }

    parkAllSensors();

    if (NUM_SENSORS > 1 && selectedCount > 0 && selectedCount < NUM_SENSORS) {
        Serial.println();
        Serial.print("Hint: only ");
        Serial.print(selectedCount);
        Serial.print(" of ");
        Serial.print(NUM_SENSORS);
        Serial.println(" configured AD0 lines selected an MPU6050.");
        Serial.println("If you expect more sensors, check VCC/GND/SDA/SCL and");
        Serial.println("AD0 wiring for the sensors that never become 0x68.");
    }

    if (selectedCount == 0) {
        Serial.println();
        Serial.println("Hint: no sensor became address 0x68. Check AD0 wiring and");
        Serial.println("whether the configured AD0 GPIO numbers match board labels.");
    }

    Serial.println("Diagnostic finished.");
    Serial.println();
}

static void holdStartupLog()
{
    if (STARTUP_LOG_HOLD_MS == 0) {
        return;
    }

    Serial.print("Holding startup log for ");
    Serial.print(STARTUP_LOG_HOLD_MS / 1000.0f, 1);
    Serial.println(" seconds before live output...");
    Serial.println("Serial commands during live output: diag, pause, resume, start");
    Serial.flush();
    delay(STARTUP_LOG_HOLD_MS);
}

static void processSerialCommand(const char *command)
{
    if (strcmp(command, "diag") == 0) {
        const bool wasPaused = liveStreamingPaused;
        liveStreamingPaused = true;
        runI2CDiagnostic();
        liveStreamingPaused = wasPaused;
        nextSampleUs = micros() + SAMPLE_INTERVAL_US;
    } else if (strcmp(command, "pause") == 0) {
        liveStreamingPaused = true;
        Serial.println("Live output paused. Send 'resume' or 'start' to continue.");
    } else if (strcmp(command, "resume") == 0 || strcmp(command, "start") == 0) {
        liveStreamingPaused = false;
        nextSampleUs = micros() + SAMPLE_INTERVAL_US;
        Serial.println("Live output resumed.");
        printLiveOutputHeader();
    } else if (command[0] != '\0') {
        Serial.print("Unknown command: ");
        Serial.println(command);
        Serial.println("Available commands: diag, pause, resume, start");
    }
}

static void pollSerialCommands()
{
    while (Serial.available() > 0) {
        const char c = static_cast<char>(Serial.read());

        if (c == '\r' || c == '\n') {
            serialCommand[serialCommandLength] = '\0';
            processSerialCommand(serialCommand);
            serialCommandLength = 0;
            serialCommand[0] = '\0';
            continue;
        }

        if (serialCommandLength < sizeof(serialCommand) - 1) {
            serialCommand[serialCommandLength++] = c;
        }
    }
}

static void waitForStartCommand()
{
    if (!WAIT_FOR_START_COMMAND) {
        return;
    }

    liveStreamingPaused = true;
    Serial.println("Waiting for serial command 'start' before live output...");

    while (liveStreamingPaused) {
        pollSerialCommands();
        delay(10);
    }
}

/* ============== VALIDATION ============== */

static void runStaticValidation()
{
    static constexpr uint16_t N = 200;

    Serial.println();
    Serial.println("==============================================");
    Serial.println("STATIC VALIDATION");
    Serial.println("Keep the full sensor rig completely still.");
    Serial.println("Expected: |a| close to 1.0 g for each sensor.");
    Serial.println("==============================================");

    delay(2000);

    for (uint8_t s = 0; s < NUM_SENSORS; ++s) {
        int64_t sumX = 0;
        int64_t sumY = 0;
        int64_t sumZ = 0;
        uint16_t validCount = 0;

        Serial.print("Reading sensor ");
        Serial.print(s + 1);
        Serial.println(" ...");

        for (uint16_t k = 0; k < N; ++k) {
            if (readMPUAccelRaw(s)) {
                sumX += axRaw[s];
                sumY += ayRaw[s];
                sumZ += azRaw[s];
                ++validCount;
            } else {
                Serial.println("  Read failed.");
            }

            delay(5);
        }

        Serial.print("Sensor ");
        Serial.print(s + 1);
        Serial.println(":");

        if (validCount == 0) {
            Serial.println("  Validation failed: no valid readings.");
            Serial.println();
            continue;
        }

        const float meanX =
            (static_cast<float>(sumX) / static_cast<float>(validCount)) /
            static_cast<float>(ACCEL_SCALE_LSB_PER_G);
        const float meanY =
            (static_cast<float>(sumY) / static_cast<float>(validCount)) /
            static_cast<float>(ACCEL_SCALE_LSB_PER_G);
        const float meanZ =
            (static_cast<float>(sumZ) / static_cast<float>(validCount)) /
            static_cast<float>(ACCEL_SCALE_LSB_PER_G);
        const float meanMag = sqrtf(meanX * meanX + meanY * meanY + meanZ * meanZ);

        Serial.print("  Mean ax [g]: ");
        Serial.println(meanX, 4);
        Serial.print("  Mean ay [g]: ");
        Serial.println(meanY, 4);
        Serial.print("  Mean az [g]: ");
        Serial.println(meanZ, 4);
        Serial.print("  Mean |a| [g]: ");
        Serial.println(meanMag, 4);

        if (meanMag > 0.90f && meanMag < 1.10f) {
            Serial.println("  Result: OK  (magnitude close to 1 g)");
        } else {
            Serial.println("  Result: Warning, CHECK  (magnitude not close to 1 g)");
        }

        Serial.println();
    }

    Serial.println("Validation finished.");
    Serial.println();
}

/* ================= ARDUINO ENTRY POINTS ================= */

void setup()
{
    Serial.begin(SERIAL_BAUD);

    const uint32_t serialStartMs = millis();
    while (!Serial && millis() - serialStartMs < 3000) {
        delay(10);
    }

    for (uint8_t i = 0; i < MAX_SENSORS; ++i) {
        pinMode(AD0_PINS[i], OUTPUT);
        digitalWrite(AD0_PINS[i], HIGH);
    }

    Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
    Wire.setClock(I2C_CLOCK_HZ);

#if defined(ESP32)
    Wire.setTimeOut(3);
#elif defined(WIRE_HAS_TIMEOUT)
    Wire.setWireTimeout(3000, true);
#endif

    delay(100);

    printSettings();

    if (RUN_I2C_DIAGNOSTIC) {
        runI2CDiagnostic();
    }

    for (uint8_t i = 0; i < NUM_SENSORS; ++i) {
        sensorOK[i] = false;

        Serial.print("Initializing IMU ");
        Serial.println(i + 1);

        if (initializeMPU(i)) {
            sensorOK[i] = true;
            Serial.println("  Connection OK");
        } else {
            Serial.println("  Connection FAILED");
            continue;
        }

        if (readMPUAccelRaw(i)) {
            Serial.print("  First read OK: ");
            printFixedG(axRaw[i]);
            Serial.print(", ");
            printFixedG(ayRaw[i]);
            Serial.print(", ");
            printFixedG(azRaw[i]);
            Serial.print(", ");
            printMagnitudeG(i);
            Serial.println();
        } else {
            Serial.println("  First read FAILED");
            sensorOK[i] = false;
        }

        delay(20);
    }

    Serial.println();
    Serial.println("Live output format:");
    printLiveOutputHeader();

    if (RUN_STATIC_VALIDATION) {
        runStaticValidation();
    }

    holdStartupLog();
    waitForStartCommand();

    Serial.println("Starting live output...");
    printLiveOutputHeader();

    nextSampleUs = micros() + SAMPLE_INTERVAL_US;
}

void loop()
{
    pollSerialCommands();

    if (liveStreamingPaused) {
        delay(10);
        return;
    }

    const uint32_t nowUs = micros();

    if (static_cast<int32_t>(nowUs - nextSampleUs) < 0) {
        return;
    }

    const uint32_t sampleUs = nowUs;
    nextSampleUs += SAMPLE_INTERVAL_US;

    if (static_cast<int32_t>(nowUs - nextSampleUs) > static_cast<int32_t>(SAMPLE_INTERVAL_US)) {
        nextSampleUs = nowUs + SAMPLE_INTERVAL_US;
        ++overrunCount;
    }

    Serial.print(sampleUs / 1000UL);
    Serial.print(";");

    for (uint8_t i = 0; i < NUM_SENSORS; ++i) {
        const bool ok = readMPUAccelRaw(i);

        if (ok) {
            printFixedG(axRaw[i]);
            Serial.print(",");
            printFixedG(ayRaw[i]);
            Serial.print(",");
            printFixedG(azRaw[i]);
            Serial.print(",");
            printMagnitudeG(i);
        } else {
            Serial.print("nan,nan,nan,nan");
        }

        if (i < NUM_SENSORS - 1) {
            Serial.print(";");
        }
    }

    Serial.println();
}
