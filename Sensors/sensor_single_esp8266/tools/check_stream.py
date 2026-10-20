"""Capture the existing NAMAZU serial format and check one-sensor delivery.

Requires pyserial for live capture; offline inspection uses the standard library.
Firmware timestamps describe nominal sample spacing, so the live check also uses
the PC monotonic clock and the firmware's separately measured observed_hz.
"""
import argparse
import json
import math
from pathlib import Path
import re
import time

HEADER = "t_ms;S1_ax_g,S1_ay_g,S1_az_g,S1_mag_g"
VALUE = r"(?:-?\d+\.\d{4}|nan)"
ROW = re.compile(rf"^(\d+);({VALUE}),({VALUE}),({VALUE}),({VALUE})$")
COUNTERS = ("i2c_errors", "fifo_overflows", "backlog_resets", "faults", "near_limit")


class StreamCheck:
    def __init__(self, rate):
        self.rate = rate
        self.rows = self.invalid = self.malformed = self.discontinuities = 0
        self.magnitude_errors = self.out_of_range = self.fault_messages = 0
        self.restarts = 0
        self.first_ms = self.last_ms = None
        self.first_arrival = self.last_arrival = None
        self.peak_axis_g = 0.0
        self.stats = None

    def add(self, line, arrival=None):
        line = line.strip()
        if line.startswith("# STATS "):
            try:
                stats = dict(item.split("=", 1) for item in line.split()[2:])
                self.stats = {key: float(value) for key, value in stats.items()}
            except ValueError:
                self.malformed += 1
            return
        if line.startswith("# STREAM_FAULT "):
            self.fault_messages += 1
        if self.rows and line.startswith("# NodeMCU ESP8266"):
            self.restarts += 1
        if not line or line == HEADER or line.startswith(("#", "Sensor ", "Mean ", "Validation finished.")):
            return
        match = ROW.fullmatch(line)
        if match is None:
            # ESP8266 boot-ROM output uses a different baud rate. Ignore it only
            # before acquisition starts; corruption mid-capture is a failure.
            if self.rows or line[0].isdigit():
                self.malformed += 1
            return
        stamp = int(match[1])
        values = [float(match[i]) for i in range(2, 6)]
        if self.last_ms is not None and stamp - self.last_ms != 1000 // self.rate:
            self.discontinuities += 1
        if self.first_ms is None:
            self.first_ms = stamp
            self.first_arrival = arrival
        self.last_ms, self.last_arrival = stamp, arrival
        self.rows += 1
        if not all(math.isfinite(value) for value in values):
            self.invalid += 1
            return
        self.peak_axis_g = max(self.peak_axis_g, *(abs(value) for value in values[:3]))
        if any(abs(value) > 16 for value in values[:3]):
            self.out_of_range += 1
        # Four-decimal rounding of the axes and independently computed norm.
        if abs(math.sqrt(sum(value * value for value in values[:3])) - values[3]) > 0.00025:
            self.magnitude_errors += 1

    def report(self):
        elapsed = None
        if self.first_arrival is not None and self.last_arrival is not None:
            elapsed = self.last_arrival - self.first_arrival
        return {
            "expected_hz": self.rate,
            "rows": self.rows,
            "invalid_rows": self.invalid,
            "malformed_lines": self.malformed,
            "timestamp_discontinuities": self.discontinuities,
            "magnitude_errors": self.magnitude_errors,
            "out_of_range_rows": self.out_of_range,
            "fault_messages": self.fault_messages,
            "restarts": self.restarts,
            "peak_axis_g": self.peak_axis_g,
            "pc_elapsed_s": elapsed,
            "pc_observed_hz": (self.rows - 1) / elapsed if elapsed and elapsed > 0 else None,
            "firmware_stats": self.stats,
        }

    def problems(self, minimum_seconds=None):
        result = []
        if self.rows < 2:
            result.append("Fewer than two sample rows received.")
        if any((self.invalid, self.malformed, self.discontinuities, self.magnitude_errors,
                self.out_of_range, self.fault_messages, self.restarts)):
            result.append("Stream contains invalid data, gaps, corruption, or restarts.")
        if self.peak_axis_g >= 15.68:
            result.append("Acceleration reached 98% of the range; inspect possible clipping.")
        if self.stats is None:
            result.append("Missing final STATS response; hardware errors cannot be checked.")
        else:
            for key in COUNTERS:
                if self.stats.get(key) != 0:
                    result.append(f"Firmware {key} is missing or nonzero.")
            rate = self.stats.get("observed_hz", math.nan)
            if not math.isfinite(rate) or abs(rate / self.rate - 1) > 0.05:
                result.append("Firmware-measured delivery rate differs by more than 5%.")
        report = self.report()
        if minimum_seconds is not None:
            elapsed = report["pc_elapsed_s"]
            if elapsed is None or elapsed < minimum_seconds * 0.95:
                result.append("Live capture did not cover the requested interval.")
            rate = report["pc_observed_hz"]
            if rate is None or abs(rate / self.rate - 1) > 0.05:
                result.append("PC-measured delivery rate differs by more than 5%.")
        return result


class Lines:
    """Keep partial serial lines across read timeouts and USB packet boundaries."""
    def __init__(self):
        self.pending = bytearray()

    def feed(self, chunk):
        self.pending.extend(chunk)
        while b"\n" in self.pending:
            line, _, rest = self.pending.partition(b"\n")
            self.pending = rest
            yield line.decode("ascii", errors="replace").rstrip("\r")
        if len(self.pending) > 4096:
            raise ValueError("More than 4096 bytes without a line terminator.")


def capture(args, check):
    import serial
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive creation protects earlier experimental data from overwriting.
    with output.open("x", encoding="utf-8", newline="") as destination:
        with serial.Serial(args.port, 1000000, timeout=0.1, write_timeout=1) as port:
            # Opening some CP2102 boards resets them; startup auto-streams. On an
            # already running/paused board this explicitly starts a new segment.
            port.write(b"start\n")
            lines = Lines()
            startup_deadline = time.monotonic() + 15
            stats_deadline = None
            while True:
                now = time.monotonic()
                if check.first_arrival is None and now > startup_deadline:
                    raise TimeoutError("No samples within 15 s. Check wiring and startup diagnostics.")
                if check.first_arrival is not None and now - check.first_arrival >= args.seconds and stats_deadline is None:
                    check.stats = None
                    port.write(b"stats\n")
                    stats_deadline = now + 2
                chunk = port.read(min(max(port.in_waiting, 1), 8192))
                arrival = time.monotonic()
                for line in lines.feed(chunk):
                    destination.write(line + "\r\n")
                    check.add(line, arrival)
                if stats_deadline is not None and (check.stats is not None or arrival >= stats_deadline):
                    break
            # A final unterminated fragment is not a complete sample and is not
            # counted; capture normally ends on the complete STATS response.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--port", help="Serial port, e.g. COM9; close MATLAB/serial monitors first")
    source.add_argument("--file", help="Inspect a saved capture; PC delivery timing is unavailable")
    parser.add_argument("--rate", type=int, choices=(1000, 500), default=1000)
    parser.add_argument("--seconds", type=float, default=60)
    parser.add_argument("--output", help="New capture filename; existing files are never overwritten")
    args = parser.parse_args()
    if args.port and not args.output:
        parser.error("--port requires --output")
    if not math.isfinite(args.seconds) or args.seconds < 10:
        parser.error("--seconds must be finite and at least 10")
    check = StreamCheck(args.rate)
    try:
        if args.port:
            capture(args, check)
        else:
            with open(args.file, encoding="utf-8", errors="replace") as source_file:
                for line in source_file:
                    check.add(line)
    except (OSError, ValueError, TimeoutError, ImportError) as exc:
        print(f"Capture failed: {exc}")
        print(json.dumps(check.report(), indent=2))
        return 2
    problems = check.problems(args.seconds if args.port else None)
    print(json.dumps(check.report(), indent=2))
    if not args.port:
        print("Offline check: PC delivery rate cannot be verified from nominal timestamps.")
    print("CHECK FAILED" if problems else "CHECK PASSED (delivery/format only; no calibration or frequency-response validation)")
    for problem in problems:
        print("- " + problem)
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
