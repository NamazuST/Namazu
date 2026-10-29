# Grüni: five GY-521 sensors on the photographed ESP32-WROOM-32

Firmware for the AZ-Delivery **ESP32-WROOM-32** with the green mark, photographed on 2026-10-22. This is the 38-pin board with `G32`, `G33`, `G25`, etc. printed on its headers. It uses the existing five MPU6050/GY-521 boards, shared I²C, and individual AD0 wires. No multiplexer is required.

**Fast profile: 500 samples/s per sensor, ±16 g per axis, 921,600 baud.** A 333⅓ Hz profile provides headroom for even the longest full-range rows, and 250 Hz is an additional fallback. The board was identified as an ESP32-D0WDQ6 on **COM8**. The fast profile is a target to qualify on the assembled five-sensor rig, not a measured reliability claim.

**Four or five sensors with the old acquisition strategy at 500 Hz?** Use the
[continuous polling quick start](LATEST-QUICKSTART.md) and `Run-Latest-4-Sensors.cmd`
or `Run-Latest-5-Sensors.cmd`. These separate profiles read the latest acceleration
registers, continue past individual read failures with per-sensor NaNs, and count
missed sweeps/output rows. They use the same pins, baud rate, range, and CSV layout.
The FIFO behavior described below still applies to the original profiles.

**Adding the second sensor?** Use the [two-sensor quick start](TWO-SENSOR-QUICKSTART.md)
and double-click `Run-Two-Sensors.cmd` to upload `grueni_s2_500hz` and run a
60-second check yourself. S1 AD0 stays on G25; S2 AD0 goes to G26.

## Compact wiring

Orient the board exactly as in the photo: antenna at the top, Micro-USB at the bottom, components facing you. **All seven signal connections are on the left header**, within the stretch from G32 to G13. G12 is deliberately skipped because it is a boot configuration pin.

Disconnect USB while wiring. Power all five modules from the ESP32 **3V3** pin and use a shared ground. Each sensor needs five connections: VCC, GND, SDA, SCL, and its own AD0 wire.

| Printed ESP32 label | Connect to |
| --- | --- |
| **3V3** (top left) | VCC on all five GY-521 modules |
| **GND** (between G12 and G13) | GND on all five modules |
| **G32** | SDA on all five modules |
| **G33** | SCL on all five modules |
| **G25** | Sensor 1 AD0 / ADO |
| **G26** | Sensor 2 AD0 / ADO |
| **G27** | Sensor 3 AD0 / ADO |
| **G14** | Sensor 4 AD0 / ADO |
| **G13** | Sensor 5 AD0 / ADO |

The physical order of the relevant left-header pins, top to bottom:

```text
       G32  ── SDA, all five sensors
       G33  ── SCL, all five sensors
       G25  ── AD0, sensor 1
       G26  ── AD0, sensor 2
       G27  ── AD0, sensor 3
       G14  ── AD0, sensor 4
       G12     leave unused
       GND  ── GND, all five sensors
       G13  ── AD0, sensor 5
```

Distribute the four shared nets using a small terminal strip or soldered distribution board. Keep the five AD0 connections separate: **do not ground them or join them together**. Leave INT, XDA, and XCL unconnected. Do not substitute 5V for 3V3. GPIO6–11 / SDx / CMD / CLK are flash connections; G34/G35/SP/SN are input-only.

Start with short wires (about 20 cm or less per sensor branch). Five breakout boards can put five sets of pull-ups in parallel: check the effective resistance and bus rise time if the bus is unstable. SDA/SCL must idle at a suitable 3.3 V logic level, not 5 V. Longer shaker wiring, excessive capacitance, loose connectors, or overly strong pull-ups can limit operation at 400 kHz; a successful short-wire bench test does not qualify a long cable harness.

The ESP32 can route I²C to G32/G33, so the usual G21/G22 positions are unnecessary. For each transaction, the firmware parks the other sensors at address 0x69 and selects just one at 0x68 by driving its AD0 low. It never reads or writes the shared parked address. At startup, 0x68 must disappear when all AD0 lines are high; otherwise acquisition is refused.

## Rates and limitations

| Profile | Rate per sensor / complete rows per second | Serial baud | Range | Nominal MPU6050 acceleration bandwidth |
| --- | ---: | ---: | --- | --- |
| `grueni_500hz` (default, qualify delivery) | 500 | 921,600 | ±16 g | 184 Hz, DLPF 1 |
| `grueni_333hz` (full-range serial headroom) | 1000/3 ≈ 333.333333 | 921,600 | ±16 g | 94 Hz, DLPF 2 |
| `grueni_250hz` | 250 | 921,600 | ±16 g | 94 Hz, DLPF 2 |
| `grueni_s1_500hz` (S1 only) | 500 | 921,600 | ±16 g | 184 Hz, DLPF 1 |
| `grueni_s2_500hz` (S1 and S2) | 500 | 921,600 | ±16 g | 184 Hz, DLPF 1 |
| `grueni_latest4_500hz` (latest polling, S1–S4) | 500 target | 921,600 | ±16 g | 184 Hz, DLPF 1 |
| `grueni_latest5_500hz` (latest polling, S1–S5) | 500 target | 921,600 | ±16 g | 184 Hz, DLPF 1 |

500 Hz means **500 complete five-sensor rows/s**, containing 2,500 three-axis sensor samples/s. It is not 500 divided among five sensors. Acceleration remains in g, with four decimals and real vector magnitude. The conversion is 2,048 counts/g; one count is approximately 0.000488 g. The wider range preserves the single-sensor project's impact headroom at the cost of resolution compared with the older ±8 g rig.

At 921,600 baud / 8N1, the theoretical payload ceiling is 92,160 bytes/s. A five-sensor row requires roughly 150–185 bytes at ordinary timestamp lengths, depending on values/signs. At 500 rows/s this is about 75,000–92,500 bytes/s. **500 Hz fits typical readings but cannot sustain every possible full-range value pattern indefinitely.** An 8 KB UART buffer absorbs bursts; if the bounded acquisition queues fill, the firmware stops with an explicit fault. It does not silently lower the sample rate or discard samples.

The maximum row length, including a 20-digit timestamp and all axes at negative full scale, is 197 bytes. The 333⅓ Hz profile needs at most about 65,667 bytes/s for such rows, leaving substantial serial headroom. Its native sensor divider is 2, so its exact sample interval is **3 ms**; use `1000/3`, not an assumed exact 333 Hz, in analysis. A build-time check enforces the worst-case serial budget for the 333⅓ and 250 Hz profiles. Use 333⅓ Hz for a recording that needs that margin rather than trying to qualify 500 Hz only at rest.

**Five sensors at 1 kHz cannot fit the unchanged text format through this USB bridge.** A faster CPU does not remove that limit. A different transport or more compact protocol would be a separate change. The MPU6050 also has only 1 kHz of distinct acceleration samples; its 8 kHz gyro-related setting cannot create more acceleration information.

The photographed bridge appears to be a classic CP2102. Silicon Labs lists 921,600 in its standard-rate electrical table, while the datasheet overview mentions up to 1 Mbps. **A 1 Mbps startup test on this exact ESP32/COM8 produced corrupted application text**, as previously seen on the ESP8266 assembly. All final profiles therefore use 921,600 baud. Brief ESP32 boot output at its ROM baud is separate from application corruption.

The stated filter bandwidths assume a genuine MPU6050. Compatible IDs 0x70/0x72 are accepted with an explicit warning, as in the existing projects; these IDs do not establish equivalent filter response or sensitivity. Do not assume a flat response up to Nyquist, and characterize mounting, filtering, aliasing, and amplitude before quantitative vibration work.

## FIFO acquisition and timing integrity

This section describes `main.cpp` and the original FIFO profiles. The separate
`latest.cpp` profiles use the [continuous polling behavior](LATEST-QUICKSTART.md).

Each sensor continuously fills an acceleration-only FIFO. The ESP32 drains these in bursts into five independent bounded queues, then writes complete rows into an asynchronous UART buffer. It checks configuration readback, FIFO overflow, I²C failures, missing data, queue capacity, and frame-count divergence. It never fills gaps by repeating the last reading or silently discarding a frame to align sensors.

One row contains the next FIFO sample from each sensor. `t_ms` is a **nominal 2, 3, or 4 ms grid**, anchored to ESP uptime at the start of each stream segment. It is not an exact capture timestamp for every sensor and does not prove actual sampling rate. The MCU clock is extended by `esp_timer_get_time`, so timestamps do not wrap after 71 minutes. Firmware statistics independently measure frames/rows over MCU elapsed time; the PC checker measures delivery against its own clock.

**The five sensors are not hardware synchronized.** FIFO enable commands are issued in a short sweep, whose duration is reported as `start_span_us`, but independent sensor clocks retain initial offsets and drift. `max_count_skew` includes both drift and sequential read timing; it is not a bound on phase error. More than four queued samples of divergence stops the stream instead of silently reassigning sample indices. This can limit continuous recording duration on modules with mismatched clocks. For FRFs or mode-shape phase comparisons, first measure inter-sensor delay/drift using common excitation; identical CSV timestamps alone do not establish simultaneity.

On a fault, **the whole rig stops** and emits a row containing five `nan,nan,nan,nan` groups, followed by `# STREAM_FAULT` with a reason and sensor number. This preserves all column positions and prevents partial rigs from appearing valid. Fix the issue and reset or send `start` to begin a new segment. Treat every fault, pause, or validation interruption as a break; do not interpolate or FFT across it.

## Build, upload, and first use

### Checking the first soldered sensor

With **only S1 attached**, the separate `grueni_s1_probe` profile checks the wiring
without requiring S2–S5. Connect VCC → 3V3, GND → GND, SDA → G32, SCL → G33,
and AD0 → G25. This is a diagnostic program, not an acceleration stream:

```powershell
pio run -d Sensors/sensor_rig_esp32_grueni -e grueni_s1_probe -t upload --upload-port COM8
pio device monitor -d Sensors/sensor_rig_esp32_grueni -e grueni_s1_probe --port COM8
```

At 921,600 baud it reports idle GPIO levels, tests SDA/SCL independently using
brief open-drain pulses, and probes 0x68/0x69 at both 100 and 400 kHz. With AD0
high, only 0x69 should acknowledge; with AD0 low, only 0x68 should acknowledge.
An acknowledged device's WHO_AM_I register is read. Result 0 means ACK, 2 means
address NACK, and 5 means timeout. High idle GPIO readings alone do not prove
continuity to the sensor, power at the module, or adequate external pull-ups.

When SCL is pulled low, SDA should stay high; when SDA is pulled low, SCL should
stay high. If they follow each other, disconnect USB and check for a solder bridge
or an uncut shared copper strip. Confirm with an unpowered continuity check; the
GPIO test cannot locate the connection or exclude other causes. Send any character
to repeat the diagnostic. **Do not run this profile with multiple sensors attached**:
it reads their shared parked address. The acquisition profiles use `main.cpp` and
exclude this diagnostic source; upload one of them again for recording.

### Recording with only sensor 1 connected

Once the wiring probe succeeds, `grueni_s1_500hz` runs the same FIFO acquisition
and integrity checks for **S1 only**, using AD0 G25, SDA G32, and SCL G33. It runs
at 500 samples/s, ±16 g, 921,600 baud. The other four select lines remain parked.
It uses the established format with just the S1 group, not fabricated data for
missing sensors:

```text
t_ms;S1_ax_g,S1_ay_g,S1_az_g,S1_mag_g
6000;0.0000,0.0000,1.0000,1.0000
```

```powershell
pio run -d Sensors/sensor_rig_esp32_grueni -e grueni_s1_500hz -t upload --upload-port COM8
python Sensors/sensor_rig_esp32_grueni/tools/check_stream.py --port COM8 --sensors 1 --rate 500 --seconds 60 --output Sensors/sensor_rig_esp32_grueni/captures/bench-s1-500hz.csv
```

Keep S1 still for the startup validation. Set the PC reader to one sensor,
921,600 baud, and 500 Hz. Use `--sensors 1` for offline checking too. When the full
rig is assembled, upload `grueni_500hz` (or a five-sensor fallback) and return the
PC reader to five sensors. The default build still requires all five sensors;
a successful S1 test does not qualify the complete bus, transport load, or timing
alignment of five modules.

### Five-sensor acquisition

For a partial rig with S1 and S2, follow the
[two-sensor quick start](TWO-SENSOR-QUICKSTART.md) instead. The launcher uploads
the matching two-group format, checks both sensors, and saves the log and data.

Open this folder in PlatformIO, or run from the repository root:

```powershell
pio run -d Sensors/sensor_rig_esp32_grueni -e grueni_500hz
pio device list
pio run -d Sensors/sensor_rig_esp32_grueni -e grueni_500hz -t upload --upload-port COM8
pio device monitor -d Sensors/sensor_rig_esp32_grueni -e grueni_500hz --port COM8
```

COM8 was verified as this ESP32 on 2026-10-22; recheck the port if Windows changes it. Close MATLAB/serial monitors before upload. If `pio` is not on PATH on this workstation, replace it with:

```powershell
& 'C:\Users\Mariu\.platformio\penv\Scripts\platformio.exe'
```

Append the same `run ...` arguments to that executable. For more serial headroom, use `-e grueni_333hz` for upload and monitor, and set the PC reader to 921,600 baud and `1000/3` Hz. The additional `grueni_250hz` fallback uses 250 Hz. Upload itself uses 115,200 baud for all profiles; that is separate from the measurement baud.

Keep **all five sensors still for approximately five seconds after startup**, until `Validation finished.` appears. Each `SENSOR_INIT` should say `OK`, each validation should contain 200/200 valid readings, and the magnitude should be near 1 g. Streaming then begins automatically. All five sensors must be connected; missing sensors cause a stopped fault state.

The data contract is unchanged from the five-sensor rig:

```text
t_ms;S1_ax_g,S1_ay_g,S1_az_g,S1_mag_g;S2_ax_g,S2_ay_g,S2_az_g,S2_mag_g;S3_ax_g,S3_ay_g,S3_az_g,S3_mag_g;S4_ax_g,S4_ay_g,S4_az_g,S4_mag_g;S5_ax_g,S5_ay_g,S5_az_g,S5_mag_g
6000;0.0000,0.0000,1.0000,1.0000;0.0000,0.0000,1.0000,1.0000;0.0000,0.0000,1.0000,1.0000;0.0000,0.0000,1.0000,1.0000;0.0000,0.0000,1.0000,1.0000
```

Diagnostics begin with `#`; stationary validation keeps the established `Sensor 1:` / `Mean ax [g]:` / `Mean |a| [g]:` labels. Commands are LF- or CR/LF-terminated:

| Command | Effect |
| --- | --- |
| `stats` | Report delivery rates, errors, FIFO/queue maxima, count skew, startup span |
| `diag` | Report settings and statistics without restarting acquisition |
| `pause` | Stop all sensors' FIFO acquisition and mark a stream break |
| `start` / `resume` | Reinitialize all five sensors, clear queues, start a new segment |
| `validate` | Perform stationary validation; restart a new segment if previously streaming |

Counters and maxima accumulate until board reset; per-sensor frame counts and delivery estimates refer to the current segment. `near_limit` counts readings with any axis at ≥98% of range, indicating possible clipping. Reset before a clean qualification run if a prior attempt failed.

## MATLAB / NAMAZU configuration

For the existing five-sensor acquisition:

```matlab
currentSimulationData.accelerationSensorsActive = true;
currentSimulationData.numberOfAccSensors = 5;
currentSimulationData.accelerationSensorPort = "COM8";
currentSimulationData.accelerationSensorBaud = 921600;
currentSimulationData.accelerationSensorSampleRate = 500;
```

For `RunHammerTestBatch`, pass `"NumSensors",5`, `"Baud",921600`, `"SampleRate",500`, and `"AccelerometerRangeG",16`, with the actual port. Use `"SampleRate",1000/3` for the 333⅓ Hz profile. The data are already in g; do not apply another raw-count conversion. Keep any chosen FFT upper limit appropriate to the sensor response and experiment.

The older five-sensor MATLAB readers understand the same 21 numeric columns, but their sustained throughput and gap handling must be qualified separately. **`LiveSingleSensorFFTMonitor` only accepts one sensor and is not the viewer for this five-sensor stream.** This project does not modify those scripts or the older rigs' pin maps/defaults.

## Bench acceptance

With all sensors connected, first inspect startup output at the matching baud. Then close other readers and run:

```powershell
python Sensors/sensor_rig_esp32_grueni/tools/check_stream.py --port COM8 --rate 500 --seconds 60 --output Sensors/sensor_rig_esp32_grueni/captures/bench-500hz.csv
```

The tool requires `pyserial` (available in this workstation's PlatformIO Python), requests a pause/start handshake, and saves only the new complete segment. Existing capture files are never overwritten. It checks all five groups, vector magnitudes, range, missing timestamps, corrupted rows, error counters, and separate sensor/MCU/PC delivery rates. Rates must be within ±5% for this gross throughput test, which is not a timing-accuracy specification. Use `--rate 333` for the exact 333⅓ Hz profile or `--rate 250` for the slower fallback. All use 921,600 baud by default.

On Windows, the checker requests a 256 KiB receive queue instead of pyserial's
4 KiB default to provide headroom during PC scheduling pauses. This is a driver
request, not a verified allocated size: [Windows permits the driver to choose its
buffering scheme](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-setupcomm).
Timestamp and corruption checks remain mandatory. A clean repeat after a larger
queue request does not, by itself, establish the cause of an earlier transfer gap.

Repeat for the intended recording duration, then under representative excitation. Expect zero malformed/invalid groups, gaps, faults, FIFO overflows, and I²C errors. Check `max_fifo_bytes` stays well below 480 and `max_queue` below 64. A near-limit warning means the motion may be clipping. If `sample_count_skew` occurs, stop and evaluate clock mismatch; do not disable the check and assume phase alignment.

```powershell
python Sensors/sensor_rig_esp32_grueni/tools/check_stream.py --file Sensors/sensor_rig_esp32_grueni/captures/bench-500hz.csv --rate 500
python -m unittest discover -s Sensors/sensor_rig_esp32_grueni/tools -p "test_*.py" -v
```

The CSV has no checksum; magnitude/format checks catch many failures but cannot detect every possible corruption. Passing this test establishes delivery for the tested interval, not calibration or inter-sensor phase alignment.

## Verification on 2026-10-22

All three profiles built successfully using Espressif32 6.13.0 / Arduino-ESP32 2.0.17. Cppcheck reported no enabled warning/performance/portability findings. Fourteen host regression tests cover all three rates, split packets, all twenty sensor fields, malformed/non-ASCII data, NaN groups, gaps, duplicate/reversed time, magnitude errors, clipping, faults/restarts, missing sensor statistics, independent PC delivery timing, and the pause/start capture handshake.

The final **500 Hz / 921,600 baud** profile was uploaded to the ESP32 on **COM8**, and esptool verified the flash hashes. Application startup text was completely readable, with zero high-bit bytes after the firmware banner. None of the five sensors responded on the configured pins (`SENSOR_INIT ... FAILED` for S1–S5), so the firmware emitted a five-group NaN fault row and remained stopped (`streaming=0`). This checks boot, serial diagnostics, and missing-sensor handling; it **does not validate five-sensor acquisition throughput**. Connect the complete rig according to the table, reset, and run the bench check.

Local diagnostic captures are under ignored `captures/`: `startup-1M-20261022-164223.bin` (corrupted application text) and `startup-921600-20261022-164903.bin` (readable application text). No healthy five-sensor measurement was available during this implementation.

## First soldered sensor check, 2026-10-23

Only S1 was connected, with AD0 on G25, on COM8. The original acquisition firmware
reported `parked_address_check result=5` (timeout). The separate `grueni_s1_probe`
profile built and uploaded successfully, with flash hashes verified. Its output:

```text
Idle:                  SDA_G32=1 SCL_G33=1
Pull SCL low:          SDA=0 SCL=0 (expected 1,0)
Pull SDA low:          SDA=0 SCL=0 (expected 0,1)
AD0 high/low:          G25 readback follows the commanded state
0x68 and 0x69 probes:  timeout at both 100 kHz and 400 kHz
```

This strongly suggests an electrical connection between SDA and SCL; it does not
locate it. Disconnect USB, check continuity between these nets, and inspect the
new soldered board for bridges or a shared copper strip before retesting. There
was no successful sensor identification or acceleration acquisition. The GPIO
readback does not prove continuity of G25 to the sensor's AD0 pad.

At the end of this initial check, the **diagnostic profile was flashed**, at 921,600 baud; it does not stream
acceleration data. Local evidence is saved under ignored `captures/` as
`startup-s1-20261023-114819.bin` and `probe-lines-s1-20261023-115330.bin`.

### Recheck and S1 acquisition, 2026-10-23

On recheck, S1 initialized successfully at 400 kHz (`WHO_AM_I=0x72`); the previous
bus timeout was no longer present. The device was then running a five-sensor
profile, which correctly refused acquisition because S2–S5 were absent. A separate
`grueni_s1_500hz` profile was added, built, uploaded, and verified on COM8. It is
the **currently installed profile**, with only the S1 data group, 500 Hz, ±16 g,
and 921,600 baud. All three five-sensor profiles also rebuilt successfully and
the checker passed 17 host regression tests, including one/five-sensor capture.

Startup produced 200/200 valid readings. Mean acceleration was
`(-0.0749, 0.2429, 0.9761) g`, and mean vector magnitude was **1.0087 g**. These
are a plausibility check at the current orientation, not calibration constants.

The first 60-second capture had one truncated line and a 15-sample gap (30 ms of
missing samples), despite zero firmware I²C/FIFO/fault counters. This test failed;
its evidence is retained in `captures/bench-s1-500hz-20261023-132244.csv` and the
matching `.report.txt`. Firmware builds were running concurrently. A host/USB
delivery interruption is consistent with the evidence, but the cause was not
isolated.

The checker was updated to request a larger Windows receive buffer. A repeat
after the builds finished **passed**:

| Check | Result |
| --- | --- |
| Capture duration | 59.984 s between first/last PC sample arrivals (60 s requested) |
| Complete samples | 30,032 |
| PC delivery rate | 500.650 samples/s |
| Firmware/sensor frame rate | 500.395 samples/s |
| Malformed/invalid rows, timestamp gaps, stream faults | 0 |
| I²C errors / FIFO overflows / near-limit readings | 0 / 0 / 0 |
| Maximum FIFO occupancy / software queue | 30 bytes / 5 frames |
| Largest absolute axis value | 1.5249 g |

The successful capture and report are
`captures/bench-s1-buffered-20261023-132555.csv` and
`captures/bench-s1-buffered-20261023-132555.report.txt`. Startup evidence is in
`captures/startup-s1-stream-20261023-132216.bin`. A successful repeat does not prove
that the buffer request caused the improvement, and does not qualify a busy PC,
longer recordings, or a complete five-sensor rig. Keep gap detection enabled in
measurement readers. The compatible 0x72 device's calibration and frequency
response remain unverified.

## Sources

- [Espressif I²C API](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/i2c.html): configurable SDA/SCL and pull-up requirements.
- [ESP32 datasheet](https://documentation.espressif.com/esp32_datasheet_en.pdf): GPIO capabilities, boot strapping, flash connections.
- [MPU-6000/6050 register map](https://cdn.sparkfun.com/datasheets/Sensors/Accelerometers/RM-MPU-6000A.pdf): AD0 addressing, divider/filter settings, FIFO registers and overflow behavior.
- [Silicon Labs CP2102/9 datasheet](https://www.silabs.com/documents/public/data-sheets/CP2102-9.pdf): USB-UART baud-rate specifications.
