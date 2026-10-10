"""Serves the dashboard cards (beacon, timers) to the Home Assistant frontend."""

from __future__ import annotations

from pathlib import Path

from homeassistant.components.frontend import add_extra_js_url
from homeassistant.components.http import StaticPathConfig
from homeassistant.core import HomeAssistant

WWW = Path(__file__).parent / "www"
CARDS = ("ha-sidecar-beacon-card.js", "ha-sidecar-timers-card.js")
BASE_URL = "/ha_sidecar_static"
CARD_URL = f"{BASE_URL}/{CARDS[0]}"  # kept for the beacon API/docs that name it


async def async_register_card(hass: HomeAssistant, version: str) -> None:
    """Make the card types available in the dashboard editor.

    Loading a module only *defines* its custom element. The beacon card sends nothing to Home Assistant unless it is placed on
    a dashboard, which is why the beacon is explicit: it runs where you add the card. The timers card only reads the tablet's
    timers entity and calls the timer services when a button is pressed.
    """
    await hass.http.async_register_static_paths(
        [StaticPathConfig(f"{BASE_URL}/{name}", str(WWW / name), cache_headers=False) for name in CARDS]
    )
    for name in CARDS:
        add_extra_js_url(hass, f"{BASE_URL}/{name}?v={version}")
