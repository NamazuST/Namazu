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

/* ================= USER SETTINGS ================= */

static constexpr uint8_t MAX_SENSORS = 5;
static constexpr uint8_t NUM_SENSORS = 5;

static_assert(NUM_SENSORS >= 1, "NUM_SENSORS must be at least 1.");
static_assert(NUM_SENSORS <= MAX_SENSORS, "NUM_SENSORS exceeds MAX_SENSORS.");

// Classic ESP32-WROOM defaults. Avoid GPIO6-GPIO11: they are used for flash.
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

    // Most MPU6050 boards return 0x68. Some compatible chips return 0x70.
    ok = ok && (whoAmI == 0x68 || whoAmI == 0x70);

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

    Serial.println("Starting live output...");
    printLiveOutputHeader();

    nextSampleUs = micros() + SAMPLE_INTERVAL_US;
}

void loop()
{
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
