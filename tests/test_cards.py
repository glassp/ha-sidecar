"""The result-card builder (custom_components/ha_sidecar/cards.py has no Home Assistant imports)."""

import importlib.util
import sys
from pathlib import Path
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location("cards", Path(__file__).parent.parent / "custom_components" / "ha_sidecar" / "cards.py")
cards = importlib.util.module_from_spec(spec)
sys.modules["cards"] = cards
spec.loader.exec_module(cards)


def st(entity_id, state, **attributes):
    return SimpleNamespace(entity_id=entity_id, state=state, attributes=attributes, name=attributes.get("friendly_name", entity_id))


WEATHER = st("weather.home", "partlycloudy", friendly_name="Home", temperature=21.0, temperature_unit="°C", humidity=60, wind_speed=12.4, wind_speed_unit="km/h")


def test_weather_card_shows_condition_temperature_and_details():
    c = cards.weather_card(WEATHER)
    assert (c["type"], c["title"], c["value"], c["subtitle"], c["icon"]) == ("weather", "Home", "21 °C", "Partly cloudy", "partlycloudy")
    assert c["details"] == ["Humidity 60 %", "Wind 12.4 km/h"]


def test_weather_card_forecast_is_limited_and_formatted():
    days = [{"label": d, "condition": "sunny", "temperature": 22 + i, "templow": 12} for i, d in enumerate(["Mon", "Tue", "Wed", "Thu", "Fri"])]
    c = cards.weather_card(WEATHER, days)
    assert len(c["forecast"]) == cards.MAX_FORECAST
    assert c["forecast"][0] == {"label": "Mon", "value": "22° / 12°", "icon": "sunny"}


def test_media_card_title_artist_album_and_picture():
    c = cards.media_card(st("media_player.tv", "playing", friendly_name="TV", media_title="Song", media_artist="Band", media_album_name="Album", entity_picture="/api/media_player_proxy/media_player.tv?token=x"))
    assert (c["title"], c["subtitle"], c["value"]) == ("Song", "Band — Album", "Playing")
    assert c["image"].startswith("/api/media_player_proxy/")


def test_camera_gives_an_image_card_only_with_a_picture():
    assert cards.card_for_state(st("camera.door", "idle", friendly_name="Door", entity_picture="/api/camera_proxy/camera.door?token=t"))["type"] == "image"
    assert cards.card_for_state(st("camera.door", "idle")) is None


def test_entity_values_read_like_a_person_would_say_them():
    assert cards.entity_card(st("sensor.t", "21.50", friendly_name="Kitchen temperature", unit_of_measurement="°C"))["value"] == "21.5 °C"
    assert cards.entity_card(st("light.k", "on", friendly_name="Kitchen light", brightness=128))["subtitle"] == "Brightness 50 %"
    assert cards.entity_card(st("binary_sensor.w", "on", friendly_name="Window", device_class="window"))["value"] == "Open"
    assert cards.entity_card(st("binary_sensor.d", "off", friendly_name="Door", device_class="door"))["value"] == "Closed"
    assert cards.entity_card(st("cover.c", "open", friendly_name="Blinds", current_position=70))["subtitle"] == "70 % open"
    assert cards.entity_card(st("climate.h", "heat", friendly_name="Heat", current_temperature=20.5, temperature=22))["value"] == "20.5°"


def test_unavailable_entities_give_no_card():
    assert cards.card_for_state(st("sensor.t", "unavailable", friendly_name="T")) is None
    assert cards.card_for_state(st("weather.home", "unknown")) is None


def intent(success=None, name=None):
    r = {"data": {"success": success or [], "failed": []}}
    if name:
        r["speech_slots"] = {"name": name}
    return {"response": r}


def test_an_action_gives_cards_for_the_entities_it_touched():
    states = {"light.kitchen": st("light.kitchen", "on", friendly_name="Kitchen light"), "script.x": st("script.x", "off", friendly_name="X")}
    out = cards.build_cards(lambda: states.values(), states.get, intent([{"name": "Kitchen light", "type": "entity", "id": "light.kitchen"}, {"name": "X", "type": "entity", "id": "script.x"}]))
    assert [c["entity_id"] for c in out] == ["light.kitchen"], "a script is not something to show"


def test_a_weather_answer_names_the_weather_entity():
    states = {"weather.home": WEATHER}
    out = cards.build_cards(lambda: states.values(), states.get, intent([{"name": "Home", "type": "entity", "id": "weather.home"}]))
    assert out[0]["type"] == "weather"


def test_a_question_gives_the_card_of_the_entity_it_names():
    states = {"sensor.kt": st("sensor.kt", "21.5", friendly_name="Kitchen temperature", unit_of_measurement="°C")}
    out = cards.build_cards(lambda: states.values(), states.get, intent(name="kitchen temperature"))
    assert out[0]["value"] == "21.5 °C"


def test_a_name_that_is_not_unique_gives_no_card():
    states = [st("sensor.a", "1", friendly_name="Temperature"), st("sensor.b", "2", friendly_name="temperature")]
    assert cards.build_cards(lambda: states, lambda i: None, intent(name="Temperature")) == []


def test_a_weather_question_gets_the_forecast():
    states = {"weather.home": WEATHER}
    forecast = {"weather.home": [{"label": "Mon", "condition": "rainy", "temperature": 15, "templow": 9}]}
    out = cards.build_cards(lambda: states.values(), states.get, intent(name="Home"), forecast)
    assert out[0]["type"] == "weather" and out[0]["forecast"][0]["icon"] == "rainy"


def test_no_more_than_three_cards():
    states = {f"light.l{i}": st(f"light.l{i}", "on", friendly_name=f"L{i}") for i in range(6)}
    out = cards.build_cards(lambda: states.values(), states.get, intent([{"type": "entity", "id": k, "name": k} for k in states]))
    assert len(out) == cards.MAX_CARDS


def test_an_error_response_has_no_cards():
    assert cards.build_cards(lambda: [], lambda i: None, {"response": {"data": {"code": "no_valid_targets"}}}) == []
    assert cards.build_cards(lambda: [], lambda i: None, None) == []


def test_a_custom_card_fills_what_is_given():
    c = cards.custom_card({"title": "Garden", "image": "https://x/y.jpg", "details": ["a", "b", "c", "d", "e"]})
    assert (c["type"], c["icon"], len(c["details"])) == ("image", "camera", 4)
    assert cards.custom_card({"title": "Hi", "value": "42"})["type"] == "entity"
