"""Serves the beacon card to the Home Assistant frontend."""

from __future__ import annotations

from pathlib import Path

from homeassistant.components.frontend import add_extra_js_url
from homeassistant.components.http import StaticPathConfig
from homeassistant.core import HomeAssistant

CARD_URL = "/ha_sidecar_static/ha-sidecar-beacon-card.js"
CARD_FILE = Path(__file__).parent / "www" / "ha-sidecar-beacon-card.js"


async def async_register_card(hass: HomeAssistant, version: str) -> None:
    """Make the card type available in the dashboard editor.

    Loading the module only *defines* the custom element. Nothing is sent to Home Assistant unless a card is placed on a
    dashboard, which is why the beacon is explicit: it runs where you add the card.
    """
    await hass.http.async_register_static_paths([StaticPathConfig(CARD_URL, str(CARD_FILE), cache_headers=False)])
    add_extra_js_url(hass, f"{CARD_URL}?v={version}")
