/*
 * MPU6050 5-sensor rig, faster CSV-compatible firmware.
 *
 * This sketch keeps the MATLAB serial format compatible with the existing
 * parser:
 *
 *   t_ms;S1_ax_g,S1_ay_g,S1_az_g,S1_mag_g;S2_ax_g,...
 *
 * Changes compared with the original sensor-rig sketch:
 *   - direct MPU6050 register access instead of library getAcceleration()
 *   - no live sqrt() magnitude calculation
 *   - fixed-point integer printing instead of Serial.print(float, 4)
 *   - shorter sensor address settle delay
 *
 * The live S#_mag_g value is printed as 0.0000 for compatibility. MATLAB
 * recomputes corrected magnitude from ax/ay/az anyway.
 */

#include <Wire.h>

/* ================= SETTINGS ================= */

const int NUM_SENS = 5;
const int AD0_PINS[NUM_SENS] = {2,3,4,5,6};

const uint8_t MPU_ADDR = 0x68;

const unsigned long SERIAL_BAUD = 1000000;
const unsigned long I2C_CLOCK_HZ = 400000;
const unsigned long SAMPLE_RATE_HZ = 250;
const unsigned long SAMPLE_INTERVAL_US = 1000000UL / SAMPLE_RATE_HZ;

// If switching between sensors becomes unreliable, increase this to 20-50 us.
const unsigned int AD0_SETTLE_US = 8;

// MPU6050 sample rate = 1 kHz / (1 + divider) when DLPF is enabled.
// 1 kHz / (1 + 3) = 250 Hz.
const uint8_t MPU_SAMPLE_RATE_DIVIDER = 3;

// DLPF config 1: accelerometer bandwidth around 184 Hz.
const uint8_t MPU_DLPF_CONFIG = 1;

// +/-4 g => 8192 LSB/g. Fixed-point output prints raw / 8192 as g.
const long ACCEL_SCALE_LSB_PER_G = 8192L;

/* ============== MPU6050 REGISTERS ============== */

const uint8_t REG_SMPLRT_DIV = 0x19;
const uint8_t REG_CONFIG = 0x1A;
const uint8_t REG_ACCEL_CONFIG = 0x1C;
const uint8_t REG_ACCEL_XOUT_H = 0x3B;
const uint8_t REG_PWR_MGMT_1 = 0x6B;
const uint8_t REG_WHO_AM_I = 0x75;

/* ============== DATA STORAGE ============== */

bool sensorOK[NUM_SENS];

int16_t ax_raw[NUM_SENS];
int16_t ay_raw[NUM_SENS];
int16_t az_raw[NUM_SENS];

unsigned long nextSampleUs = 0;
unsigned long overrunCount = 0;

/* ============== LOW-LEVEL I2C HELPERS ============== */

void selectMPU(int id)
{
    if (NUM_SENS == 1) {
        digitalWrite(AD0_PINS[0], LOW);
        delayMicroseconds(AD0_SETTLE_US);
        return;
    }

    for (int i = 0; i < NUM_SENS; i++) {
        digitalWrite(AD0_PINS[i], HIGH);
    }

    digitalWrite(AD0_PINS[id], LOW);
    delayMicroseconds(AD0_SETTLE_US);
}

bool writeByte(uint8_t reg, uint8_t value)
{
    Wire.beginTransmission(MPU_ADDR);
    Wire.write(reg);
    Wire.write(value);
    return Wire.endTransmission(true) == 0;
}

bool readBytes(uint8_t reg, uint8_t count, uint8_t *buffer)
{
    Wire.beginTransmission(MPU_ADDR);
    Wire.write(reg);

    if (Wire.endTransmission(false) != 0) {
        return false;
    }

    uint8_t nRead = Wire.requestFrom(MPU_ADDR, count, (uint8_t)true);

    if (nRead != count) {
        return false;
    }

    for (uint8_t i = 0; i < count; i++) {
        buffer[i] = Wire.read();
    }

    return true;
}

bool readByte(uint8_t reg, uint8_t &value)
{
    uint8_t buffer[1];

    if (!readBytes(reg, 1, buffer)) {
        return false;
    }

    value = buffer[0];
    return true;
}

bool readMPUAccelRaw(int id)
{
    if (!sensorOK[id]) {
        return false;
    }

    selectMPU(id);

    uint8_t buffer[6];

    if (!readBytes(REG_ACCEL_XOUT_H, 6, buffer)) {
        return false;
    }

    ax_raw[id] = (int16_t)((buffer[0] << 8) | buffer[1]);
    ay_raw[id] = (int16_t)((buffer[2] << 8) | buffer[3]);
    az_raw[id] = (int16_t)((buffer[4] << 8) | buffer[5]);

    return true;
}

bool initializeMPU(int id)
{
    selectMPU(id);

    bool ok = true;

    ok = ok && writeByte(REG_PWR_MGMT_1, 0x00);
    delay(50);
    ok = ok && writeByte(REG_CONFIG, MPU_DLPF_CONFIG);
    ok = ok && writeByte(REG_SMPLRT_DIV, MPU_SAMPLE_RATE_DIVIDER);

    // ACCEL_CONFIG bits [4:3] = 01 => +/-4 g
    ok = ok && writeByte(REG_ACCEL_CONFIG, 0x08);

    uint8_t whoAmI = 0;
    ok = ok && readByte(REG_WHO_AM_I, whoAmI);

    // Most MPU6050 boards return 0x68. Some compatible chips return 0x70.
    ok = ok && (whoAmI == 0x68 || whoAmI == 0x70);

    return ok;
}

/* ============== FAST FIXED-POINT PRINTING ============== */

void printFixedG(int16_t raw)
{
    long value = raw;

    if (value < 0) {
        Serial.print('-');
        value = -value;
    }

    unsigned long scaled = ((unsigned long)value * 10000UL) / ACCEL_SCALE_LSB_PER_G;
    unsigned long whole = scaled / 10000UL;
    unsigned int frac = scaled % 10000UL;

    Serial.print(whole);
    Serial.print('.');

    if (frac < 1000) Serial.print('0');
    if (frac < 100) Serial.print('0');
    if (frac < 10) Serial.print('0');

    Serial.print(frac);
}

/* ============== HEADER AND VALIDATION ============== */

void printLiveOutputHeader()
{
    Serial.print("t_ms;");

    for (int i = 0; i < NUM_SENS; i++) {
        Serial.print("S");
        Serial.print(i + 1);
        Serial.print("_ax_g,S");
        Serial.print(i + 1);
        Serial.print("_ay_g,S");
        Serial.print(i + 1);
        Serial.print("_az_g,S");
        Serial.print(i + 1);
        Serial.print("_mag_g");

        if (i < NUM_SENS - 1) {
            Serial.print(";");
        }
    }

    Serial.println();
}

void runStaticValidation()
{
    const int N = 200;

    Serial.println();
    Serial.println("==============================================");
    Serial.println("STATIC VALIDATION");
    Serial.println("Keep the full sensor rig completely still.");
    Serial.println("Expected: |a| close to 1.0 g for each sensor.");
    Serial.println("==============================================");

    delay(2000);

    for (int s = 0; s < NUM_SENS; s++) {
        long sumX = 0;
        long sumY = 0;
        long sumZ = 0;
        int validCount = 0;

        Serial.print("Reading sensor ");
        Serial.print(s + 1);
        Serial.println(" ...");

        for (int k = 0; k < N; k++) {
            if (readMPUAccelRaw(s)) {
                sumX += ax_raw[s];
                sumY += ay_raw[s];
                sumZ += az_raw[s];
                validCount++;
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

        float meanX = (sumX / (float)validCount) / (float)ACCEL_SCALE_LSB_PER_G;
        float meanY = (sumY / (float)validCount) / (float)ACCEL_SCALE_LSB_PER_G;
        float meanZ = (sumZ / (float)validCount) / (float)ACCEL_SCALE_LSB_PER_G;
        float meanMag = sqrt(meanX*meanX + meanY*meanY + meanZ*meanZ);

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

/* ================= SETUP ================= */

void setup()
{
    Serial.begin(SERIAL_BAUD);

    unsigned long serialStart = millis();
    while (!Serial && millis() - serialStart < 3000) {
        // Wait briefly for native-USB boards, but do not block forever.
    }

    Wire.begin();
    Wire.setClock(I2C_CLOCK_HZ);

#if defined(WIRE_HAS_TIMEOUT)
    Wire.setWireTimeout(3000, true);
#endif

    for (int i = 0; i < NUM_SENS; i++) {
        pinMode(AD0_PINS[i], OUTPUT);
        digitalWrite(AD0_PINS[i], HIGH);
        sensorOK[i] = false;
    }

    delay(100);

    Serial.println("MPU6050 Multi-Sensor Fast CSV Acceleration Test");
    Serial.print("Target sample rate [Hz]: ");
    Serial.println(SAMPLE_RATE_HZ);
    Serial.print("Serial baud: ");
    Serial.println(SERIAL_BAUD);
    Serial.print("I2C clock [Hz]: ");
    Serial.println(I2C_CLOCK_HZ);

    for (int i = 0; i < NUM_SENS; i++) {
        Serial.print("Initializing IMU ");
        Serial.println(i + 1);

        if (initializeMPU(i)) {
            sensorOK[i] = true;
            Serial.println("  Connection OK");
        } else {
            sensorOK[i] = false;
            Serial.println("  Connection FAILED");
            continue;
        }

        if (readMPUAccelRaw(i)) {
            Serial.print("  First read OK: ");
            printFixedG(ax_raw[i]); Serial.print(", ");
            printFixedG(ay_raw[i]); Serial.print(", ");
            printFixedG(az_raw[i]); Serial.println();
        } else {
            Serial.println("  First read FAILED");
            sensorOK[i] = false;
        }

        delay(20);
    }

    Serial.println();
    Serial.println("Live output format:");
    printLiveOutputHeader();

    runStaticValidation();

    Serial.println("Starting live output...");
    printLiveOutputHeader();

    nextSampleUs = micros() + SAMPLE_INTERVAL_US;
}

/* ================= LOOP ================= */

void loop()
{
    unsigned long nowUs = micros();

    if ((long)(nowUs - nextSampleUs) < 0) {
        return;
    }

    unsigned long sampleUs = nowUs;
    nextSampleUs += SAMPLE_INTERVAL_US;

    if ((long)(nowUs - nextSampleUs) > (long)SAMPLE_INTERVAL_US) {
        nextSampleUs = nowUs + SAMPLE_INTERVAL_US;
        overrunCount++;
    }

    Serial.print(sampleUs / 1000UL);
    Serial.print(";");

    for (int i = 0; i < NUM_SENS; i++) {
        bool ok = readMPUAccelRaw(i);

        if (ok) {
            printFixedG(ax_raw[i]); Serial.print(",");
            printFixedG(ay_raw[i]); Serial.print(",");
            printFixedG(az_raw[i]); Serial.print(",");

            // Compatibility placeholder. MATLAB recomputes corrected mag.
            Serial.print("0.0000");
        } else {
            Serial.print("nan,nan,nan,nan");
        }

        if (i < NUM_SENS - 1) {
            Serial.print(";");
        }
    }

    Serial.println();
}
