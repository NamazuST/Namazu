"""Upload four/five-sensor 500 Hz latest-register firmware and record a timed check."""
import argparse
from datetime import datetime
import importlib.util
import subprocess
import sys
from run_two_sensors import PROJECT, run_logged


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sensors", type=int, choices=(4, 5), required=True)
    parser.add_argument("--port", default="COM8")
    parser.add_argument("--seconds", type=int, default=60)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--build-only", action="store_true", help="Compile without opening COM8")
    mode.add_argument("--check-only", action="store_true", help="Check already uploaded latest-register firmware")
    args = parser.parse_args()
    if args.seconds < 10:
        parser.error("--seconds must be at least 10")
    if not args.check_only and importlib.util.find_spec("platformio") is None:
        parser.error("PlatformIO is missing. Use a Run-Latest launcher or PlatformIO's Python.")
    if not args.build_only and importlib.util.find_spec("serial") is None:
        parser.error("pyserial is missing. Use a Run-Latest launcher or PlatformIO's Python.")
    profile = f"grueni_latest{args.sensors}_500hz"
    build = [sys.executable, "-u", "-m", "platformio", "run", "-d", str(PROJECT), "-e", profile]
    if args.build_only:
        return subprocess.run(build, cwd=PROJECT).returncode

    print(f"{args.sensors} sensors on {args.port}: latest-register polling, 500 Hz target, +/-16 g, 921600 baud.", flush=True)
    print("SDA=G32, SCL=G33; AD0 S1=G25 S2=G26 S3=G27 S4=G14 S5=G13.", flush=True)
    print("Close MATLAB/serial monitors; finish wiring with USB disconnected before running this.", flush=True)
    print("Keep the rig still during startup validation. Read errors will not stop acquisition.", flush=True)
    capture_dir = PROJECT / "captures"
    capture_dir.mkdir(exist_ok=True)
    stem = f"bench-latest{args.sensors}-500hz-" + datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    csv = capture_dir / (stem + ".csv")
    report = capture_dir / (stem + ".log")
    print(f"Session log: {report}", flush=True)
    with report.open("x", encoding="utf-8") as log:
        log.write(f"Profile={profile} port={args.port} seconds={args.seconds}\n")
        if not args.check_only:
            result = run_logged(build + ["-t", "upload", "--upload-port", args.port], log)
            if result:
                print("Upload failed; acquisition check was not started. See the session log.")
                return result
        print(f"Recording for {args.seconds} seconds; quality verdict follows at the end.", flush=True)
        command = [sys.executable, "-u", str(PROJECT / "tools" / "check_stream.py"),
                   "--port", args.port, "--sensors", str(args.sensors), "--acquisition", "latest",
                   "--rate", "500", "--baud", "921600", "--seconds", str(args.seconds),
                   "--output", str(csv), "--verbose"]
        result = run_logged(command, log)
    print(f"Capture: {csv}\nSession log: {report}")
    if result:
        print("Quality check failed. Inspect NaN counts, missed_sweeps, uart_dropped_rows, and per-sensor read_errors.")
        print("A failed quality verdict does not instruct the firmware to stop streaming.")
    else:
        print("This run passed delivery checks. Distinct conversions, calibration, and phase alignment are not established.")
    return result


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\nStopped by user. Saved files may be incomplete.")
        raise SystemExit(130)
    except OSError as exc:
        print(f"Could not complete the check: {exc}", file=sys.stderr)
        raise SystemExit(2)
