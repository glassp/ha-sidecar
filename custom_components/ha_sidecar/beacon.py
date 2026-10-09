"""Dashboard beacon bookkeeping for one tablet.

Pure logic, no Home Assistant imports, so it can be unit-tested on its own (tests/test_beacon.py).

The beacon card on the dashboard pings Home Assistant while the page is alive. Silence only means something while we can
expect pings, which is what `watching` says. A verdict of `stale` needs a ping that was seen before (`armed`): a tablet
whose dashboard has no beacon card is never judged.
"""

from __future__ import annotations

from datetime import datetime, timedelta
from enum import StrEnum


class BeaconState(StrEnum):
    UNKNOWN = "unknown"  # no beacon seen since the companion app was (re)launched
    OK = "ok"
    STALE = "stale"  # pings stopped while they were expected
    PAUSED = "paused"  # not judged: screen off, app not in front, tablet offline, Home Assistant just started


class BeaconTracker:
    def __init__(self, timeout: timedelta = timedelta(minutes=4)) -> None:
        self.timeout = timeout
        self.last: datetime | None = None
        self.armed = False
        self._watching_since: datetime | None = None
        self._last_heal: datetime | None = None

    def record(self, now: datetime) -> None:
        self.last = now
        self.armed = True

    def disarm(self) -> None:
        """The companion app was launched or restarted: wait for the first beacon of the new page."""
        self.armed = False

    def evaluate(self, now: datetime, *, watching: bool) -> BeaconState:
        if not watching:
            self._watching_since = None
            return BeaconState.PAUSED
        if self._watching_since is None:
            self._watching_since = now  # silence is counted from here, not from before the screen was off
        if not self.armed or self.last is None:
            return BeaconState.UNKNOWN
        reference = max(self.last, self._watching_since)
        return BeaconState.OK if now - reference <= self.timeout else BeaconState.STALE

    def may_heal(self, now: datetime) -> bool:
        """At most one heal per timeout, so a page that keeps failing is not restarted in a loop by this check alone."""
        return self._last_heal is None or now - self._last_heal > self.timeout

    def healed(self, now: datetime) -> None:
        self._last_heal = now
        self.disarm()
