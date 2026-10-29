import unittest
import tempfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
from check_stream import HEADER, Lines, StreamCheck, capture, header


def row(ms, group="0.0000,0.0000,1.0000,1.0000", sensor_count=5):
    return str(ms) + (";" + group) * sensor_count


def stats(check, rate=500):
    check.add(f"# STATS streaming=1 observed_hz={rate} i2c_errors=0 fifo_overflows=0 faults=0 near_limit=0")
    for i in range(1, check.sensor_count + 1):
        check.add(f"# SENSOR id={i} who=0x68 frames=5001 observed_hz={rate}")


class StreamTests(unittest.TestCase):
    def good(self, rate=500, sensor_count=5):
        check = StreamCheck(rate, sensor_count)
        check.add(check.header)
        for i in range(10000 // check.period_ms + 1):
            check.add(row(i * check.period_ms, sensor_count=sensor_count), i * check.period_ms / 1000)
        stats(check, check.rate)
        return check

    def test_clean_five_sensor_profiles(self):
        for rate in (500, 333, 250):
            check = self.good(rate)
            self.assertEqual(check.problems(10), [])
            self.assertAlmostEqual(check.report()["pc_observed_hz"], check.rate)

    def test_clean_single_sensor_profile(self):
        check = self.good(sensor_count=1)
        self.assertEqual(check.problems(10), [])
        self.assertEqual(check.header, "t_ms;S1_ax_g,S1_ay_g,S1_az_g,S1_mag_g")
        self.assertEqual(check.report()["expected_sensors"], 1)
        self.assertEqual(check.peaks, [1.0])

    def test_two_sensors_require_both_groups_and_statistics(self):
        check = self.good(sensor_count=2)
        self.assertEqual(check.problems(10), [])
        self.assertEqual(len(check.peaks), 2)
        check.add(row(10002, sensor_count=1))
        self.assertEqual(check.malformed, 1)
        del check.sensors[2]
        self.assertTrue(any("statistics" in issue for issue in check.problems()))

    def test_single_sensor_check_rejects_five_sensor_stream(self):
        check = self.good(sensor_count=1)
        check.add(HEADER)
        check.add(row(10002))
        check.add("# SENSOR id=2 who=0x68 frames=5001 observed_hz=500")
        self.assertEqual(check.malformed, 3)
        self.assertTrue(check.problems())

    def test_sensor_count_must_be_supported(self):
        for count in (0, 6):
            with self.assertRaises(ValueError):
                StreamCheck(500, count)

    def test_split_usb_packets(self):
        decoder = Lines()
        data = (row(100) + "\r\n" + row(102) + "\r\n").encode()
        result = []
        for byte in data:
            result.extend(decoder.feed(bytes([byte])))
        self.assertEqual(result, [row(100), row(102)])

    def test_all_twenty_values_and_group_delimiters_required(self):
        check = self.good()
        check.add("10002;0.0000,0.0000,1.0000,1.0000")
        check.add(row(10004).replace(";", ","))
        self.assertEqual(check.malformed, 2)
        self.assertTrue(check.problems())

    def test_corruption_and_incomplete_numbers(self):
        check = self.good()
        check.add(row(10002).replace("1.0000", "1.000x", 1))
        check.add(row(10004) + "\x90")
        self.assertEqual(check.malformed, 2)

    def test_one_sensor_nan_invalidates_capture(self):
        check = self.good()
        check.add(row(10002).replace("0.0000,0.0000,1.0000,1.0000", "nan,nan,nan,nan", 1))
        self.assertEqual(check.invalid, 1)
        self.assertTrue(check.problems())

    def test_missing_duplicate_and_reversed_time(self):
        check = self.good()
        for ms in (10004, 10004, 10002):
            check.add(row(ms))
        self.assertEqual(check.gaps, 3)

    def test_true_magnitude_for_each_sensor(self):
        check = StreamCheck(500)
        check.add(row(0, "1.0000,2.0000,2.0000,3.0000"))
        self.assertEqual(check.magnitude_errors, 0)
        check.add(row(2, "1.0000,2.0000,2.0000,0.0000"))
        self.assertEqual(check.magnitude_errors, 5)

    def test_clipping_is_detected_even_with_valid_format(self):
        check = self.good()
        check.add(row(10002, "-16.0000,0.0000,0.0000,16.0000"))
        self.assertEqual(check.range_errors, 0)
        self.assertTrue(any("clipping" in problem for problem in check.problems()))

    def test_fault_pause_restart_and_missing_sensor_statistics(self):
        check = self.good()
        check.add("# STREAM_FAULT reason=fifo_overflow sensor=3")
        check.add("# STREAM_BREAK reason=pause sensor=0")
        check.add("# Streaming")
        del check.sensors[3]
        self.assertEqual(check.faults, 2)
        self.assertEqual(check.restarts, 1)
        self.assertTrue(check.problems())

    def test_pc_clock_exposes_slow_delivery_despite_nominal_timestamps(self):
        check = self.good()
        check.last_arrival = 20
        self.assertTrue(any("PC delivery" in problem for problem in check.problems(10)))
        check.sensors[4] = float("nan")
        self.assertTrue(any("statistics for" in problem for problem in check.problems()))

    def test_diagnostic_banner_is_not_a_restart(self):
        check = self.good()
        check.add("# ESP32 GRUENI five-sensor FIFO rig")
        self.assertEqual(check.restarts, 0)
        self.assertEqual(check.problems(10), [])

    def test_nonzero_or_missing_firmware_counters_fail(self):
        check = self.good()
        check.stats["fifo_overflows"] = 1
        self.assertTrue(check.problems())
        check.stats = None
        self.assertTrue(check.problems())

    def test_unterminated_stream_is_bounded(self):
        with self.assertRaises(ValueError):
            list(Lines().feed(b"x" * 4097))

    def test_capture_ignores_startup_ack_and_queued_old_data(self):
        for sensor_count in (1, 2, 5):
            with self.subTest(sensor_count=sensor_count):
                self.capture_case(sensor_count)

    def test_capture_rejects_wrong_firmware_before_recording(self):
        with self.assertRaisesRegex(RuntimeError, "Firmware header does not match 2"):
            self.capture_case(2, stream_count=1)

    def latest(self, sensor_count=4):
        check = StreamCheck(500, sensor_count, "latest")
        check.add("# acquisition=latest")
        for i in range(5001):
            # Real 2 ms sweeps with sub-millisecond scheduling jitter can yield
            # alternating 1/3 ms integer timestamps, with no lost output rows.
            check.add(row(i * 2 + i % 2, sensor_count=sensor_count), i / 500)
        check.add("# STATS streaming=1 observed_hz=500 i2c_errors=0 missed_sweeps=0 "
                  "uart_dropped_rows=0 format_errors=0 near_limit=0")
        for i in range(1, sensor_count + 1):
            check.add(f"# SENSOR id={i} who=0x72 frames=5001 observed_hz=500 read_errors=0 configured=1")
        return check

    def test_latest_four_and_five_accept_quantized_timing_jitter(self):
        for count in (4, 5):
            check = self.latest(count)
            self.assertEqual(check.problems(10), [])
            self.assertEqual(check.gaps, 0)
            self.assertEqual(check.jitter_intervals, 5000)
            self.assertEqual((check.min_interval_ms, check.max_interval_ms), (1, 3))

    def test_latest_rejects_gaps_duplicate_and_backward_time(self):
        check = self.latest()
        for stamp in (10004, 10004, 10002):
            check.add(row(stamp, sensor_count=4))
        self.assertEqual(check.gaps, 3)
        self.assertTrue(check.problems())

    def test_latest_nan_marks_only_failed_sensor_and_later_rows_are_kept(self):
        check = self.latest()
        bad = row(10002, sensor_count=4).split(";")
        bad[2] = "nan,nan,nan,nan"
        check.add(";".join(bad))
        check.add(row(10004, sensor_count=4))
        self.assertEqual(check.rows, 5003)
        self.assertEqual(check.invalid_per_sensor, [0, 1, 0, 0])
        self.assertEqual((check.gaps, check.faults), (0, 0))
        self.assertTrue(check.problems())

    def test_latest_loss_counters_fail_even_if_timestamps_look_continuous(self):
        for key in ("missed_sweeps", "uart_dropped_rows", "format_errors", "i2c_errors"):
            check = self.latest()
            check.stats[key] = 1
            self.assertTrue(check.problems())
            del check.stats[key]
            self.assertTrue(check.problems())

    def test_latest_requires_identification_and_per_sensor_read_health(self):
        check = self.latest()
        check.acquisition_seen = None
        self.assertTrue(any("identification" in issue for issue in check.problems()))
        check.acquisition_seen = "latest"
        check.add("# SENSOR id=4 who=0x72 frames=5001 observed_hz=500 read_errors=0 configured=0")
        self.assertTrue(any("Unconfigured" in issue for issue in check.problems()))

    def test_latest_capture_continues_through_nan_for_four_and_five(self):
        for count in (4, 5):
            check = self.capture_case(count, acquisition="latest", nan_once=True)
            self.assertEqual(check.invalid, 1)
            self.assertGreater(check.rows, 1)
            self.assertEqual(check.acquisition_seen, "latest")

    def test_capture_rejects_wrong_strategy_even_when_sensor_count_matches(self):
        for expected, actual in (("latest", "fifo"), ("fifo", "latest")):
            with self.assertRaisesRegex(RuntimeError, "Firmware acquisition does not match"):
                self.capture_case(5, acquisition=expected, stream_acquisition=actual)

    def capture_case(self, sensor_count, stream_count=None, acquisition="fifo", stream_acquisition=None, nan_once=False):
        if stream_count is None:
            stream_count = sensor_count
        if stream_acquisition is None:
            stream_acquisition = acquisition
        clock = SimpleNamespace(value=0.0)
        class Port:
            in_waiting = 1000
            def __init__(self):
                self.chunks, self.commands = [], []
                self.stamp = 100
                self.buffer_request = None
            def __enter__(self):
                return self
            def __exit__(self, *args):
                return False
            def reset_input_buffer(self):
                pass
            def set_buffer_size(self, **kwargs):
                self.buffer_request = kwargs
            def write(self, command):
                self.commands.append(command)
                if command == b"pause\n":
                    self.chunks.append(("# Streaming\n" + row(99999, sensor_count=sensor_count) +
                                        "\n# STREAM_BREAK reason=pause\n# Paused\n").encode())
                elif command == b"start\n":
                    mode_line = "# acquisition=latest\n" if stream_acquisition == "latest" else ""
                    self.chunks.append((mode_line + header(stream_count) + "\n# Streaming\n").encode())
                elif command == b"stats\n":
                    lines = ["# STATS streaming=1 observed_hz=500 i2c_errors=0 fifo_overflows=0 faults=0 near_limit=0"]
                    if acquisition == "latest":
                        lines = ["# STATS streaming=1 observed_hz=500 i2c_errors=0 missed_sweeps=0 uart_dropped_rows=0 format_errors=0 near_limit=0"]
                    lines += [f"# SENSOR id={i} who=0x68 frames=3 observed_hz=500 read_errors=0 configured=1" for i in range(1, sensor_count + 1)]
                    self.chunks.append(("\n".join(lines) + "\n").encode())
            def read(self, _):
                clock.value += 6
                if self.chunks:
                    return self.chunks.pop(0)
                line = row(self.stamp, sensor_count=sensor_count)
                if nan_once and self.stamp == 100:
                    line = line.replace("0.0000,0.0000,1.0000,1.0000", "nan,nan,nan,nan", 1)
                data = (line + "\n").encode()
                self.stamp += 2
                return data
        port = Port()
        with tempfile.TemporaryDirectory() as directory:
            args = SimpleNamespace(output=str(Path(directory)/"capture.csv"), port="TEST", baud=921600, seconds=10)
            check = StreamCheck(500, sensor_count, acquisition)
            with patch.dict("sys.modules", {"serial": SimpleNamespace(Serial=lambda *a, **kw: port)}), \
                    patch("check_stream.time.sleep"), \
                    patch("check_stream.time.monotonic", side_effect=lambda: clock.value):
                capture(args, check)
            self.assertEqual(port.commands, [b"pause\n", b"start\n", b"stats\n"])
            self.assertEqual(port.buffer_request, dict(rx_size=262144, tx_size=4096))
            self.assertEqual(check.first_ms, 100)
            self.assertEqual((check.gaps, check.faults, check.restarts, check.malformed), (0, 0, 0, 0))
            self.assertEqual(len(check.sensors), sensor_count)
            self.assertEqual(Path(args.output).read_text().splitlines()[0], check.header)
            self.assertNotIn("99999", Path(args.output).read_text())
        return check


if __name__ == "__main__":
    unittest.main()
