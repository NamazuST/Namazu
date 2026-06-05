/*
 * MPU6050 top-sensor-only lightweight CSV firmware.
 *
 * Active sensor:
 *   AD0 pin 6, reported as S1 in the MATLAB table.
 *
 * MATLAB-compatible live format:
 *   t_ms;S1_ax_g,S1_ay_g,S1_az_g,S1_mag_g
 *
 * The live loop reads only one MPU6050 using a direct 6-byte register burst.
 * It avoids the MPU6050 helper library, avoids live sqrt(), and prints fixed-
 * point acceleration values to reduce serial/CPU overhead.
 */

#include <Wire.h>

/* ================= SETTINGS ================= */

const int NUM_SENS = 1;
const int AD0_PINS[NUM_SENS] = {6};

// If the other four sensors are still connected to the same I2C bus, keep
// their AD0 pins high so they do not share address 0x68 with the top sensor.
const bool PARK_OTHER_AD0_PINS = true;
const int PARKED_AD0_PINS[] = {2, 3, 4, 5};
const int NUM_PARKED_AD0_PINS = sizeof(PARKED_AD0_PINS) / sizeof(PARKED_AD0_PINS[0]);

const uint8_t MPU_ADDR = 0x68;

const unsigned long SERIAL_BAUD = 1000000;
const unsigned long I2C_CLOCK_HZ = 400000;

// 500 Hz gives a 250 Hz Nyquist limit for the one-sensor benchmark.
// If the stream is unstable, try 250. If it is very stable, try 1000.
const unsigned long SAMPLE_RATE_HZ = 500;
const unsigned long SAMPLE_INTERVAL_US = 1000000UL / SAMPLE_RATE_HZ;

// MPU6050 sample rate = 1 kHz / (1 + divider) when DLPF is enabled.
// divider 1 => 500 Hz.
const uint8_t MPU_SAMPLE_RATE_DIVIDER = 1;

// DLPF config 1: accelerometer bandwidth around 184 Hz.
const uint8_t MPU_DLPF_CONFIG = 1;

// +/-4 g => 8192 LSB/g. Fixed-point output prints raw / 8192 as g.
const long ACCEL_SCALE_LSB_PER_G = 8192L;

// Startup validation costs only a moment before live output and lets MATLAB
// create corrected columns. Turn this false for a pure raw-speed benchmark.
const bool RUN_STATIC_VALIDATION = true;
const int VALIDATION_SAMPLES = 150;

/* ============== MPU6050 REGISTERS ============== */

const uint8_t REG_SMPLRT_DIV = 0x19;
const uint8_t REG_CONFIG = 0x1A;
const uint8_t REG_ACCEL_CONFIG = 0x1C;
const uint8_t REG_ACCEL_XOUT_H = 0x3B;
const uint8_t REG_PWR_MGMT_1 = 0x6B;
const uint8_t REG_WHO_AM_I = 0x75;

/* ============== STATE ============== */

bool sensorOK = false;
int16_t axRaw = 0;
int16_t ayRaw = 0;
int16_t azRaw = 0;

unsigned long nextSampleUs = 0;
unsigned long overrunCount = 0;

/* ============== LOW-LEVEL HELPERS ============== */

void selectTopSensor()
{
    if (PARK_OTHER_AD0_PINS) {
        for (int i = 0; i < NUM_PARKED_AD0_PINS; i++) {
            digitalWrite(PARKED_AD0_PINS[i], HIGH);
        }
    }

    digitalWrite(AD0_PINS[0], LOW);
    delayMicroseconds(8);
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

bool readAccelRaw()
{
    if (!sensorOK) {
        return false;
    }

    uint8_t buffer[6];

    if (!readBytes(REG_ACCEL_XOUT_H, 6, buffer)) {
        return false;
    }

    axRaw = (int16_t)((buffer[0] << 8) | buffer[1]);
    ayRaw = (int16_t)((buffer[2] << 8) | buffer[3]);
    azRaw = (int16_t)((buffer[4] << 8) | buffer[5]);

    return true;
}

bool initializeMPU()
{
    selectTopSensor();

    bool ok = true;
    ok = ok && writeByte(REG_PWR_MGMT_1, 0x00);
    delay(50);

    ok = ok && writeByte(REG_CONFIG, MPU_DLPF_CONFIG);
    ok = ok && writeByte(REG_SMPLRT_DIV, MPU_SAMPLE_RATE_DIVIDER);

    // ACCEL_CONFIG bits [4:3] = 01 => +/-4 g.
    ok = ok && writeByte(REG_ACCEL_CONFIG, 0x08);

    uint8_t whoAmI = 0;
    ok = ok && readByte(REG_WHO_AM_I, whoAmI);
    ok = ok && (whoAmI == 0x68 || whoAmI == 0x70);

    return ok;
}

/* ============== PRINTING ============== */

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

void printHeader()
{
    Serial.println("t_ms;S1_ax_g,S1_ay_g,S1_az_g,S1_mag_g");
}

/* ============== STARTUP VALIDATION ============== */

void printMeanG(const char *label, long sumRaw, int n)
{
    Serial.print(label);
    Serial.print(": ");

    long meanRaw = sumRaw / n;
    printFixedG((int16_t)meanRaw);
    Serial.println();
}

void runStaticValidation()
{
    if (!RUN_STATIC_VALIDATION || !sensorOK) {
        return;
    }

    long sumX = 0;
    long sumY = 0;
    long sumZ = 0;
    int validCount = 0;

    Serial.println();
    Serial.println("STATIC VALIDATION");
    Serial.println("Keep the top sensor still.");
    Serial.println("Sensor 1:");

    for (int i = 0; i < VALIDATION_SAMPLES; i++) {
        if (readAccelRaw()) {
            sumX += axRaw;
            sumY += ayRaw;
            sumZ += azRaw;
            validCount++;
        }

        delay(2);
    }

    if (validCount == 0) {
        Serial.println("Validation failed: no valid readings.");
        return;
    }

    printMeanG("Mean ax [g]", sumX, validCount);
    printMeanG("Mean ay [g]", sumY, validCount);
    printMeanG("Mean az [g]", sumZ, validCount);

    float meanX = (sumX / (float)validCount) / (float)ACCEL_SCALE_LSB_PER_G;
    float meanY = (sumY / (float)validCount) / (float)ACCEL_SCALE_LSB_PER_G;
    float meanZ = (sumZ / (float)validCount) / (float)ACCEL_SCALE_LSB_PER_G;
    float meanMag = sqrt(meanX * meanX + meanY * meanY + meanZ * meanZ);

    Serial.print("Mean |a| [g]: ");
    Serial.println(meanMag, 4);
    Serial.println("Validation finished.");
    Serial.println();
}

/* ================= SETUP ================= */

void setup()
{
    Serial.begin(SERIAL_BAUD);

    unsigned long serialStart = millis();
    while (!Serial && millis() - serialStart < 1500) {
        // Avoid blocking forever on boards without native USB.
    }

    pinMode(AD0_PINS[0], OUTPUT);

    if (PARK_OTHER_AD0_PINS) {
        for (int i = 0; i < NUM_PARKED_AD0_PINS; i++) {
            pinMode(PARKED_AD0_PINS[i], OUTPUT);
            digitalWrite(PARKED_AD0_PINS[i], HIGH);
        }
    }

    digitalWrite(AD0_PINS[0], LOW);

    Wire.begin();
    Wire.setClock(I2C_CLOCK_HZ);

#if defined(WIRE_HAS_TIMEOUT)
    Wire.setWireTimeout(3000, true);
#endif

    Serial.println("MPU6050 Top Sensor Lightweight CSV");
    Serial.print("Target sample rate [Hz]: ");
    Serial.println(SAMPLE_RATE_HZ);
    Serial.print("Serial baud: ");
    Serial.println(SERIAL_BAUD);
    Serial.print("Active AD0 pin: ");
    Serial.println(AD0_PINS[0]);

    sensorOK = initializeMPU();

    if (sensorOK) {
        Serial.println("Connection OK");
    } else {
        Serial.println("Connection FAILED");
    }

    runStaticValidation();

    Serial.println("Starting live output...");
    printHeader();

    nextSampleUs = micros() + SAMPLE_INTERVAL_US;
}

/* ================= LOOP ================= */

void loop()
{
    unsigned long nowUs = micros();

    if ((long)(nowUs - nextSampleUs) < 0) {
        return;
    }

    unsigned long sampleUs = nextSampleUs;
    nextSampleUs += SAMPLE_INTERVAL_US;

    if ((long)(nowUs - nextSampleUs) > (long)SAMPLE_INTERVAL_US) {
        nextSampleUs = nowUs + SAMPLE_INTERVAL_US;
        overrunCount++;
    }

    Serial.print(sampleUs / 1000UL);
    Serial.print(';');

    if (readAccelRaw()) {
        printFixedG(axRaw);
        Serial.print(',');
        printFixedG(ayRaw);
        Serial.print(',');
        printFixedG(azRaw);
        Serial.print(',');
        Serial.print("0.0000");
    } else {
        Serial.print("nan,nan,nan,nan");
    }

    Serial.println();
}
