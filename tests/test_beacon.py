"""Unit tests for the beacon bookkeeping: python3 -m unittest discover -s tests"""

import importlib.util
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "beacon", Path(__file__).parent.parent / "custom_components" / "ha_sidecar" / "beacon.py"
)
beacon = importlib.util.module_from_spec(SPEC)
sys.modules["beacon"] = beacon
SPEC.loader.exec_module(beacon)

T0 = datetime(2030, 1, 1, 12, 0, tzinfo=timezone.utc)
MIN = timedelta(minutes=1)


class BeaconTrackerTest(unittest.TestCase):
    def setUp(self):
        self.t = beacon.BeaconTracker(timeout=4 * MIN)

    def test_no_verdict_before_the_first_beacon(self):
        # a tablet whose dashboard has no beacon card must never be judged
        self.assertEqual(self.t.evaluate(T0, watching=True), beacon.BeaconState.UNKNOWN)
        self.assertEqual(self.t.evaluate(T0 + 60 * MIN, watching=True), beacon.BeaconState.UNKNOWN)

    def test_ok_while_pings_arrive(self):
        self.t.record(T0)
        self.assertEqual(self.t.evaluate(T0 + MIN, watching=True), beacon.BeaconState.OK)
        self.t.record(T0 + 3 * MIN)
        self.assertEqual(self.t.evaluate(T0 + 6 * MIN, watching=True), beacon.BeaconState.OK)

    def test_stale_after_the_timeout(self):
        self.t.record(T0)
        self.t.evaluate(T0, watching=True)
        self.assertEqual(self.t.evaluate(T0 + 4 * MIN, watching=True), beacon.BeaconState.OK)
        self.assertEqual(self.t.evaluate(T0 + 5 * MIN, watching=True), beacon.BeaconState.STALE)

    def test_not_judged_while_not_watching(self):
        self.t.record(T0)
        self.assertEqual(self.t.evaluate(T0 + 30 * MIN, watching=False), beacon.BeaconState.PAUSED)

    def test_silence_is_counted_from_when_watching_resumed(self):
        # screen off for an hour: the old ping must not make the dashboard look frozen the moment the screen turns on
        self.t.record(T0)
        self.t.evaluate(T0 + MIN, watching=False)
        resumed = T0 + 60 * MIN
        self.assertEqual(self.t.evaluate(resumed, watching=True), beacon.BeaconState.OK)
        self.assertEqual(self.t.evaluate(resumed + 3 * MIN, watching=True), beacon.BeaconState.OK)
        self.assertEqual(self.t.evaluate(resumed + 5 * MIN, watching=True), beacon.BeaconState.STALE)

    def test_a_new_page_has_to_beacon_again(self):
        self.t.record(T0)
        self.t.disarm()  # the companion app was restarted
        self.assertEqual(self.t.evaluate(T0 + 30 * MIN, watching=True), beacon.BeaconState.UNKNOWN)
        self.t.record(T0 + 31 * MIN)
        self.assertEqual(self.t.evaluate(T0 + 32 * MIN, watching=True), beacon.BeaconState.OK)

    def test_heal_at_most_once_per_timeout(self):
        self.assertTrue(self.t.may_heal(T0))
        self.t.healed(T0)
        self.assertFalse(self.t.may_heal(T0 + 2 * MIN))
        self.assertTrue(self.t.may_heal(T0 + 5 * MIN))
        self.assertFalse(self.t.armed)  # and the restarted page has to beacon before it is judged again


if __name__ == "__main__":
    unittest.main()
