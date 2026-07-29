# Firmware settings reference

Source of truth: `src/main.cpp`.

Last reviewed against firmware source: 2026-07-27.

## Acquisition settings

| Setting | Current value | Meaning |
| --- | ---: | --- |
| `NUM_SENSORS` | `5` | Number of MPU6050 boards streamed per sample row. |
| `SAMPLE_RATE_HZ` | `250` | Target output sample rate for the full rig. |
| `SAMPLE_INTERVAL_US` | `4000` | Time between full 5-sensor output rows. |
| `SERIAL_BAUD` | `1000000` | Serial stream baud rate. |
| `I2C_CLOCK_HZ` | `400000` | ESP32 I2C bus clock. |
| `PRINT_MAGNITUDE` | `true` | Output `ax`, `ay`, `az`, and `|a|` per sensor. |

At `250 Hz`, the time step is `0.004 s` and the Nyquist frequency is `125 Hz`.

## MPU6050 settings

| Setting | Current value | Meaning |
| --- | ---: | --- |
| `REG_PWR_MGMT_1` reset | `0x80` | Reset each MPU during initialization. |
| `REG_PWR_MGMT_1` wake | `0x01` | Wake using the X-gyro PLL clock source. |
| `MPU_SAMPLE_RATE_DIVIDER` | `3` | With DLPF enabled: `1000 / (1 + 3) = 250 Hz`. |
| `MPU_DLPF_CONFIG` | `1` | Digital low-pass filter setting, high bandwidth for vibration work. |
| `ACCEL_FULL_SCALE_G` | `8` | Accelerometer full-scale range is `+-8 g`. |
| `MPU_ACCEL_CONFIG` | `0x10` | Register value for `+-8 g`. |
| `ACCEL_SCALE_LSB_PER_G` | `4096` | Conversion factor for `+-8 g`. |
| accepted `WHO_AM_I` values | `0x68`, `0x70`, `0x72` | MPU6050 and common compatible modules. |

For impact tests, watch for any axis approaching about `+-8 g`; that indicates
the MPU6050 acceleration range is close to saturation.

Acceleration range tradeoff:

| Range | `MPU_ACCEL_CONFIG` | `ACCEL_SCALE_LSB_PER_G` | Use when |
| --- | ---: | ---: | --- |
| `+-2 g` | `0x00` | `16384` | Best resolution, only for very gentle motion. |
| `+-4 g` | `0x08` | `8192` | Good default for light impacts; clipped with the heavy hammer. |
| `+-8 g` | `0x10` | `4096` | Recommended current hammer-test setting. |
| `+-16 g` | `0x18` | `2048` | Maximum headroom, but lowest acceleration resolution. |

Changing to a wider range reduces sensitivity in LSB/g. For modal frequency
estimation this is usually a good trade when the old range clips, because
clipping distorts the signal more severely than the moderate loss of resolution.

## ESP32 pin settings

| Setting | Current value | Meaning |
| --- | ---: | --- |
| `I2C_SDA_PIN` | `21` | Shared SDA line for all sensors. |
| `I2C_SCL_PIN` | `22` | Shared SCL line for all sensors. |
| `AD0_PINS` | `{13, 14, 25, 26, 27}` | Sensor-select pins for sensors 1-5. |
| `AD0_SETTLE_US` | `20` | Delay after switching AD0 lines before reading. |

The selected sensor is pulled low and read at I2C address `0x68`. All other
sensors are parked high at address `0x69`.

## Startup and diagnostics

| Setting | Current value | Meaning |
| --- | ---: | --- |
| `RUN_I2C_DIAGNOSTIC` | `true` | Print AD0/I2C address diagnostic on boot. |
| `RUN_STATIC_VALIDATION` | `true` | Print static mean acceleration values on boot. |
| `STARTUP_LOG_HOLD_MS` | `3000` | Hold startup log for 3 seconds before live rows. |
| `WAIT_FOR_START_COMMAND` | `false` | If `true`, live stream waits for serial command `start`. |

Available serial commands during live output:

```text
diag
validate
pause
resume
start
```

## PlatformIO settings

| Setting | Current value |
| --- | ---: |
| PlatformIO environment | `esp32dev` |
| Framework | `arduino` |
| Monitor speed | `1000000` |
| Upload speed | `921600` |
