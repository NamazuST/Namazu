# Run the two-sensor rig yourself

Profile: **`grueni_s2_500hz`**, **500 samples/s per sensor**, **±16 g per axis**,
**921,600 baud**, default port **COM8**. This uses the same acquisition code and
text format as the one- and five-sensor profiles, with exactly two sensor groups.

## 1. Wire sensor 2 with USB disconnected

| GY-521 connection | Sensor 1 → ESP32 | Sensor 2 → ESP32 |
| --- | --- | --- |
| VCC | 3V3 | 3V3 |
| GND | GND | GND |
| SDA | G32 | G32 |
| SCL | G33 | G33 |
| AD0 / ADO | G25 | **G26** |

The four power/bus connections are shared. **AD0 is separate for each sensor**;
do not connect it permanently to ground or join the two AD0 wires. Leave INT,
XDA, and XCL unconnected. Check the new solder joints for bridges, especially
between SDA and SCL. Both sensors must be attached for this profile to stream.

## 2. Upload and check

Reconnect USB, close MATLAB and any serial monitor using COM8, and keep both
sensors still for the first few seconds.

**Double-click `Run-Two-Sensors.cmd` in this folder in File Explorer.** It finds
the existing PlatformIO Python installation, builds and uploads the two-sensor
firmware, then records and checks 60 seconds. It keeps its window open at the end.

Alternatively, run this from the repository root in PowerShell:

```powershell
.\Sensors\sensor_rig_esp32_grueni\Run-Two-Sensors.cmd
```

The launcher saves a uniquely named `.csv` recording and `.log` session report
under this project's `captures/` folder, and prints their full paths. The report
includes upload output, available startup diagnostics, and the check result.
An upload failure stops the launcher before acquisition. The two-sensor firmware
stays installed after the test; it starts streaming again after a successful boot.

## 3. Read the result

- `SENSOR_INIT id=1 ... result=OK` and `id=2 ... result=OK` should appear when the
  checker starts its new recording segment.
- Startup validation should show 200/200 valid readings for each sensor; when
  still, each mean magnitude should be near 1 g. The individual axes depend on
  how the module is oriented. Some early boot messages may precede the checker's
  port opening and are not guaranteed to appear in the log.
- **`CHECK PASSED`** means both streams passed the data-delivery checks for this
  interval: approximately 500 complete rows/s, no detected missing/corrupted
  samples, and zero reported I²C/FIFO/stream faults. This does not establish
  calibration or simultaneous sampling between the two modules.
- **`CHECK FAILED`**: keep the `.log` and `.csv`. `initialization` / `start_failed`
  / `pause_failed` can mean a missing or incorrectly connected sensor. A firmware
  header mismatch means the installed profile and requested sensor count differ.
  A port-access error usually means another program has COM8 open, the board is
  disconnected, or its COM number changed.
- `sample_count_skew` means the sensor sample counts diverged beyond the allowed
  margin. Stop and investigate their timing; do not disable this check or treat
  identical row timestamps as proof of synchronization.

**Do not use `grueni_s1_probe` with both sensors connected.** That separate wiring
diagnostic is specifically for one module and reads the shared parked address.

## Repeat without uploading

From the repository root, with the two-sensor firmware already installed:

```powershell
.\Sensors\sensor_rig_esp32_grueni\Run-Two-Sensors.cmd --check-only
.\Sensors\sensor_rig_esp32_grueni\Run-Two-Sensors.cmd --check-only --seconds 120
```

If Windows assigns another port, append `--port COM9` (or the actual port). To
compile only, with no serial-port access, use `--build-only`.

## Use the data in NAMAZU / MATLAB

Configure the multi-sensor reader for **2 sensors, 500 Hz, 921,600 baud, COM8**:

```matlab
currentSimulationData.numberOfAccSensors = 2;
currentSimulationData.accelerationSensorPort = "COM8";
currentSimulationData.accelerationSensorBaud = 921600;
currentSimulationData.accelerationSensorSampleRate = 500;
```

The row structure is:

```text
t_ms;S1_ax_g,S1_ay_g,S1_az_g,S1_mag_g;S2_ax_g,S2_ay_g,S2_az_g,S2_mag_g
```

Acceleration values are already in g. `LiveSingleSensorFFTMonitor` accepts one
sensor, so use a multi-sensor reader for this profile. Run only one serial reader
at a time. The default PlatformIO profile still targets all five sensors; select
`grueni_s2_500hz` explicitly if uploading through PlatformIO instead of the launcher.

Prepared and compiled on 2026-10-23. The two-sensor firmware build, launcher help,
and 19 host regression tests passed. No two-sensor hardware test was performed
during preparation; the launcher performs that check when you run it after wiring.
