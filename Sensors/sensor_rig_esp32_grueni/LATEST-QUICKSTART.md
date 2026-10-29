# Continuous 500 Hz polling: four sensors now, five when assembled

These **separate firmware profiles** use the old rig's acquisition strategy:
read each sensor's latest six acceleration-register bytes in sequence, then
send one CSV row. They target **500 complete rows/s**, with **±16 g per axis**
and **921600 baud**. FIFO profiles and the two-sensor launcher remain available.

## Run it yourself

1. Disconnect USB while soldering or changing connections. Finish the wiring
   before reconnecting to COM8. Close MATLAB and other serial monitors.
2. With S1–S4 connected, double-click **`Run-Latest-4-Sensors.cmd`**.
3. Once S5 is connected, double-click **`Run-Latest-5-Sensors.cmd`** instead.

Each launcher builds and uploads its profile, then records a **60-second check**
and saves the CSV and a detailed `.log` in `captures/`. Keep the rig still during
the initial validation. The check does not stop early because a sensor reports
NaN: it completes the timed capture and reports the data-quality result.

The launcher window stays open at the end. The board keeps streaming, but
closing/reopening a USB serial connection can reset it. Set your MATLAB/NAMAZU
reader to **four or five sensor groups**, **500 Hz nominal**, and **921600 baud**.
This version changes no MATLAB files. Configure the existing reader for the
matching sensor count; acquisition errors must be treated as missing data.

From PowerShell in this folder:

```powershell
.\Run-Latest-4-Sensors.cmd --seconds 120
.\Run-Latest-5-Sensors.cmd --check-only --seconds 120
.\Run-Latest-5-Sensors.cmd --build-only
```

`--check-only` requires the matching latest-register firmware already uploaded.
It verifies the strategy and column count before accepting data. `--build-only`
does not open a serial port. An optional `--port COM9` selects a different port.

## Wiring stays the same

All modules share **VCC → 3V3**, **GND → GND**, **SDA → G32**, **SCL → G33**.
Each module's AD0 has its own connection:

| Sensor | AD0 / ADO → ESP32 label |
| --- | --- |
| S1 | G25 |
| S2 | G26 |
| S3 | G27 |
| S4 | G14 |
| S5 | G13 |

Leave G12 unused. Leave sensor INT/XDA/XCL unconnected. All five AD0 outputs
are managed even in the four-sensor profile, so a correctly wired fifth sensor
can remain parked while the four-sensor profile runs. Do not read shared address
0x69 or run the single-sensor wiring probe with multiple sensors attached.

## What changed from FIFO acquisition

- A microsecond timer wakes acquisition every 2 ms. The timer callback only
  signals the acquisition task; I²C and output run outside the callback.
- Each sweep performs one six-byte burst read per sensor at 400 kHz. There are
  no FIFO count/status reads and no sample-count-skew stop.
- One complete row is formatted into a buffer and passed to the asynchronous
  8 KB UART transmit buffer. There are no serial prints between sensor reads.
- A failed read emits `nan,nan,nan,nan` **only in that sensor's group**, then
  retries on the next sweep. Other groups retain their correct positions.
- A sensor that fails initialization remains NaN until you fix it and send
  `start` (or reset) to initialize it again. Address-isolation or timer setup
  failures still refuse acquisition: they cannot produce a trustworthy stream.
- Overdue polling periods are skipped and counted; old values are not used to
  fabricate the missed rows. If UART space is insufficient, the complete output
  row is dropped and counted. Neither condition permanently stops acquisition.

The CSV structure is unchanged: integer `t_ms`, then four comma-separated
values in g per sensor, separated by semicolons. Values have four decimal
places and magnitude is the actual vector norm. Four-sensor firmware has four
groups; five-sensor firmware has five. Lines beginning `#` are diagnostics.

**Timestamp meaning differs from FIFO mode:** `t_ms` is the actual start time
of the sequential read sweep, in milliseconds since ESP boot. It is not a
synthetic 2 ms grid or an exact conversion timestamp. Quantization and task
scheduling can produce 1/3 ms intervals around the 2 ms target. The checker
reports that jitter, flags larger gaps/non-increasing times, and checks
firmware loss counters as well as PC delivery rate.

The sensors still have independent clocks. Latest-register polling can read a
conversion twice or miss a conversion as the clocks drift. **Continuous output
does not establish synchronized or always-distinct sensor measurements.** Use
clean contiguous data for FFTs; do not bridge NaNs/gaps as if sampling remained
uniform. Phase-sensitive analysis needs separate timing characterization.

## Read the result

`CHECK PASSED` means this capture passed the format/delivery checks, with rates
within 5% of target, no missing/invalid rows detected, and zero reported loss
and error counters. It does not certify calibration, timing alignment, or
distinct conversions. `CHECK FAILED` preserves the capture and explains why;
it does **not** send a stop command to the firmware.

Final `# STATS` / `# SENSOR` lines include:

| Field | Meaning |
| --- | --- |
| `observed_hz` in STATS | Complete rows queued for serial per second of ESP time |
| `observed_hz` in SENSOR | Successful register reads per second, not proven unique conversions |
| `read_errors` | Failed/unavailable reads for this sensor; its group becomes NaN |
| `i2c_errors` | Failed I²C transactions during this segment |
| `missed_sweeps` | Expired 2 ms acquisition slots skipped before a later sweep |
| `uart_dropped_rows` | Rows not delivered because UART could not accept a complete row |
| `max_sweep_us` | Largest time spent reading all active sensors |
| `max_cycle_us` | Largest sweep time including formatting/queuing output |
| `max_lateness_us` | Largest delay from the next scheduled acquisition slot |
| `near_limit` | Sensor reads with an axis reaching 98% of ±16 g |

Counters reset on `start`/`resume`. Initialization results appear separately
before streaming. `stats` or `diag` during recording adds serial traffic and
can itself cause a timing gap; the launcher requests statistics at the end of
its measurement. `pause`, `start`, `resume`, and `validate` are also supported.

Five sensors at 500 Hz remain close to this USB-UART link's text throughput
limit: 921600 baud with 8N1 permits at most 92160 payload bytes/s. Sustained
long full-range rows can exceed that. This firmware reports the loss and
continues; it cannot make that physical limit disappear. Four sensors have
more transmission headroom. **Both profiles require a live delivery check on
the assembled rig; compilation is not proof of sustained 500 Hz.**

The nominal sensor configuration is divider 1, DLPF 1 (184 Hz acceleration
bandwidth), ±16 g (2048 counts/g). Compatible WHO_AM_I IDs 0x70/0x72 are accepted
with a warning; their sensitivity/filter behavior has not been established.

## Direct commands and implementation

```powershell
pio run -d Sensors/sensor_rig_esp32_grueni -e grueni_latest4_500hz -t upload --upload-port COM8
python Sensors/sensor_rig_esp32_grueni/tools/check_stream.py --port COM8 --sensors 4 --acquisition latest --seconds 60 --output Sensors/sensor_rig_esp32_grueni/captures/latest4-test.csv
```

Run these direct commands from the repository root. For five sensors substitute
`grueni_latest5_500hz`, `--sensors 5`, and a new capture filename. The checker
never overwrites a capture. For offline review use `--file <capture.csv>` with
the same `--sensors` and `--acquisition latest` options.

Implementation: [`src/latest.cpp`](src/latest.cpp), shared CSV formatting in
[`include/rig_data.h`](include/rig_data.h). The default PlatformIO environment
still selects the original five-sensor FIFO implementation; explicitly select
a latest profile or use its launcher.

Technical references: [MPU-6000/6050 register map, acceleration registers and sample-rate divider](https://cdn.sparkfun.com/datasheets/Sensors/Accelerometers/RM-MPU-6000A.pdf)
and [ESP-IDF 4.4 high-resolution timer](https://docs.espressif.com/projects/esp-idf/en/v4.4.7/esp32/api-reference/system/esp_timer.html).
