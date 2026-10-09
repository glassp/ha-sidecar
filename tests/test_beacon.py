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


class BeaconLadderTest(unittest.TestCase):
    def setUp(self):
        self.t = beacon.BeaconTracker(timeout=4 * MIN)
        self.t.record(T0, "/lovelace/wall")

    def test_leaving_is_not_a_hang(self):
        self.t.mark_inactive("navigation", "/config")
        self.assertEqual(self.t.evaluate(T0 + 60 * MIN, watching=True), beacon.BeaconState.INACTIVE)
        self.t.record(T0 + 61 * MIN, "/lovelace/wall")  # the card is mounted again
        self.assertEqual(self.t.evaluate(T0 + 62 * MIN, watching=True), beacon.BeaconState.OK)

    def test_silence_first_navigates_then_restarts(self):
        now = T0 + 10 * MIN
        self.assertEqual(self.t.next_action(now, can_navigate=True), "navigate")
        self.assertIsNone(self.t.next_action(now + 30 * timedelta(seconds=1), can_navigate=True))  # give it time
        self.assertEqual(self.t.next_action(now + 91 * timedelta(seconds=1), can_navigate=True), "heal")

    def test_a_beacon_after_navigating_ends_the_escalation(self):
        now = T0 + 10 * MIN
        self.t.next_action(now, can_navigate=True)
        self.t.record(now + 20 * timedelta(seconds=1), "/lovelace/wall")
        self.assertEqual(self.t.next_action(now + 5 * MIN, can_navigate=True), "navigate")  # a new episode starts over

    def test_without_a_kiosk_dashboard_it_goes_straight_to_restart(self):
        self.assertEqual(self.t.next_action(T0 + 10 * MIN, can_navigate=False), "heal")

    def test_restart_is_rate_limited(self):
        self.t.healed(T0)
        self.assertIsNone(self.t.next_action(T0 + 2 * MIN, can_navigate=False))


if __name__ == "__main__":
    unittest.main()
