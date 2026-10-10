"""Home Assistant side of the result cards: reads states and weather forecasts for [cards.py](cards.py)."""

from __future__ import annotations

import logging
from typing import Any

from homeassistant.core import HomeAssistant
from homeassistant.util import dt as dt_util

from . import cards

_LOGGER = logging.getLogger(__name__)


async def async_forecast(hass: HomeAssistant, entity_id: str) -> list[dict[str, Any]]:
    """The next days of a weather entity (daily forecast), each with a short weekday label; empty if it has none."""
    try:
        response = await hass.services.async_call(
            "weather", "get_forecasts", {"entity_id": entity_id, "type": "daily"}, blocking=True, return_response=True
        )
    except Exception as err:  # noqa: BLE001 - not every weather entity supports a daily forecast
        _LOGGER.debug("No daily forecast for %s: %s", entity_id, err)
        return []
    days = []
    for item in ((response or {}).get(entity_id) or {}).get("forecast") or []:
        when = dt_util.parse_datetime(str(item.get("datetime", "")))
        days.append({**item, "label": dt_util.as_local(when).strftime("%a") if when else ""})
    return days


async def async_cards_for_states(hass: HomeAssistant, states: list[Any]) -> list[dict[str, Any]]:
    out = []
    for state in states:
        if state is None:
            continue
        forecast = await async_forecast(hass, state.entity_id) if state.entity_id.startswith("weather.") else None
        card = cards.card_for_state(state, forecast)
        if card is not None:
            out.append(card)
    return out[: cards.MAX_CARDS]


async def async_cards_for_intent(hass: HomeAssistant, intent_output: dict[str, Any] | None) -> list[dict[str, Any]]:
    """Cards for what an intent response was about (the entities an action touched, or the one a question named)."""
    first = cards.build_cards(hass.states.async_all, hass.states.get, intent_output)
    forecasts = {c["entity_id"]: await async_forecast(hass, c["entity_id"]) for c in first if c["type"] == "weather"}
    return cards.build_cards(hass.states.async_all, hass.states.get, intent_output, forecasts) if forecasts else first
