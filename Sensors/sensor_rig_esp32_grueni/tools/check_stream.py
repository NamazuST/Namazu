"""Check rig CSV integrity and actual delivery; never infer rate solely from t_ms."""
import argparse
import json
import math
from pathlib import Path
import re
import time

def header(sensor_count=5):
    return "t_ms" + "".join(f";S{i}_ax_g,S{i}_ay_g,S{i}_az_g,S{i}_mag_g" for i in range(1, sensor_count + 1))


HEADER = header()
NUMBER = r"(?:-?\d+\.\d{4}|nan)"
GROUP = re.compile(rf"^({NUMBER}),({NUMBER}),({NUMBER}),({NUMBER})$")


class Lines:
    def __init__(self):
        self.pending = bytearray()

    def feed(self, chunk):
        self.pending.extend(chunk)
        while b"\n" in self.pending:
            line, _, self.pending = self.pending.partition(b"\n")
            yield line.rstrip(b"\r").decode("ascii", errors="replace")
        if len(self.pending) > 4096:
            raise ValueError("Over 4096 bytes without LF; check the baud setting.")


def fields(line):
    return dict(item.split("=", 1) for item in line.split()[2:])


class StreamCheck:
    def __init__(self, rate, sensor_count=5, acquisition="fifo"):
        if sensor_count not in range(1, 6):
            raise ValueError("Sensor count must be 1..5")
        self.sensor_count = sensor_count
        if acquisition not in ("fifo", "latest"):
            raise ValueError("Acquisition must be fifo or latest")
        self.acquisition = acquisition
        self.acquisition_seen = None
        self.header = header(sensor_count)
        self.period_ms = {500: 2, 333: 3, 250: 4}[rate]
        self.rate = 1000 / self.period_ms
        self.rows = self.malformed = self.invalid = self.gaps = self.faults = 0
        self.magnitude_errors = self.range_errors = self.restarts = 0
        self.first_ms = self.last_ms = self.first_arrival = self.last_arrival = None
        self.peaks = [0.0] * sensor_count
        self.stats = None
        self.sensors = {}
        self.sensor_read_errors = {}
        self.invalid_per_sensor = [0] * sensor_count
        self.jitter_intervals = 0
        self.min_interval_ms = self.max_interval_ms = None

    def add(self, line, arrival=None):
        if any(ord(c) < 32 or ord(c) > 126 for c in line):
            self.malformed += 1
            return
        if line.startswith("# acquisition="):
            self.acquisition_seen = line.split()[1].split("=", 1)[1]
            if self.acquisition_seen != self.acquisition:
                self.malformed += 1
            return
        if line.startswith("# STATS "):
            try:
                self.stats = {key: float(value) for key, value in fields(line).items()}
            except ValueError:
                self.malformed += 1
            return
        if line.startswith("# SENSOR "):
            try:
                values = fields(line)
                sensor = int(values["id"])
                if sensor not in range(1, self.sensor_count + 1):
                    raise ValueError("Invalid sensor ID")
                self.sensors[sensor] = float(values["observed_hz"])
                if self.acquisition == "latest":
                    self.sensor_read_errors[sensor] = float(values["read_errors"])
                    if values.get("configured") != "1":
                        self.sensor_read_errors[sensor] = math.inf
            except (ValueError, KeyError):
                self.malformed += 1
            return
        if line.startswith(("# STREAM_FAULT", "# STREAM_BREAK")):
            self.faults += 1
        # 'diag' repeats the banner without restarting. A new Streaming
        # acknowledgement identifies a new segment; timestamps also catch resets.
        if self.rows and line == "# Streaming":
            self.restarts += 1
        if not line or line == self.header or line.startswith("#"):
            return
        parts = line.split(";")
        if len(parts) != self.sensor_count + 1 or not re.fullmatch(r"\d+", parts[0]):
            self.malformed += 1
            return
        matches = [GROUP.fullmatch(group) for group in parts[1:]]
        if not all(matches):
            self.malformed += 1
            return
        stamp = int(parts[0])
        if self.last_ms is not None:
            interval = stamp - self.last_ms
            self.min_interval_ms = interval if self.min_interval_ms is None else min(interval, self.min_interval_ms)
            self.max_interval_ms = interval if self.max_interval_ms is None else max(interval, self.max_interval_ms)
            if interval != self.period_ms:
                self.jitter_intervals += 1
            # Latest mode reports real sweep time, rounded down to milliseconds.
            # 1/3 ms intervals can surround a 2 ms target. Firmware counters also
            # detect skipped slots, including losses hidden by quantization.
            if (self.acquisition == "fifo" and interval != self.period_ms or
                    self.acquisition == "latest" and (interval <= 0 or interval > self.period_ms + 1)):
                self.gaps += 1
        if self.first_ms is None:
            self.first_ms, self.first_arrival = stamp, arrival
        self.last_ms, self.last_arrival = stamp, arrival
        self.rows += 1
        for i, match in enumerate(matches):
            values = [float(value) for value in match.groups()]
            if not all(math.isfinite(value) for value in values):
                self.invalid += 1
                self.invalid_per_sensor[i] += 1
                continue
            self.peaks[i] = max(self.peaks[i], *(abs(value) for value in values[:3]))
            if any(abs(value) > 16 for value in values[:3]):
                self.range_errors += 1
            if abs(math.sqrt(sum(value * value for value in values[:3])) - values[3]) > .00025:
                self.magnitude_errors += 1

    def report(self):
        elapsed = None if self.first_arrival is None else self.last_arrival - self.first_arrival
        return dict(acquisition=self.acquisition, expected_sensors=self.sensor_count, expected_hz_per_sensor=self.rate, rows=self.rows, malformed_lines=self.malformed,
                    invalid_sensor_groups=self.invalid, timestamp_discontinuities=self.gaps,
                    invalid_groups_per_sensor=self.invalid_per_sensor, non_nominal_intervals=self.jitter_intervals,
                    min_interval_ms=self.min_interval_ms, max_interval_ms=self.max_interval_ms,
                    fault_messages=self.faults, restarts=self.restarts, magnitude_errors=self.magnitude_errors,
                    range_errors=self.range_errors, peak_axis_g_per_sensor=self.peaks,
                    pc_elapsed_s=elapsed, pc_observed_hz=(self.rows-1)/elapsed if elapsed and elapsed > 0 else None,
                    firmware_stats=self.stats, sensor_observed_hz=self.sensors,
                    sensor_read_errors=self.sensor_read_errors)

    def problems(self, seconds=None):
        issues = []
        if self.rows < 2 or any((self.malformed, self.invalid, self.gaps, self.faults,
                                 self.restarts, self.magnitude_errors, self.range_errors)):
            issues.append("Invalid, missing, corrupted, or interrupted data.")
        if max(self.peaks) >= 15.68:
            issues.append("At least one sensor approached clipping (98% of range).")
        if self.stats is None:
            issues.append("Missing final firmware statistics.")
        else:
            counters = ("i2c_errors", "fifo_overflows", "faults", "near_limit") if self.acquisition == "fifo" else (
                "i2c_errors", "missed_sweeps", "uart_dropped_rows", "format_errors", "near_limit")
            if any(self.stats.get(key) != 0 for key in counters):
                issues.append("Nonzero or missing firmware error/near-limit counters.")
            if self.stats.get("streaming") != 1:
                issues.append("Firmware is not streaming.")
            measured = self.stats.get("observed_hz", math.nan)
            if not math.isfinite(measured) or abs(measured / self.rate - 1) > .05:
                issues.append("Firmware delivery differs from target by more than 5%.")
        if set(self.sensors) != set(range(1, self.sensor_count + 1)) or any(
                not math.isfinite(value) or abs(value / self.rate - 1) > .05 for value in self.sensors.values()):
            issues.append("Missing or out-of-tolerance delivery statistics for one or more sensors.")
        if self.acquisition == "latest":
            if self.acquisition_seen != "latest":
                issues.append("Missing latest-acquisition identification; check the uploaded profile.")
            if set(self.sensor_read_errors) != set(range(1, self.sensor_count + 1)) or any(
                    value != 0 for value in self.sensor_read_errors.values()):
                issues.append("Unconfigured sensors or nonzero/missing per-sensor read-error counters.")
        if seconds is not None:
            report = self.report()
            elapsed, measured = report["pc_elapsed_s"], report["pc_observed_hz"]
            if elapsed is None or elapsed < .95 * seconds:
                issues.append("Capture did not cover the requested interval.")
            if measured is None or abs(measured / self.rate - 1) > .05:
                issues.append("PC delivery differs from target by more than 5%.")
        return issues


def capture(args, check):
    import serial
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x", encoding="utf-8", newline="") as destination:
        with serial.Serial(args.port, args.baud, timeout=.1, write_timeout=1) as port:
            # pyserial's Windows default requests only 4096 bytes. Request more
            # headroom for PC scheduling pauses; Windows drivers may ignore it.
            # This does not replace the checks for truncated rows/missing data.
            request_buffer = getattr(port, "set_buffer_size", None)
            if request_buffer is not None:
                request_buffer(rx_size=262144, tx_size=4096)
            # USB-open may reset the board. Pause/ack/start/ack avoids accepting
            # startup's Streaming message before the queued start command runs.
            time.sleep(1)
            port.reset_input_buffer()
            port.write(b"pause\n")
            phase = "pause"
            stream_acquisition = None
            deadline = time.monotonic() + 30
            stats_deadline = None
            lines = Lines()
            while True:
                now = time.monotonic()
                if check.first_arrival is None and now > deadline:
                    raise TimeoutError("No acknowledged data stream in 30 s; inspect baud/wiring/diagnostics.")
                if check.first_arrival is not None and stats_deadline is None and now-check.first_arrival >= args.seconds:
                    check.stats = None
                    check.sensors.clear()
                    check.sensor_read_errors.clear()
                    port.write(b"stats\n")
                    stats_deadline = now + 3
                chunk = port.read(min(max(port.in_waiting, 1), 16384))
                arrival = time.monotonic()
                for line in lines.feed(chunk):
                    if phase != "capture" and getattr(args, "verbose", False):
                        if line.startswith(("#", "Sensor ", "Mean ", "Validation finished")):
                            # Keep diagnostics printable even on a legacy Windows
                            # console when a corrupted byte decoded as U+FFFD.
                            print(line.encode("ascii", errors="backslashreplace").decode("ascii"), flush=True)
                    if phase == "pause":
                        if line.startswith("# STREAM_FAULT"):
                            raise RuntimeError(line)
                        if line == "# Paused":
                            port.write(b"start\n")
                            phase = "start"
                        continue
                    if phase == "start":
                        if line.startswith("# STREAM_FAULT"):
                            raise RuntimeError(line)
                        if line.startswith("t_ms;") and line != check.header:
                            raise RuntimeError(
                                f"Firmware header does not match {check.sensor_count} expected sensor(s). "
                                "Upload the matching profile or change --sensors.")
                        if line.startswith("# acquisition="):
                            stream_acquisition = line.split()[1].split("=", 1)[1]
                        if line != "# Streaming":
                            continue
                        if (stream_acquisition or "fifo") != check.acquisition:
                            raise RuntimeError(f"Firmware acquisition does not match {check.acquisition}; upload the matching profile.")
                        phase = "capture"
                        destination.write(check.header + "\r\n")
                        if stream_acquisition:
                            identification = "# acquisition=" + stream_acquisition
                            destination.write(identification + "\r\n")
                            check.add(identification)
                        if request_buffer is not None:
                            destination.write("# HOST rx_buffer_request_bytes=262144 driver_may_ignore=1\r\n")
                    destination.write(line + "\r\n")
                    check.add(line, arrival)
                if stats_deadline is not None and (
                        check.stats is not None and len(check.sensors) == check.sensor_count or arrival >= stats_deadline):
                    break
                if phase == "capture" and check.faults and stats_deadline is None:
                    # A stopped board cannot reach a duration deadline; report it.
                    port.write(b"stats\n")
                    stats_deadline = arrival + 3


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--port")
    source.add_argument("--file")
    parser.add_argument("--rate", type=int, choices=(500, 333, 250), default=500,
                        help="333 selects the exact 1000/3 Hz profile (3 ms spacing)")
    parser.add_argument("--baud", type=int, default=921600)
    parser.add_argument("--acquisition", choices=("fifo", "latest"), default="fifo",
                        help="latest accepts real sweep-time jitter and checks polling loss/read counters")
    parser.add_argument("--sensors", type=int, choices=range(1, 6), default=5,
                        help="Expected groups: 1 for grueni_s1_500hz, 2 for grueni_s2_500hz, default 5")
    parser.add_argument("--verbose", action="store_true", help="Show startup/initialization diagnostics")
    parser.add_argument("--seconds", type=float, default=60)
    parser.add_argument("--output", help="New capture path, never overwritten")
    args = parser.parse_args()
    if args.port and not args.output:
        parser.error("--port requires --output")
    if not math.isfinite(args.seconds) or args.seconds < 10:
        parser.error("--seconds must be finite and >=10")
    check = StreamCheck(args.rate, args.sensors, args.acquisition)
    try:
        if args.port:
            capture(args, check)
        else:
            with open(args.file, encoding="utf-8", errors="replace") as source_file:
                for line in source_file:
                    check.add(line.rstrip("\r\n"))
    except (OSError, ValueError, RuntimeError, ImportError) as exc:
        print(f"Capture failed: {exc}")
        print(json.dumps(check.report(), indent=2))
        return 2
    issues = check.problems(args.seconds if args.port else None)
    print(json.dumps(check.report(), indent=2))
    print("CHECK FAILED" if issues else "CHECK PASSED (delivery/format only, not inter-sensor synchronization or calibration)")
    for issue in issues:
        print("- " + issue)
    if args.acquisition == "latest":
        print("Latest mode counts register reads, not guaranteed distinct sensor conversions. NaNs do not stop capture.")
    if not args.port:
        print("Offline data cannot establish PC delivery timing.")
    return int(bool(issues))


if __name__ == "__main__":
    raise SystemExit(main())
