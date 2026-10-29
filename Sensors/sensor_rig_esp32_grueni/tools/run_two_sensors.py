"""Upload the two-sensor profile and save a timed acquisition check on Windows."""
import argparse
from datetime import datetime
import importlib.util
from pathlib import Path
import subprocess
import sys

PROJECT = Path(__file__).resolve().parents[1]
PROFILE = "grueni_s2_500hz"


def run_logged(command, log):
    """Keep progress visible and retain diagnostics, including failures."""
    with subprocess.Popen(command, cwd=PROJECT, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, text=True, encoding="utf-8",
                          errors="replace") as process:
        try:
            for line in process.stdout:
                print(line, end="", flush=True)
                log.write(line)
                log.flush()
            return process.wait()
        except KeyboardInterrupt:
            process.terminate()
            process.wait()
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", default="COM8")
    parser.add_argument("--seconds", type=int, default=60)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check-only", action="store_true", help="Check the already uploaded two-sensor firmware")
    mode.add_argument("--build-only", action="store_true", help="Compile without accessing a serial port")
    args = parser.parse_args()
    if args.seconds < 10:
        parser.error("--seconds must be at least 10")
    if not args.check_only and importlib.util.find_spec("platformio") is None:
        parser.error("PlatformIO is missing from this Python. Use Run-Two-Sensors.cmd or PlatformIO's Python.")
    if not args.build_only and importlib.util.find_spec("serial") is None:
        parser.error("pyserial is missing from this Python. Use Run-Two-Sensors.cmd or PlatformIO's Python.")

    build = [sys.executable, "-u", "-m", "platformio", "run", "-d", str(PROJECT), "-e", PROFILE]
    if args.build_only:
        return subprocess.run(build, cwd=PROJECT).returncode

    print(f"Two GY-521 sensors on {args.port}: 500 samples/s each, +/-16 g, 921600 baud.", flush=True)
    print("Shared VCC=3V3, GND=GND, SDA=G32, SCL=G33; S1 AD0=G25, S2 AD0=G26.", flush=True)
    print("Close MATLAB/serial monitors. Keep both sensors still for startup validation.", flush=True)
    capture_dir = PROJECT / "captures"
    capture_dir.mkdir(exist_ok=True)
    stem = "bench-s2-500hz-" + datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    csv = capture_dir / (stem + ".csv")
    report = capture_dir / (stem + ".log")
    print(f"Session log: {report}", flush=True)

    with report.open("x", encoding="utf-8") as log:
        log.write(f"Profile={PROFILE} port={args.port} seconds={args.seconds}\n")
        if not args.check_only:
            print("Building and uploading the two-sensor firmware...", flush=True)
            result = run_logged(build + ["-t", "upload", "--upload-port", args.port], log)
            if result:
                print("Upload failed; the acquisition check was not started. See the session log.")
                return result
        print(f"Recording {args.seconds} seconds. Progress and the final verdict follow.", flush=True)
        command = [sys.executable, "-u", str(PROJECT / "tools" / "check_stream.py"),
                   "--port", args.port, "--sensors", "2", "--rate", "500", "--baud", "921600",
                   "--seconds", str(args.seconds), "--output", str(csv), "--verbose"]
        result = run_logged(command, log)

    print(f"Capture: {csv}")
    print(f"Session log: {report}")
    if result:
        print("CHECK FAILED: inspect the diagnostics above. Close other port users; check both sensors' wiring.")
        print("A sample_count_skew fault indicates diverging sample counts; keep this protection enabled.")
    else:
        print("Both sensor streams passed this delivery check. Calibration and phase alignment are separate checks.")
    return result


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\nStopped by user. Any saved log/capture may be incomplete.")
        raise SystemExit(130)
    except OSError as exc:
        print(f"Could not complete the check: {exc}", file=sys.stderr)
        raise SystemExit(2)
