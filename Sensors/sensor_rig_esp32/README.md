# ESP32 MPU6050 sensor rig firmware

This firmware runs the acceleration sensor rig on a classic ESP32 dev board.
It uses the same serial row format that the MATLAB sensor-rig functions expect:

```text
t_ms;S1_ax_g,S1_ay_g,S1_az_g,S1_mag_g;S2_ax_g,...
```

The current firmware constants are summarized in `FIRMWARE_SETTINGS.md`.

The current accelerometer range is `+-8 g`. This was increased from `+-4 g`
after the first hammer-test batch clipped with a heavy hand hammer.

## Default wiring

Use a 3.3 V ESP32 board. The MPU6050 I2C pins must not be pulled up to 5 V.

Many ESP32 dev boards print `D` pin names on the board instead of `GPIO` or
`IO` names. On those boards, `D13` usually means `GPIO13`, `D25` usually means
`GPIO25`, and so on. `RX2` is usually `GPIO16`, and `TX2` is usually `GPIO17`.
If your board has a printed pinout on the back, trust that first.

| ESP32 pin | Sensor rig connection |
| --- | --- |
| 3V3 | all MPU6050 VCC pins |
| GND | all MPU6050 GND pins |
| GPIO21 / D21 | all MPU6050 SDA pins |
| GPIO22 / D22 | all MPU6050 SCL pins |
| GPIO13 / D13 | sensor 1 AD0 |
| GPIO14 / D14 | sensor 2 AD0 |
| GPIO25 / D25 | sensor 3 AD0 |
| GPIO26 / D26 | sensor 4 AD0 |
| GPIO27 / D27 | sensor 5 AD0 |

Leave MPU6050 `INT` unconnected.

## Generic ESP32 dev board wiring

This is the wiring used with the other ESP32 dev board that already worked.
Use this table when the board labels look like `D13`, `D14`, `D25`, `D26`,
and `D27`.

| ESP32 board label | Firmware GPIO | Sensor rig connection | Suggested wire color |
| --- | --- | --- | --- |
| `3V3` | 3.3 V supply | all MPU6050 `VCC` pins | red |
| `GND` | ground | all MPU6050 `GND` pins | black |
| `D21` / `GPIO21` | GPIO21 | all MPU6050 `SDA` pins | blue |
| `D22` / `GPIO22` | GPIO22 | all MPU6050 `SCL` pins | green |
| `D13` / `GPIO13` | GPIO13 | sensor 1 `AD0` / `ADO` | yellow, label `S1` |
| `D14` / `GPIO14` | GPIO14 | sensor 2 `AD0` / `ADO` | yellow, label `S2` |
| `D25` / `GPIO25` | GPIO25 | sensor 3 `AD0` / `ADO` | yellow, label `S3` |
| `D26` / `GPIO26` | GPIO26 | sensor 4 `AD0` / `ADO` | yellow, label `S4` |
| `D27` / `GPIO27` | GPIO27 | sensor 5 `AD0` / `ADO` | yellow, label `S5` |

## DFRobot FireBeetle ESP32 V4.0 wiring

The photographed board is labelled `DFROBOT FireBeetle Board-ESP32 [V4.0]`.
Use the labels printed on the board. Most important: connect the sensor `VCC`
wires to the board pin labelled `3V3`, not to the board pin labelled `VCC`.

| Board label on your ESP32 | Firmware GPIO | Sensor rig connection | Suggested wire color |
| --- | --- | --- | --- |
| `3V3` | 3.3 V supply | all MPU6050 `VCC` pins | red |
| `GND` | ground | all MPU6050 `GND` pins | black |
| `SDA/IO21` | GPIO21 | all MPU6050 `SDA` pins | blue |
| `SCL/IO22` | GPIO22 | all MPU6050 `SCL` pins | green |
| `IO13/D7` | GPIO13 | sensor 1 `AD0` / `ADO` | yellow, label `S1` |
| `BCLK/IO14` | GPIO14 | sensor 2 `AD0` / `ADO` | yellow, label `S2` |
| `IO25/D2` | GPIO25 | sensor 3 `AD0` / `ADO` | yellow, label `S3` |
| `IO26/D3` | GPIO26 | sensor 4 `AD0` / `ADO` | yellow, label `S4` |
| `IO27/D4` | GPIO27 | sensor 5 `AD0` / `ADO` | yellow, label `S5` |

Color coding is useful, but do not trust it blindly. Check the printed pin
labels on the ESP32 and MPU6050 boards before powering the rig. The yellow
`AD0` wires are especially easy to mix up, so mark both cable ends with the
sensor number.

Physical connection options:

1. For bench testing, use female Dupont jumper wires on the ESP32 header pins.
2. For five sensors, use a small breadboard, screw-terminal strip, Wago-style
   lever connectors, or a soldered distribution board for the shared `3V3`,
   `GND`, `SDA`, and `SCL` lines.
3. Keep each `AD0` wire separate. Do not join the yellow `AD0` wires together.
4. Power the ESP32 off before moving jumper wires.

The shared bus should look like this:

```text
ESP32 3V3      -> S1 VCC, S2 VCC, S3 VCC, S4 VCC, S5 VCC
ESP32 GND      -> S1 GND, S2 GND, S3 GND, S4 GND, S5 GND
ESP32 SDA/IO21 -> S1 SDA, S2 SDA, S3 SDA, S4 SDA, S5 SDA
ESP32 SCL/IO22 -> S1 SCL, S2 SCL, S3 SCL, S4 SCL, S5 SCL

ESP32 IO13/D7  -> S1 AD0
ESP32 IO14     -> S2 AD0
ESP32 IO25/D2  -> S3 AD0
ESP32 IO26/D3  -> S4 AD0
ESP32 IO27/D4  -> S5 AD0
```

The firmware selects one MPU6050 at a time by pulling its `AD0` pin low
so it appears at I2C address `0x68`. All other sensors are parked high at
address `0x69`, which avoids address conflicts while the ESP32 reads `0x68`.

Do not use ESP32 GPIO6-GPIO11 for `AD0`; those pins are normally connected
to the ESP32 flash chip. Do not use `D34`, `D35`, `VN`, or `VP` for `AD0`;
those pins are input-only and cannot switch the MPU6050 address.

## If your board only has labels like D2, D4, RX2, TX2

Prefer the default pins above if your board exposes them. If it does not, this
fallback set normally works on many ESP32 boards:

| ESP32 board label | GPIO name | Sensor rig connection |
| --- | --- | --- |
| D21 | GPIO21 | all MPU6050 SDA pins |
| D22 | GPIO22 | all MPU6050 SCL pins |
| RX2 | GPIO16 | sensor 1 AD0 |
| TX2 | GPIO17 | sensor 2 AD0 |
| D25 | GPIO25 | sensor 3 AD0 |
| D26 | GPIO26 | sensor 4 AD0 |
| D27 | GPIO27 | sensor 5 AD0 |

For that fallback set, change this line near the top of `src/main.cpp`:

```cpp
static constexpr int AD0_PINS[MAX_SENSORS] = {13, 14, 25, 26, 27};
```

to:

```cpp
static constexpr int AD0_PINS[MAX_SENSORS] = {16, 17, 25, 26, 27};
```

Pins `D2` and `D4` can work as outputs, but they are ESP32 boot strapping pins.
Use them only if you have no better pins available, and disconnect the sensor
rig during flashing if the board fails to boot or upload.

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

## Troubleshooting `nan,nan,nan,nan`

Rows full of `nan` mean the ESP32 is streaming, but the MPU6050 reads are
failing. Reset the ESP32 and look at the startup `I2C / AD0 DIAGNOSTIC` block.

Expected result for a fully wired multi-sensor rig:

```text
All AD0 high / parked: 0x68=--, 0x69=ACK
Selected sensor 1 ...: 0x68=ACK, 0x69=ACK
Selected sensor 2 ...: 0x68=ACK, 0x69=ACK
```

If all sensors are parked high but `0x68=ACK` still appears, at least one
sensor `AD0` pin is not connected to the ESP32, is shorted to GND, or cannot
be driven by the selected GPIO.

If both `0x68` and `0x69` are always `--`, check power, ground, SDA/SCL
orientation, pull-ups, and whether your board really maps `D21`/`D22` to
GPIO21/GPIO22.

If the diagnostic shows `WHO=0x72`, the sensor is answering but identifies as
an MPU-compatible variant rather than the classic `WHO=0x68` MPU6050. The
firmware accepts `0x68`, `0x70`, and `0x72` because the acceleration registers
used here are compatible on common modules with those IDs.

The firmware holds the startup messages for `3` seconds before live output
starts. During live output you can type these commands into the serial monitor:

```text
diag
validate
pause
resume
start
```

`diag` reruns the I2C/AD0 diagnostic. `validate` reruns the static validation
and prints fresh mean `ax`, `ay`, `az`, and `|a|` values for every configured
sensor. `pause` stops the live stream so you can copy messages. `resume` or
`start` continues streaming.

If you want the firmware to wait forever until you type `start`, set this near
the top of `src/main.cpp`:

```cpp
static constexpr bool WAIT_FOR_START_COMMAND = true;
```

## Troubleshooting clipped hammer-test data

If a hammer run contains repeated values close to the acceleration range, the
signal is clipped. With the current firmware, watch for axis values close to
`+8 g` or `-8 g`.

If clipping still occurs:

1. Hit more gently or use a lighter/softer hammer tip.
2. Move the impact point or sensor mounting if one sensor is hit too directly.
3. Increase the firmware range to `+-16 g` by changing `MPU_ACCEL_CONFIG` to
   `0x18` and `ACCEL_SCALE_LSB_PER_G` to `2048` in `src/main.cpp`.

Only use `+-16 g` when needed. It gives more headroom but lower acceleration
resolution.

You can also capture the first few seconds to a text file from PowerShell:

```powershell
cd C:\OMNISSIAH\Projekte\26-05-08-Namazu-Hackathon\Sensors\sensor_rig_esp32
python tools\log_serial_startup.py COM9 --seconds 3
```

Replace `COM9` with your ESP32 port. If Python reports that `serial` is
missing, install `pyserial` in the Python environment you use for this project.
