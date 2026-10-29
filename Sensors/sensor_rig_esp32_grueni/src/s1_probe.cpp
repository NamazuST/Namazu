// Temporary wiring diagnostic for ONE GY-521: SDA G32, SCL G33, AD0 G25.
// Unlike the acquisition firmware, this may READ address 0x69. Do not run with
// multiple sensors attached: they would share that address while parked.
#include <Arduino.h>
#include <Wire.h>

namespace {
constexpr int sda = 32, scl = 33, ad0 = 25;

void lines(const char *stage) {
    Serial.printf("# LINES stage=%s SDA_G32=%d SCL_G33=%d AD0_G25=%d\r\n",
                  stage, digitalRead(sda), digitalRead(scl), digitalRead(ad0));
}

void independentLines() {
    // Open-drain only, as with I2C itself: never drive SDA/SCL high actively.
    digitalWrite(sda, HIGH); digitalWrite(scl, HIGH);
    pinMode(sda, OUTPUT_OPEN_DRAIN | PULLUP);
    pinMode(scl, OUTPUT_OPEN_DRAIN | PULLUP);
    digitalWrite(scl, LOW);
    delayMicroseconds(50);
    const int sdaWithClockLow = digitalRead(sda), sclLow = digitalRead(scl);
    digitalWrite(sda, LOW); // change data while clock is low
    digitalWrite(scl, HIGH);
    delayMicroseconds(50);
    const int sdaLow = digitalRead(sda), sclWithDataLow = digitalRead(scl);
    digitalWrite(sda, HIGH); // STOP; release both lines before printing
    delayMicroseconds(50);
    pinMode(sda, INPUT_PULLUP); pinMode(scl, INPUT_PULLUP);
    Serial.printf("# LINE_TEST pull_SCL_low: SDA=%d SCL=%d (expected 1,0)\r\n", sdaWithClockLow, sclLow);
    Serial.printf("# LINE_TEST pull_SDA_low: SDA=%d SCL=%d (expected 0,1)\r\n", sdaLow, sclWithDataLow);
    if (!sdaWithClockLow && !sclWithDataLow)
        Serial.println("# LINES_COUPLED: SDA and SCL follow each other; inspect for solder bridge/shared copper strip");
}

void probe(uint8_t address) {
    Wire.beginTransmission(address);
    const uint8_t ack = Wire.endTransmission(true);
    Serial.printf("# ADDRESS address=0x%02X result=%u (0=ACK,2=NACK,5=timeout)\r\n",
                  unsigned(address), unsigned(ack));
    if (ack != 0) return;
    Wire.beginTransmission(address);
    Wire.write(0x75); // WHO_AM_I: read only, no configuration changes
    const uint8_t reg = Wire.endTransmission(false);
    if (reg != 0) {
        Serial.printf("# WHO_AM_I register_select_error=%u\r\n", unsigned(reg));
        return;
    }
    const size_t received = Wire.requestFrom(address, uint8_t(1), uint8_t(true));
    if (received == 1) Serial.printf("# WHO_AM_I address=0x%02X value=0x%02X\r\n",
                                    unsigned(address), unsigned(Wire.read()));
    else Serial.printf("# WHO_AM_I read_error received=%u\r\n", unsigned(received));
}

void run() {
    Serial.println("# S1 WIRING PROBE: only ONE sensor connected; baud=921600");
    Serial.println("# VCC=3V3 GND=GND SDA=G32 SCL=G33 AD0=G25; idle SDA/SCL must be 1");
    pinMode(sda, INPUT_PULLUP);
    pinMode(scl, INPUT_PULLUP);
    for (int pin : {25, 26, 27, 14, 13}) { digitalWrite(pin, HIGH); pinMode(pin, OUTPUT); }
    delay(10);
    lines("GPIO_pullups");
    independentLines();
    for (uint32_t frequency : {100000UL, 400000UL}) {
        if (!Wire.begin(sda, scl, frequency)) { Serial.println("# ERROR Wire.begin failed"); return; }
        Wire.setTimeOut(20);
        Serial.printf("# I2C frequency_hz=%lu\r\n", static_cast<unsigned long>(frequency));
        for (int level : {HIGH, LOW}) {
            digitalWrite(ad0, level);
            delay(10);
            lines(level ? "AD0_high_expect_69" : "AD0_low_expect_68");
            if (!digitalRead(sda) || !digitalRead(scl)) {
                Serial.println("# BUS_HELD_LOW: skipping transactions; check wiring, power and solder bridges");
                continue;
            }
            probe(0x68);
            probe(0x69);
        }
        Wire.end();
    }
    digitalWrite(ad0, HIGH);
    Serial.println("# PROBE finished; send any character to repeat. No acceleration data acquired.");
}
}

void setup() {
    Serial.begin(921600);
    Serial.setDebugOutput(false);
    delay(300);
    run();
}

void loop() {
    if (Serial.available()) {
        while (Serial.available()) Serial.read();
        run();
    }
    delay(10);
}
