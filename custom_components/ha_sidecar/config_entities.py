"""Entities that mirror the tablet's display/presence settings (the `cfg` dict in the state).

Every setting lives on the tablet (works offline); these entities read `state["cfg"][key]` and write
through the generic `set_config` command, so they can be used from automations, scripts, blueprints or
driven by helpers (e.g. an automation that turns the `Night light` switch on/off with an input_boolean).
"""

from __future__ import annotations

from datetime import time
from typing import Any

from homeassistant.components.number import NumberEntity, NumberMode
from homeassistant.components.select import SelectEntity
from homeassistant.components.switch import SwitchEntity
from homeassistant.components.text import TextEntity, TextMode
from homeassistant.components.time import TimeEntity
from homeassistant.const import EntityCategory, UnitOfTime

from .device import SidecarDevice
from .entity import SidecarEntity


class _ConfigMixin:
    _device: SidecarDevice
    _key: str

    @property
    def _cfg_value(self) -> Any:
        return (self._device.state.get("cfg") or {}).get(self._key)

    async def _write(self, value: Any) -> None:
        result = await self._device.send_command("set_config", {"config": {self._key: value}})
        # the tablet answers with the full, validated config (e.g. a pasted URL reduced to its path)
        if isinstance(result.get("config"), dict):
            self._device.state["cfg"] = result["config"]
        else:
            self._device.state.setdefault("cfg", {})[self._key] = value
        self.async_write_ha_state()  # type: ignore[attr-defined]


# key, name, min, max, step, unit, icon
NUMBERS = [
    ("day_level", "Day brightness", 0, 255, 1, None, "mdi:brightness-7"),
    ("day_dim_level", "Day idle brightness", 0, 255, 1, None, "mdi:brightness-5"),
    ("night_level", "Night brightness", 0, 255, 1, None, "mdi:brightness-3"),
    ("night_light_level", "Night light brightness", 0, 255, 1, None, "mdi:lightbulb-night"),
    ("night_touch_level", "Night brightness after touch", 0, 255, 1, None, "mdi:gesture-tap"),
    ("dim_after_s", "Dim after", 10, 1800, 5, UnitOfTime.SECONDS, "mdi:timer-sand"),
    ("presence_hold_s", "Presence hold time", 5, 300, 5, UnitOfTime.SECONDS, "mdi:timer-outline"),
    ("night_hold_s", "Night touch hold time", 5, 300, 5, UnitOfTime.SECONDS, "mdi:timer-outline"),
    ("fade_s", "Brightness fade time", 0, 10, 0.5, UnitOfTime.SECONDS, "mdi:transition"),
    ("camera_sensitivity", "Camera motion sensitivity", 0, 100, 1, "%", "mdi:motion-sensor"),
    ("camera_fps", "Camera frame rate", 1, 10, 1, "fps", "mdi:camera-timer"),
    ("glance_after_s", "Glance screen after", 30, 3600, 10, UnitOfTime.SECONDS, "mdi:timer-sand"),
]

# key, name, icon
SWITCHES = [
    ("auto_dim", "Dim when idle", "mdi:brightness-auto"),
    ("night_light", "Night light", "mdi:lightbulb-night-outline"),
    ("camera_presence", "Camera presence detection", "mdi:camera-account"),
    ("glance", "At-a-glance screen", "mdi:clock-digital"),
]

# key, name, options, icon
SELECTS = [
    ("mode", "Brightness mode", ["auto", "day", "night", "manual"], "mdi:theme-light-dark"),
    ("camera_facing", "Presence camera", ["front", "back"], "mdi:camera-switch"),
    ("theme", "App theme", ["system", "light", "dark", "night"], "mdi:theme-light-dark"),
]

# key, name, icon
TEXTS = [
    ("kiosk_dashboard", "Kiosk dashboard", "mdi:view-dashboard"),
    ("glance_dashboard", "Glance dashboard", "mdi:view-dashboard-outline"),
]

# key, name
TIMES = [
    ("night_start", "Night starts"),
    ("night_end", "Night ends"),
]


class ConfigNumber(_ConfigMixin, SidecarEntity, NumberEntity):
    _attr_entity_category = EntityCategory.CONFIG
    _attr_mode = NumberMode.BOX

    def __init__(self, device, key, name, vmin, vmax, step, unit, icon) -> None:
        super().__init__(device, f"cfg_{key}")
        self._key = key
        self._attr_name = name
        self._attr_native_min_value = vmin
        self._attr_native_max_value = vmax
        self._attr_native_step = step
        self._attr_native_unit_of_measurement = unit
        self._attr_icon = icon

    @property
    def native_value(self) -> float | None:
        return self._cfg_value

    async def async_set_native_value(self, value: float) -> None:
        await self._write(int(value) if float(self._attr_native_step).is_integer() else value)


class ConfigSwitch(_ConfigMixin, SidecarEntity, SwitchEntity):
    _attr_entity_category = EntityCategory.CONFIG

    def __init__(self, device, key, name, icon) -> None:
        super().__init__(device, f"cfg_{key}")
        self._key = key
        self._attr_name = name
        self._attr_icon = icon

    @property
    def is_on(self) -> bool | None:
        value = self._cfg_value
        return None if value is None else bool(value)

    async def async_turn_on(self, **kwargs: Any) -> None:
        await self._write(True)

    async def async_turn_off(self, **kwargs: Any) -> None:
        await self._write(False)


class ConfigSelect(_ConfigMixin, SidecarEntity, SelectEntity):
    _attr_entity_category = EntityCategory.CONFIG

    def __init__(self, device, key, name, options, icon) -> None:
        super().__init__(device, f"cfg_{key}")
        self._key = key
        self._attr_name = name
        self._attr_options = options
        self._attr_icon = icon

    @property
    def current_option(self) -> str | None:
        return self._cfg_value

    async def async_select_option(self, option: str) -> None:
        await self._write(option)


class ConfigTime(_ConfigMixin, SidecarEntity, TimeEntity):
    _attr_entity_category = EntityCategory.CONFIG

    def __init__(self, device, key, name) -> None:
        super().__init__(device, f"cfg_{key}")
        self._key = key
        self._attr_name = name
        self._attr_icon = "mdi:clock-outline"

    @property
    def native_value(self) -> time | None:
        minutes = self._cfg_value
        return None if minutes is None else time(int(minutes) // 60, int(minutes) % 60)

    async def async_set_value(self, value: time) -> None:
        await self._write(value.hour * 60 + value.minute)


class ConfigText(_ConfigMixin, SidecarEntity, TextEntity):
    """Dashboard link: accepts a pasted browser URL, the tablet stores just the path."""

    _attr_entity_category = EntityCategory.CONFIG
    _attr_mode = TextMode.TEXT
    _attr_native_min = 0
    _attr_native_max = 255

    def __init__(self, device, key, name, icon) -> None:
        super().__init__(device, f"cfg_{key}")
        self._key = key
        self._attr_name = name
        self._attr_icon = icon

    @property
    def native_value(self) -> str | None:
        value = self._cfg_value
        return None if value is None else str(value)

    async def async_set_value(self, value: str) -> None:
        await self._write(value)
