# Single MPU6050/GY-521 on the photographed ESP8266

The board photographed on 2026-10-07 is marked **ESP8266MOD**, with a CP2102 USB-to-serial bridge and the NodeMCU pin layout. This project targets that board. It retains the existing MPU6050/GY-521 and NAMAZU serial data structure.

**Default: one three-axis accelerometer, ±16 g per axis, nominal 1,000 samples/s, USB serial at 1,000,000 baud.** Both the default and 500 Hz fallback compile successfully. Sustained delivery, sensor identity, calibration, and frequency response still need testing on the physical assembly; 1 kHz is a target, not a measured reliability claim.

## Wiring

Disconnect USB while connecting the wires. Use the printed pin names on the boards, regardless of which way the boards face.

| NodeMCU ESP8266 pin | GY-521 pin | Purpose |
| --- | --- | --- |
| **3V3** | **VCC** | 3.3 V sensor supply |
| **GND** | **GND** | Common ground |
| **D2 (GPIO4)** | **SDA** | I²C data |
| **D1 (GPIO5)** | **SCL** | I²C clock |
| **GND** | **AD0 / ADO** | Fix address at 0x68 |
| No connection | INT, XDA, XCL | Unused by this firmware |

Power the NodeMCU through its Micro-USB **data cable** connected to the PC. Use 3V3 for the GY-521; do not substitute VIN or VU for this wiring. ESP8266 signal pins use 3.3 V. Keep the I²C leads short, preferably around 20 cm or less for the initial 400 kHz test. Ordinary GY-521 modules have I²C pull-ups; verify that SDA/SCL idle near 3.3 V if the module or its pull-ups are uncertain. Do not route sensor wires to CLK/SD0/SD1/SD2/SD3/CMD: those belong to the ESP8266 flash interface.

The INT pin is unnecessary because the firmware polls FIFO occupancy and overflow status. The sensor's own sampling clock collects acceleration into its FIFO; the ESP drains complete frames in bursts.

## What changes compared with the existing rig

| Setting | `sensor_rig_esp32` (five sensors) | This project (one sensor) |
| --- | --- | --- |
| Controller | ESP32 | ESP8266 NodeMCU |
| Sensor hardware | MPU6050/GY-521 | Same MPU6050/GY-521 |
| Number of sensors | 5 | 1, measuring X/Y/Z |
| SDA / SCL | GPIO21 / GPIO22 | D2/GPIO4 / D1/GPIO5 |
| AD0 | One GPIO per sensor for selection | Ground permanently |
| Acceleration range | ±8 g | **±16 g** |
| Conversion | 4096 counts/g | **2048 counts/g** |
| Nominal output rate | 250 rows/s | **1000 rows/s** |
| Acceleration filter bandwidth | 94 Hz (DLPF 2) | **184 Hz (DLPF 1)** |
| Acquisition | Select and read each sensor | Acceleration-only FIFO |
| USB serial | 1,000,000 baud | Same |
| Output | Time + five groups | Time + one identical group |

The older `sensor_rig_top_1_fast` sketch used ±4 g and 500 Hz; the table above compares against the current five-sensor ESP32 firmware. Its old GPIO numbers must not be copied to this ESP8266.

One sensor does not need the five-sensor rig's address switching: AD0 grounded selects 0x68 continuously. Removing those transactions and collecting buffered samples makes the higher rate practical; it does not imply that the ESP8266 is faster than the ESP32. WiFi is disabled in this USB acquisition build to reduce contention and preserve the existing PC interface.

The humidity/temperature/light/gas sensors on the environmental carrier measure different quantities and have different drivers and update rates. None replaces this accelerometer. This MPU6050 connection is **I²C**; SPI and IEPE describe other interfaces and are not used here. The environmental project's JSON interface is separate from the existing acceleration CSV format.

## Range, bandwidth, and timing limits

- **±16 g is the MPU6050's largest acceleration range**, approximately ±156.9 m/s² on each axis. This is acceleration amplitude, not displacement amplitude of the structure or shaker. Gravity and offsets occupy part of that range. Aim below the limit; saturated samples cannot be recovered.
- At ±16 g, one ADC count is about **0.000488 g**. That is half the resolution of the ±8 g setting. Printing four decimals preserves the established format but does not imply that accuracy.
- **1,000 Hz is the maximum rate of new MPU6050 accelerometer samples.** Its advertised 8 kHz gyro-related rate cannot provide 8,000 distinct acceleration samples/s. Configuring a faster FIFO clock can duplicate acceleration readings.
- DLPF 1 gives a nominal **184 Hz acceleration bandwidth** and about 2 ms filter delay. A 1 kHz sample rate does not mean accurate, flat response up to 500 Hz. DLPF 0 offers nominal 260 Hz bandwidth, but its different base clock and weaker filtering are not the default here. For vibration amplitude work, characterize the response over the frequency band you need, including any content that could alias.
- `t_ms` is reconstructed from FIFO order and the configured sample period, anchored to ESP uptime at the beginning of each stream segment. It is monotonic across the ESP `micros()` wrap. **It is not a hardware edge timestamp, UTC, or proof of the actual sample rate.** The sensor clock has tolerance; USB delivery arrives in bursts. `stats` reports a separate estimate based on frames drained versus ESP elapsed time; the PC checker independently measures delivery against its monotonic clock.
- After an acquisition fault, the firmware emits a `nan` row, reports the fault, clears/reinitializes the sensor, and starts a new timestamp segment. Treat any resulting gap as a break in the experiment. Do not FFT across it as if samples were uninterrupted.

Genuine MPU6050 identity is 0x68. To retain compatibility with modules already accepted by the old rig, this firmware also accepts IDs 0x70 and 0x72, with a warning. Those IDs do not establish genuine MPU6050 timing/filter characteristics; verify the actual module before using those specifications in analysis.

## Build and upload

Run from the repository root with PlatformIO installed. Replace `COM9` with the board's actual port. Close MATLAB and any serial monitor before upload or capture.

```powershell
pio run -d Sensors/sensor_single_esp8266 -e nodemcuv2
pio run -d Sensors/sensor_single_esp8266 -e nodemcuv2 -t upload --upload-port COM9
```

On this workstation, if `pio` is not on PATH, use:

```powershell
& 'C:\Users\Mariu\.platformio\penv\Scripts\platformio.exe' run -d Sensors/sensor_single_esp8266 -e nodemcuv2 -t upload --upload-port COM9
```

Keep the sensor stationary during the approximately four-second startup and validation. At rest its vector magnitude should be near 1 g. Firmware automatically starts streaming afterward. Startup ROM bytes can be unreadable because the ESP8266 boot ROM uses a different baud rate; the application uses 1,000,000 baud, 8N1, CR/LF line endings.

The conservative fallback selects `-e nodemcuv2_500hz` for both build and upload. It keeps ±16 g and the same columns, but uses 500 samples/s and 2 ms nominal spacing. Use 500 in the PC settings too. Retest delivery and frequency response at that setting.

## Existing data contract

```text
t_ms;S1_ax_g,S1_ay_g,S1_az_g,S1_mag_g
4200;0.0000,0.0000,1.0000,1.0000
4201;1.0000,2.0000,2.0000,3.0000
```

These rows illustrate the format. Axes and magnitude remain in **g**, with four decimals; magnitude is `sqrt(ax² + ay² + az²)`, calculated from the raw readings. There are no new data columns. A failed acquisition is represented by `t_ms;nan,nan,nan,nan`. Diagnostics start with `#`; validation retains the `Sensor 1:`, `Mean ax [g]:`, `Mean ay [g]:`, and other labels recognized by the MATLAB readers.

Send commands terminated by LF or CR/LF:

| Command | Effect |
| --- | --- |
| `stats` | Print sample/error/near-limit counters and measured average delivery rate |
| `diag` | Print configuration and stats |
| `pause` | Stop acquisition |
| `resume` or `start` | Clear FIFO and begin a fresh stream segment |
| `validate` | Pause for a stationary check; then resume if previously streaming |

Counters accumulate until reset, including startup failures. `near_limit` counts samples with any axis at ≥98% of full scale; it is a warning of possible clipping, not a precise saturation detector. Commands and validation can interrupt timing; run validation between experiments. Excess FIFO backlog also causes an explicit fault instead of silently presenting data as continuous.

## NAMAZU / MATLAB

The existing reader supports one four-value sensor group. Set the number of sensors and rate explicitly; old defaults describe the five-sensor rig.

```matlab
LiveSingleSensorFFTMonitor("Port", "COM9", "Baud", 1000000, ...
    "NominalSampleRate", 1000, "Direction", "y", "FMax", 100);

batch = RunHammerTestBatch(10, "Port", "COM9", "Baud", 1000000, ...
    "NumSensors", 1, "SampleRate", 1000, "AccelerometerRangeG", 16);
```

For configurations using `StartExperimentSensorSerial`, set `numberOfAccSensors = 1`, `accelerationSensorBaud = 1000000`, `accelerationSensorSampleRate = 1000`, and the correct `accelerationSensorPort` in the existing configuration object, with `accelerationSensorsActive` enabled. Values are already in g; do not apply the old 4096-count conversion again. Scripts that explicitly require multiple simultaneous response/reference sensors still require those channels; one sensor cannot provide a simultaneous base-versus-structure FRF by itself.

## Check sustained delivery on the bench

After wiring and flashing, reset the board and run a 60-second check with the sensor stationary, then repeat during representative excitation. Keep only one program connected to the serial port. Install `pyserial` in your chosen Python environment if necessary; the workstation's PlatformIO Python already contains it.

```powershell
python Sensors/sensor_single_esp8266/tools/check_stream.py --port COM9 --rate 1000 --seconds 60 --output Sensors/sensor_single_esp8266/captures/bench-1000hz.csv
```

The capture preserves the serial lines, including diagnostics, and refuses to overwrite an existing file. It checks row structure, actual vector magnitude, nominal timestamp gaps, resets, range warnings, final firmware counters, and both PC- and ESP-measured delivery rates. The rate acceptance window is ±5%, a gross delivery check rather than a timing-accuracy specification. For a clean test, `i2c_errors`, `fifo_overflows`, `backlog_resets`, `faults`, and `near_limit` should all remain zero. Reset before repeating a test to clear earlier faults. Check that `max_fifo_bytes` stays well below the 480-byte backlog threshold.

Offline inspection and host-tool regression tests:

```powershell
python Sensors/sensor_single_esp8266/tools/check_stream.py --file Sensors/sensor_single_esp8266/captures/bench-1000hz.csv --rate 1000
python -m unittest discover -s Sensors/sensor_single_esp8266/tools -p "test_*.py" -v
```

Offline inspection cannot recreate PC arrival timing. A passed delivery check does not establish calibration, mounting quality, cross-axis response, or useful high-frequency bandwidth. If 1 kHz fails, first inspect power/wiring, the CP2102 connection, and competing PC readers; then test the 500 Hz build. Record the measured rate and chosen settings with each experiment.

## Software verification (2026-10-07)

Both PlatformIO environments built successfully (29,512 bytes RAM, 276,699 bytes flash each). Cppcheck completed without warnings in the enabled warning/performance/portability categories. All 10 host-tool regression tests passed, covering partial USB lines, corruption, missing samples, invalid values, full-scale values, true vector magnitude, device resets, firmware faults, and nominal-versus-observed rate checks. No board was flashed and no physical acquisition was measured during this implementation.

## References

- [InvenSense MPU-6000/MPU-6050 register map](https://cdn.sparkfun.com/datasheets/Sensors/Accelerometers/RM-MPU-6000A.pdf): sample-rate divider, DLPF, full-scale range, FIFO configuration and byte ordering.
- [InvenSense product specification](https://cdn.sparkfun.com/datasheets/Components/General%20IC/PS-MPU-6000A.pdf): acceleration range, sensitivity, maximum output rate, I²C and FIFO specifications.
- [ESP8266 Arduino NodeMCU pin definitions](https://github.com/esp8266/Arduino/blob/master/variants/nodemcu/pins_arduino.h): D1 = GPIO5, D2 = GPIO4.
- [ESP8266 Arduino reference](https://arduino-esp8266.readthedocs.io/en/latest/reference.html): Wire, serial, watchdog/yield and reserved flash pins.
- [PlatformIO NodeMCU target](https://docs.platformio.org/en/latest/boards/espressif8266/nodemcuv2.html).
