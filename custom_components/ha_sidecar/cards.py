"""Result cards for the voice screen: weather, media, image and entity cards built from Home Assistant states.

No Home Assistant imports: a "state" is anything with `entity_id`, `state`, `attributes` and `name` (a `homeassistant.core.State`
or a stand-in in tests). The cards are plain dicts the tablet renders (docs/VOICE.md):

    {"type": "weather" | "media" | "image" | "entity",
     "title": str, "subtitle": str, "value": str, "icon": str,
     "image": str,                       # path or URL (relative to Home Assistant, the tablet rebases it), or ""
     "details": [str, ...],              # small print under the main line
     "forecast": [{"label", "value", "icon"}, ...],
     "entity_id": str}
"""

from __future__ import annotations

from collections.abc import Callable, Iterable
from typing import Any

MAX_CARDS = 3
MAX_FORECAST = 4

# domains worth a card when an intent response names the entity ("turn on the light": the light; "what is the weather": the weather)
SHOW_DOMAINS = {
    "light", "switch", "cover", "lock", "climate", "fan", "media_player", "vacuum", "humidifier", "input_boolean",
    "weather", "camera", "image", "sensor", "binary_sensor", "person",
}

WEATHER_ICONS = {
    "sunny": "sunny",
    "clear-night": "clear-night",
    "partlycloudy": "partlycloudy",
    "cloudy": "cloudy",
    "rainy": "rainy",
    "pouring": "pouring",
    "snowy": "snowy",
    "snowy-rainy": "snowy",
    "hail": "snowy",
    "lightning": "lightning",
    "lightning-rainy": "lightning",
    "fog": "fog",
    "windy": "windy",
    "windy-variant": "windy",
    "exceptional": "exceptional",
}

DOMAIN_ICONS = {
    "light": "light",
    "switch": "switch",
    "input_boolean": "switch",
    "cover": "cover",
    "lock": "lock",
    "climate": "climate",
    "fan": "fan",
    "media_player": "media",
    "vacuum": "vacuum",
    "sensor": "sensor",
    "binary_sensor": "sensor",
    "camera": "camera",
    "image": "camera",
    "person": "person",
    "weather": "partlycloudy",
}

BINARY_WORDS = {
    "door": ("Open", "Closed"),
    "window": ("Open", "Closed"),
    "garage_door": ("Open", "Closed"),
    "opening": ("Open", "Closed"),
    "motion": ("Motion", "Clear"),
    "occupancy": ("Occupied", "Clear"),
    "presence": ("Home", "Away"),
    "lock": ("Unlocked", "Locked"),
    "smoke": ("Smoke", "Clear"),
    "moisture": ("Wet", "Dry"),
}


def _attr(state: Any, key: str, default: Any = None) -> Any:
    return (getattr(state, "attributes", None) or {}).get(key, default)


def _domain(state: Any) -> str:
    return str(state.entity_id).split(".", 1)[0]


def _name(state: Any) -> str:
    return str(getattr(state, "name", None) or _attr(state, "friendly_name") or state.entity_id)


def _number(value: Any) -> str:
    """21.0 -> "21", 21.5 -> "21.5"."""
    try:
        f = float(value)
    except (TypeError, ValueError):
        return str(value)
    return str(int(f)) if f == int(f) else f"{f:.1f}".rstrip("0").rstrip(".")


def _unavailable(state: Any) -> bool:
    return str(state.state) in ("unavailable", "unknown")


def weather_card(state: Any, forecast: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    unit = _attr(state, "temperature_unit") or "°C"
    temp = _attr(state, "temperature")
    details = []
    if (h := _attr(state, "humidity")) is not None:
        details.append(f"Humidity {_number(h)} %")
    if (w := _attr(state, "wind_speed")) is not None:
        details.append(f"Wind {_number(w)} {_attr(state, 'wind_speed_unit') or 'km/h'}")
    if (p := _attr(state, "pressure")) is not None:
        details.append(f"Pressure {_number(p)} {_attr(state, 'pressure_unit') or 'hPa'}")
    condition = str(state.state)
    days = []
    for item in (forecast or [])[:MAX_FORECAST]:
        low, high = item.get("templow"), item.get("temperature")
        value = f"{_number(high)}°" if low is None else f"{_number(high)}° / {_number(low)}°"
        days.append({"label": str(item.get("label") or ""), "value": value if high is not None else "", "icon": WEATHER_ICONS.get(str(item.get("condition")), "cloudy")})
    return {
        "type": "weather",
        "title": _name(state),
        "subtitle": condition.replace("-", " ").replace("partlycloudy", "partly cloudy").capitalize(),
        "value": f"{_number(temp)} {unit}" if temp is not None else "",
        "icon": WEATHER_ICONS.get(condition, "cloudy"),
        "image": "",
        "details": details,
        "forecast": days,
        "entity_id": state.entity_id,
    }


def media_card(state: Any) -> dict[str, Any]:
    title = _attr(state, "media_title") or _name(state)
    parts = [p for p in (_attr(state, "media_artist"), _attr(state, "media_album_name")) if p]
    return {
        "type": "media",
        "title": str(title),
        "subtitle": " — ".join(str(p) for p in parts) or _name(state),
        "value": str(state.state).capitalize(),
        "icon": "media",
        "image": str(_attr(state, "entity_picture") or ""),
        "details": [],
        "forecast": [],
        "entity_id": state.entity_id,
    }


def image_card(state: Any) -> dict[str, Any]:
    return {
        "type": "image",
        "title": _name(state),
        "subtitle": "",
        "value": "",
        "icon": "camera",
        "image": str(_attr(state, "entity_picture") or ""),
        "details": [],
        "forecast": [],
        "entity_id": state.entity_id,
    }


def _entity_value(state: Any) -> tuple[str, str]:
    """(value, subtitle) for a plain entity."""
    domain = _domain(state)
    raw = str(state.state)
    unit = _attr(state, "unit_of_measurement")
    if domain == "sensor":
        return (f"{_number(raw)} {unit}".strip() if unit else raw), ""
    if domain == "binary_sensor":
        on, off = BINARY_WORDS.get(str(_attr(state, "device_class")), ("On", "Off"))
        return (on if raw == "on" else off if raw == "off" else raw.capitalize()), ""
    if domain == "light":
        b = _attr(state, "brightness")
        return raw.capitalize(), (f"Brightness {round(float(b) / 255 * 100)} %" if raw == "on" and b is not None else "")
    if domain == "climate":
        cur, target = _attr(state, "current_temperature"), _attr(state, "temperature")
        return (f"{_number(cur)}°" if cur is not None else raw.capitalize()), (f"Target {_number(target)}°" if target is not None else raw.capitalize())
    if domain == "cover":
        pos = _attr(state, "current_position")
        return raw.capitalize(), (f"{_number(pos)} % open" if pos is not None else "")
    return raw.replace("_", " ").capitalize(), ""


def entity_card(state: Any) -> dict[str, Any]:
    value, subtitle = _entity_value(state)
    return {
        "type": "entity",
        "title": _name(state),
        "subtitle": subtitle,
        "value": value,
        "icon": DOMAIN_ICONS.get(_domain(state), "info"),
        "image": "",
        "details": [],
        "forecast": [],
        "entity_id": state.entity_id,
    }


def card_for_state(state: Any, forecast: list[dict[str, Any]] | None = None) -> dict[str, Any] | None:
    """The best card for an entity, or None when there is nothing to show (unavailable, or an entity without a picture)."""
    domain = _domain(state)
    if domain == "weather":
        return None if _unavailable(state) else weather_card(state, forecast)
    if domain in ("camera", "image"):
        return image_card(state) if _attr(state, "entity_picture") else None
    if domain == "media_player":
        return None if _unavailable(state) else media_card(state)
    return None if _unavailable(state) else entity_card(state)


def entity_ids_from_intent(intent_output: dict[str, Any] | None) -> tuple[list[str], str | None]:
    """What a Home Assistant intent response says about the entities it used.

    Returns (entity ids of the successful targets of an action, the name an answer was about). Questions ("what is the
    temperature in the kitchen") only carry the name, in the speech slots.
    """
    response = (intent_output or {}).get("response") or {}
    data = response.get("data") or {}
    ids = [t["id"] for t in data.get("success") or [] if isinstance(t, dict) and t.get("type") == "entity" and t.get("id")]
    name = (response.get("speech_slots") or {}).get("name")
    return ids, (str(name) if name else None)


def find_by_name(states: Iterable[Any], name: str) -> Any | None:
    """The one entity whose name is exactly [name] (case-insensitive); None if there is none or it is ambiguous."""
    wanted = name.strip().casefold()
    hits = [s for s in states if _name(s).strip().casefold() == wanted]
    return hits[0] if len(hits) == 1 else None


def build_cards(
    states: Callable[[], Iterable[Any]],
    get: Callable[[str], Any | None],
    intent_output: dict[str, Any] | None,
    forecasts: dict[str, list[dict[str, Any]]] | None = None,
) -> list[dict[str, Any]]:
    """Cards for what an intent response was about. [states] lists all states, [get] reads one by id."""
    ids, name = entity_ids_from_intent(intent_output)
    chosen: list[Any] = []
    for entity_id in ids:
        s = get(entity_id)
        if s is not None and (_domain(s) in SHOW_DOMAINS):
            chosen.append(s)
    if not chosen and name:
        s = find_by_name(states(), name)
        if s is not None:
            chosen.append(s)
    cards = []
    for s in chosen:
        card = card_for_state(s, (forecasts or {}).get(s.entity_id))
        if card is not None:
            cards.append(card)
    return cards[:MAX_CARDS]


def custom_card(data: dict[str, Any]) -> dict[str, Any]:
    """A card made by hand (the `show_card` service): any of the fields, the rest empty."""
    kind = data.get("type") if data.get("type") in ("weather", "media", "image", "entity") else ("image" if data.get("image") else "entity")
    return {
        "type": kind,
        "title": str(data.get("title") or ""),
        "subtitle": str(data.get("subtitle") or ""),
        "value": str(data.get("value") or ""),
        "icon": str(data.get("icon") or ("camera" if kind == "image" else "info")),
        "image": str(data.get("image") or ""),
        "details": [str(d) for d in (data.get("details") or [])][:4],
        "forecast": [],
        "entity_id": str(data.get("entity_id") or ""),
    }
