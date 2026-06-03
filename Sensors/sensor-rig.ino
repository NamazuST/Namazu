#include "Wire.h"
#include "I2Cdev.h"
#include "MPU6050.h"

/* ================= SETTINGS ================= */

const int NUM_SENS = 5;
const int AD0_PINS[NUM_SENS] = {2, 3, 4, 5, 6};

MPU6050 MPU[NUM_SENS];
bool sensorOK[NUM_SENS];

const unsigned long SAMPLE_INTERVAL_MS = 10;   // 100 Hz
unsigned long lastSample = 0;

// ±4 g => 8192 LSB/g
const float ACCEL_SCALE_LSB_PER_G = 8192.0f;

/* ============== DATA STORAGE ============== */

int16_t ax_raw[NUM_SENS];
int16_t ay_raw[NUM_SENS];
int16_t az_raw[NUM_SENS];

float ax_g[NUM_SENS];
float ay_g[NUM_SENS];
float az_g[NUM_SENS];
float a_mag_g[NUM_SENS];

/* ============== SENSOR SWITCHING ============== */

void selectMPU(int id)
{
    // Sonderfall: nur 1 Sensor
    if (NUM_SENS == 1) {
        digitalWrite(AD0_PINS[0], LOW);   // Sensor aktiv auf Adresse 0x68
        delayMicroseconds(50);
        return;
    }

    for (int i = 0; i < NUM_SENS; i++) {
        digitalWrite(AD0_PINS[i], HIGH);   // unselected sensors => 0x69
    }

    digitalWrite(AD0_PINS[id], LOW);       // selected sensor => 0x68
    delayMicroseconds(50);
}

/* ============== BASIC READ ============== */

bool readMPUAccel(int id)
{
    if (!sensorOK[id]) {
        return false;
    }

    selectMPU(id);

    MPU[id].getAcceleration(&ax_raw[id], &ay_raw[id], &az_raw[id]);

    ax_g[id] = ax_raw[id] / ACCEL_SCALE_LSB_PER_G;
    ay_g[id] = ay_raw[id] / ACCEL_SCALE_LSB_PER_G;
    az_g[id] = az_raw[id] / ACCEL_SCALE_LSB_PER_G;

    a_mag_g[id] = sqrt(
        ax_g[id] * ax_g[id] +
        ay_g[id] * ay_g[id] +
        az_g[id] * az_g[id]
    );

    return true;
}

/* ============== HEADER PRINTING ============== */

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

/* ============== VALIDATION ============== */

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
        double sum_x = 0.0;
        double sum_y = 0.0;
        double sum_z = 0.0;
        double sum_mag = 0.0;
        int validCount = 0;

        Serial.print("Reading sensor ");
        Serial.print(s + 1);
        Serial.println(" ...");

        for (int k = 0; k < N; k++) {
            if (readMPUAccel(s)) {
                sum_x += ax_g[s];
                sum_y += ay_g[s];
                sum_z += az_g[s];
                sum_mag += a_mag_g[s];
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

        float mean_x = sum_x / validCount;
        float mean_y = sum_y / validCount;
        float mean_z = sum_z / validCount;
        float mean_mag = sum_mag / validCount;

        Serial.print("  Mean ax [g]: ");
        Serial.println(mean_x, 4);

        Serial.print("  Mean ay [g]: ");
        Serial.println(mean_y, 4);

        Serial.print("  Mean az [g]: ");
        Serial.println(mean_z, 4);

        Serial.print("  Mean |a| [g]: ");
        Serial.println(mean_mag, 4);

        if (mean_mag > 0.90f && mean_mag < 1.10f) {
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
    Serial.begin(115200);
    while (!Serial);

    Serial.println("MPU6050 Multi-Sensor Raw Acceleration Test");

    Wire.begin();
    Wire.setClock(100000);   // erstmal robuster zum Debuggen

    // Falls dein Core es unterstützt, kannst du zusätzlich testen:
    // Wire.setWireTimeout(3000, true);

    for (int i = 0; i < NUM_SENS; i++) {
        pinMode(AD0_PINS[i], OUTPUT);
        digitalWrite(AD0_PINS[i], HIGH);
        sensorOK[i] = false;
    }

    delay(100);

    for (int i = 0; i < NUM_SENS; i++) {
        selectMPU(i);

        Serial.print("Initializing IMU ");
        Serial.println(i + 1);

        MPU[i].initialize();

        if (MPU[i].testConnection()) {
            Serial.println("  Connection OK");
            sensorOK[i] = true;
        } else {
            Serial.println("  Connection FAILED");
            sensorOK[i] = false;
            continue;
        }

        MPU[i].setFullScaleAccelRange(MPU6050_ACCEL_FS_4);

        Serial.print("  Accel range code: ");
        Serial.println(MPU[i].getFullScaleAccelRange());

        // optionaler einmaliger Testread direkt nach Init
        if (readMPUAccel(i)) {
            Serial.print("  First read OK: ");
            Serial.print(ax_g[i], 4); Serial.print(", ");
            Serial.print(ay_g[i], 4); Serial.print(", ");
            Serial.print(az_g[i], 4); Serial.print(", ");
            Serial.println(a_mag_g[i], 4);
        } else {
            Serial.println("  First read FAILED");
            sensorOK[i] = false;
        }

        delay(100);
    }

    Serial.println();
    Serial.println("Live output format:");
    printLiveOutputHeader();

    runStaticValidation();

    Serial.println("Starting live output...");
    printLiveOutputHeader();
}

/* ================= LOOP ================= */

void loop()
{
    if (millis() - lastSample < SAMPLE_INTERVAL_MS) {
        return;
    }

    lastSample = millis();

    Serial.print(lastSample);
    Serial.print(";");

    for (int i = 0; i < NUM_SENS; i++) {
        bool ok = readMPUAccel(i);

        if (ok) {
            Serial.print(ax_g[i], 4); Serial.print(",");
            Serial.print(ay_g[i], 4); Serial.print(",");
            Serial.print(az_g[i], 4); Serial.print(",");
            Serial.print(a_mag_g[i], 4);
        } else {
            Serial.print("nan,nan,nan,nan");
        }

        if (i < NUM_SENS - 1) {
            Serial.print(";");
        }
    }

    Serial.println();
}