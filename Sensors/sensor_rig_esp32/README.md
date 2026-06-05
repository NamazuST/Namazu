# ESP32 MPU6050 sensor rig firmware

This firmware runs the acceleration sensor rig on a classic ESP32 dev board.
It uses the same serial row format that the MATLAB sensor-rig functions expect:

```text
t_ms;S1_ax_g,S1_ay_g,S1_az_g,S1_mag_g;S2_ax_g,...
```

## Default wiring

Use a 3.3 V ESP32 board. The MPU6050 I2C pins must not be pulled up to 5 V.

| ESP32 pin | Sensor rig connection |
| --- | --- |
| 3V3 | all MPU6050 VCC pins |
| GND | all MPU6050 GND pins |
| GPIO21 | all MPU6050 SDA pins |
| GPIO22 | all MPU6050 SCL pins |
| GPIO13 | sensor 1 AD0 |
| GPIO14 | sensor 2 AD0 |
| GPIO25 | sensor 3 AD0 |
| GPIO26 | sensor 4 AD0 |
| GPIO27 | sensor 5 AD0 |

Leave MPU6050 `INT` unconnected.

The firmware selects one MPU6050 at a time by pulling its `AD0` pin low
so it appears at I2C address `0x68`. All other sensors are parked high at
address `0x69`, which avoids address conflicts while the ESP32 reads `0x68`.

Do not use ESP32 GPIO6-GPIO11 for `AD0`; those pins are normally connected
to the ESP32 flash chip.

## Step by step

1. Disconnect the shaking-table motor driver power before wiring.
2. Connect all sensor `VCC`, `GND`, `SDA`, and `SCL` lines as shown above.
3. Connect each sensor `AD0` pad to its own ESP32 GPIO.
4. Keep the I2C wires short. If you use five GY-521 style boards, they may
   each have pull-up resistors fitted. If I2C is unstable, remove pull-ups
   from all but one or two boards, or lower `I2C_CLOCK_HZ` in the firmware
   from `400000` to `100000`.
5. Open this `Sensors/sensor_rig_esp32` folder in VS Code with PlatformIO.
6. Connect the ESP32 by USB and run PlatformIO `Build`.
7. Run PlatformIO `Upload`.
8. Open the serial monitor at `1000000` baud.
9. Keep the rig still during the startup validation. Each sensor should show
   a mean magnitude close to `1.0 g`.
10. In MATLAB, use the same serial port and baud rate. For example:

```matlab
currentSimulationData.accelerationSensorsActive = true;
currentSimulationData.numberOfAccSensors = 5;
currentSimulationData.accelerationSensorPort = "COM9";
currentSimulationData.accelerationSensorBaud = 1000000;
currentSimulationData.accelerationSensorSampleRate = 250;
```

For a one-sensor test, set `NUM_SENSORS = 1` near the top of
`src/main.cpp`; the firmware will still park the unused AD0 pins high if
they are wired.
