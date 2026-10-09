"""Android OS update entity.

Detection only works when the app is device owner (Android delivers
onSystemUpdatePending to the DPC only). "Install" opens the system update screen on the
tablet; fully unattended install needs an OTA package, see ha_sidecar.install_system_update.
"""

from __future__ import annotations

from typing import Any

from homeassistant.components.update import UpdateEntity, UpdateEntityFeature
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import CONF_DEVICE_ID, DOMAIN
from .entity import SidecarEntity


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback) -> None:
    device = hass.data[DOMAIN]["devices"][entry.data[CONF_DEVICE_ID]]
    async_add_entities([SidecarOsUpdate(device)])


class SidecarOsUpdate(SidecarEntity, UpdateEntity):
    _attr_name = "Android system update"
    _attr_title = "Android"
    _attr_supported_features = UpdateEntityFeature.INSTALL

    def __init__(self, device) -> None:
        super().__init__(device, "os_update")

    @property
    def installed_version(self) -> str | None:
        release = self._state.get("android_release")
        if not release:
            return None
        return f"{release} (patch {self._state.get('security_patch', '?')})"

    @property
    def latest_version(self) -> str | None:
        installed = self.installed_version
        if installed is None:
            return None
        return f"{installed} + pending update" if self._state.get("pending_update") else installed

    @property
    def release_summary(self) -> str | None:
        if not self._state.get("pending_update"):
            if not self._state.get("device_owner"):
                return "Update detection needs the app to be device owner."
            return None
        return (
            "The tablet reports a pending system update. Installing opens the system update screen "
            "and taps through it using the accessibility guard (labels are matched by text, so OEM "
            "screens may need extra labels). The tablet restarts when the update is applied."
        )

    async def async_install(self, version: str | None, backup: bool, **kwargs: Any) -> None:
        try:
            await self._device.send_command("run_system_update")
        except HomeAssistantError as err:
            if "needs_accessibility" not in str(err):
                raise
            # no accessibility guard: open the screen, user taps through
            await self._device.send_command("open_system_update")
