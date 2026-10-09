"""Sensors."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from homeassistant.components.sensor import SensorDeviceClass, SensorEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import EntityCategory
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import CONF_DEVICE_ID, DOMAIN
from .entity import SidecarEntity

# key, name, device_class, unit, entity_category, icon
# (battery, charging, Android version, security patch, next alarm and storage are already exposed by the
# Home Assistant companion app, so they are intentionally not duplicated here)
SENSORS = [
    ("last_interaction", "Last interaction", SensorDeviceClass.TIMESTAMP, None, None, "mdi:gesture-tap"),
    ("foreground_app", "Foreground app", None, None, None, "mdi:application"),
    ("target_brightness", "Target brightness", None, None, EntityCategory.DIAGNOSTIC, "mdi:brightness-percent"),
    ("last_blocked_app", "Last blocked app", None, None, EntityCategory.DIAGNOSTIC, "mdi:shield-alert"),
    ("blocked_count", "Blocked app launches", None, None, EntityCategory.DIAGNOSTIC, "mdi:counter"),
    ("pin_failures", "PIN failures", None, None, EntityCategory.DIAGNOSTIC, "mdi:lock-alert"),
    ("camera_error", "Presence camera error", None, None, EntityCategory.DIAGNOSTIC, "mdi:camera-off"),
    ("mode", "Enforcement mode", None, None, EntityCategory.DIAGNOSTIC, "mdi:shield-lock"),
]


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback) -> None:
    device = hass.data[DOMAIN]["devices"][entry.data[CONF_DEVICE_ID]]
    async_add_entities(
        [*(SidecarSensor(device, *s) for s in SENSORS), NextTimerSensor(device), ActiveTimersSensor(device), AlarmsSensor(device)]
    )


class SidecarSensor(SidecarEntity, SensorEntity):
    def __init__(self, device, key, name, device_class, unit, category, icon) -> None:
        super().__init__(device, key)
        self._attr_name = name
        self._attr_device_class = device_class
        self._attr_native_unit_of_measurement = unit
        self._attr_entity_category = category
        self._attr_icon = icon

    @property
    def native_value(self):
        value = self._state.get(self._key)
        if value is None:
            return None
        if self._key == "last_interaction":  # epoch millis
            return datetime.fromtimestamp(value / 1000, tz=timezone.utc)
        return value


def _iso(ms: int | None) -> str | None:
    return datetime.fromtimestamp(ms / 1000, tz=timezone.utc).isoformat() if ms else None


class NextTimerSensor(SidecarEntity, SensorEntity):
    """When the soonest running countdown ends (shows as a live countdown on dashboards)."""

    _attr_name = "Next timer"
    _attr_device_class = SensorDeviceClass.TIMESTAMP
    _attr_icon = "mdi:timer-sand"

    def __init__(self, device) -> None:
        super().__init__(device, "next_timer")

    @property
    def _next(self) -> dict[str, Any] | None:
        running = [t for t in self._state.get("timers") or [] if t.get("ends_at")]
        return min(running, key=lambda t: t["ends_at"]) if running else None

    @property
    def native_value(self):
        t = self._next
        return datetime.fromtimestamp(t["ends_at"] / 1000, tz=timezone.utc) if t else None

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        t = self._next
        return {"label": t["label"], "timer_id": t["id"]} if t else {}


class ActiveTimersSensor(SidecarEntity, SensorEntity):
    """Number of timers and stopwatches on the tablet; the attributes list them for templates."""

    _attr_name = "Timers"
    _attr_icon = "mdi:timer-outline"

    def __init__(self, device) -> None:
        super().__init__(device, "timers")

    @property
    def native_value(self) -> int | None:
        timers = self._state.get("timers")
        return None if timers is None else len(timers)

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        return {
            "timers": [
                {
                    "timer_id": t["id"],
                    "label": t["label"],
                    "kind": t["kind"],
                    "state": t["state"],
                    "duration": t["duration_ms"] // 1000,
                    "remaining": t["remaining_ms"] // 1000,
                    "elapsed": t["elapsed_ms"] // 1000,
                    "ends_at": _iso(t.get("ends_at")),
                    "started_at": _iso(t.get("started_at")),
                }
                for t in self._state.get("timers") or []
            ]
        }


class AlarmsSensor(SidecarEntity, SensorEntity):
    """Number of enabled alarms on the tablet; the attributes list all of them."""

    _attr_name = "Alarms"
    _attr_icon = "mdi:alarm-multiple"

    def __init__(self, device) -> None:
        super().__init__(device, "alarms")

    @property
    def native_value(self) -> int | None:
        alarms = self._state.get("alarms")
        return None if alarms is None else sum(1 for a in alarms if a.get("enabled"))

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        return {
            "alarms": [
                {
                    "alarm_id": a["id"],
                    "time": f"{a['hour']:02d}:{a['minute']:02d}",
                    "days": a["days"],
                    "label": a["label"],
                    "enabled": a["enabled"],
                    "skip_next": a.get("skip_next", False),
                    "next": _iso(a.get("next")),
                }
                for a in self._state.get("alarms") or []
            ],
            "muted": self._state.get("alarms_muted", False),
        }
