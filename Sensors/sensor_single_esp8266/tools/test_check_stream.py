import unittest

from check_stream import Lines, StreamCheck

STATS = "# STATS samples=60001 i2c_errors=0 fifo_overflows=0 backlog_resets=0 faults=0 near_limit=0 max_fifo_bytes=18 observed_hz=1000.00"


class StreamTests(unittest.TestCase):
    def good_capture(self):
        check = StreamCheck(1000)
        for i in range(10001):
            check.add(f"{i};0.0000,0.0000,1.0000,1.0000", i / 1000)
        check.add(STATS)
        return check

    def test_clean_capture_ignores_diagnostics(self):
        check = self.good_capture()
        check.add("# Streaming")
        self.assertEqual(check.problems(10), [])
        self.assertEqual(check.report()["pc_observed_hz"], 1000)

    def test_partial_usb_chunks_preserve_rows(self):
        lines = Lines()
        self.assertEqual(list(lines.feed(b"10;0.0000,0.")), [])
        self.assertEqual(list(lines.feed(b"0000,1.0000,1.0000\r")), [])
        self.assertEqual(list(lines.feed(b"\n11;nan,nan,nan,nan\r\n12;")),
                         ["10;0.0000,0.0000,1.0000,1.0000", "11;nan,nan,nan,nan"])
        self.assertEqual(lines.pending, b"12;")

    def test_gaps_duplicates_and_nan_are_rejected(self):
        check = StreamCheck(1000)
        for row in ("100;0.0000,0.0000,1.0000,1.0000", "102;nan,nan,nan,nan", "102;0.0000,0.0000,1.0000,1.0000"):
            check.add(row)
        check.add(STATS)
        self.assertEqual(check.discontinuities, 2)
        self.assertEqual(check.invalid, 1)
        self.assertTrue(check.problems())

    def test_fifo_fault_and_short_csv_fail(self):
        check = self.good_capture()
        check.add("10001;0.0000,1.0000")
        check.add("# STREAM_FAULT fifo_overflow; next stream segment will be re-anchored")
        check.add(STATS.replace("fifo_overflows=0", "fifo_overflows=1"))
        self.assertEqual(check.malformed, 1)
        self.assertEqual(check.fault_messages, 1)
        self.assertTrue(check.problems())

    def test_nominal_timestamps_do_not_prove_delivery_rate(self):
        check = self.good_capture()
        check.last_arrival = 20  # Nominal CSV still implies 1000 Hz, PC sees 500.
        self.assertTrue(any("PC-measured" in issue for issue in check.problems(10)))
        check.add(STATS.replace("1000.00", "500.00"))
        self.assertTrue(any("Firmware-measured" in issue for issue in check.problems()))

    def test_full_scale_negative_axis_and_actual_magnitude(self):
        check = StreamCheck(1000)
        check.add("0;-16.0000,0.0000,0.0000,16.0000")
        check.add("1;1.0000,2.0000,2.0000,3.0000")
        self.assertEqual(check.out_of_range, 0)
        self.assertEqual(check.magnitude_errors, 0)
        check.add("2;1.0000,2.0000,2.0000,0.0000")
        self.assertEqual(check.magnitude_errors, 1)
        self.assertTrue(any("clipping" in issue for issue in check.problems()))

    def test_500_hz_uses_two_ms_spacing(self):
        check = StreamCheck(500)
        check.add("0;0.0000,0.0000,1.0000,1.0000")
        check.add("2;0.0000,0.0000,1.0000,1.0000")
        check.add(STATS.replace("1000.00", "500.00"))
        self.assertEqual(check.problems(), [])

    def test_reboot_and_corrupt_line_are_failures(self):
        check = self.good_capture()
        check.add("# NodeMCU ESP8266 single MPU6050 FIFO acceleration rig")
        check.add("corrupt serial bytes")
        self.assertEqual(check.restarts, 1)
        self.assertEqual(check.malformed, 1)
        self.assertTrue(check.problems())

    def test_missing_or_nonfinite_stats_cannot_pass(self):
        check = self.good_capture()
        check.stats = None
        self.assertTrue(check.problems())
        check.add(STATS.replace("observed_hz=1000.00", "observed_hz=nan"))
        self.assertTrue(check.problems())

    def test_unbounded_unterminated_data_is_rejected(self):
        with self.assertRaises(ValueError):
            list(Lines().feed(b"x" * 4097))


if __name__ == "__main__":
    unittest.main()
