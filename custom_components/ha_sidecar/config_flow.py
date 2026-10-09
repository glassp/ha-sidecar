"""Config flow: pairs with a tablet that is in pairing mode (docs/PAIRING.md).

Found by mDNS (zeroconf) or entered by hand (address + the code the tablet shows). Either way the tablet generates the
credentials for the handshake and Home Assistant hands the tablet its connection token over an encrypted channel.
"""

from __future__ import annotations

import re
import secrets
from typing import Any

import voluptuous as vol

from homeassistant.components.network import async_get_source_ip
from homeassistant.config_entries import ConfigEntry, ConfigFlow, ConfigFlowResult, OptionsFlow
from homeassistant.const import CONF_HOST, CONF_NAME, CONF_PORT
from homeassistant.core import callback
from homeassistant.helpers import selector
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.network import NoURLAvailableError, get_url
from homeassistant.helpers.service_info.zeroconf import ZeroconfServiceInfo
from homeassistant.util import slugify

from .const import (
    CONF_DEVICE_ID,
    CONF_BEACON_HEAL,
    CONF_BEACON_TIMEOUT,
    CONF_ENTITY_PREFIX,
    CONF_GLANCE_ENTITIES,
    CONF_NIGHT_ENTITY,
    CONF_PRESENCE_ENTITIES,
    CONF_TOKEN,
    DOMAIN,
)
from .pairing import DEFAULT_PORT, PairingError, Tablet, TabletPairing

CONF_CODE = "code"
PREFIX_RE = re.compile(r"^[a-z][a-z0-9]*(_[a-z0-9]+)*$")  # lower-case words, single underscores (HA forbids "__")


def _suggest_prefix(name: str) -> str:
    prefix = re.sub(r"_+", "_", slugify(name)).strip("_")
    return prefix if PREFIX_RE.match(prefix) else "wallpanel"


class SidecarConfigFlow(ConfigFlow, domain=DOMAIN):
    VERSION = 1

    @staticmethod
    @callback
    def async_get_options_flow(config_entry: ConfigEntry) -> OptionsFlow:
        return SidecarOptionsFlow()

    def __init__(self) -> None:
        self._host = ""
        self._port = DEFAULT_PORT
        self._code = ""
        self._tablet: Tablet | None = None
        self._pairing: TabletPairing | None = None
        self._name = ""
        self._prefix = ""
        self._ha_token = secrets.token_urlsafe(32)

    # --- how the tablet is found ------------------------------------------------------------------

    async def async_step_user(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """Manual pairing: the tablet's address and the code it shows (leave the code empty to confirm on the tablet)."""
        errors: dict[str, str] = {}
        if user_input is not None:
            self._host = user_input[CONF_HOST].strip()
            self._port = int(user_input.get(CONF_PORT, DEFAULT_PORT))
            self._code = (user_input.get(CONF_CODE) or "").strip()
            try:
                self._tablet = await TabletPairing(async_get_clientsession(self.hass), self._host, self._port).info()
            except PairingError as err:
                errors["base"] = err.code
            else:
                await self.async_set_unique_id(self._tablet.device_id)
                self._abort_if_unique_id_configured()
                return await self.async_step_details()
        return self.async_show_form(
            step_id="user",
            data_schema=vol.Schema(
                {
                    vol.Required(CONF_HOST, default=self._host): str,
                    vol.Required(CONF_PORT, default=self._port): int,
                    vol.Optional(CONF_CODE, default=self._code): str,
                }
            ),
            errors=errors,
        )

    async def async_step_zeroconf(self, discovery_info: ZeroconfServiceInfo) -> ConfigFlowResult:
        """The tablet advertises `_ha-sidecar._tcp` while its pairing mode is on."""
        props = discovery_info.properties
        device_id = props.get("id")
        if not device_id:
            return self.async_abort(reason="not_ha_sidecar")
        await self.async_set_unique_id(device_id)
        self._abort_if_unique_id_configured()
        v4 = [str(ip) for ip in discovery_info.ip_addresses if ip.version == 4]
        self._host = v4[0] if v4 else discovery_info.host
        self._port = discovery_info.port or DEFAULT_PORT
        self._code = ""  # discovery pairs by confirming on the tablet
        self._tablet = Tablet(device_id, props.get("name") or device_id, props.get("model") or "")
        self.context["title_placeholders"] = {"name": self._tablet.name}
        return await self.async_step_details()

    # --- name, prefix, handshake --------------------------------------------------------------------

    async def async_step_details(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        assert self._tablet is not None
        errors: dict[str, str] = {}
        if user_input is not None:
            self._name = user_input[CONF_NAME].strip()
            self._prefix = user_input[CONF_ENTITY_PREFIX].strip()
            if not PREFIX_RE.match(self._prefix):
                errors[CONF_ENTITY_PREFIX] = "invalid_prefix"
            elif any(e.data.get(CONF_ENTITY_PREFIX) == self._prefix for e in self._async_current_entries()):
                errors[CONF_ENTITY_PREFIX] = "prefix_in_use"
            else:
                self._pairing = TabletPairing(async_get_clientsession(self.hass), self._host, self._port)
                try:
                    await self._pairing.hello(self.hass.config.location_name, "token" if self._code else "confirm")
                    if self._code:
                        await self._pairing.finish(await self._credentials(), self._code)
                        return self._create()
                except PairingError as err:
                    errors["base"] = err.code
                else:
                    return await self.async_step_verify()
        return self.async_show_form(
            step_id="details",
            data_schema=vol.Schema(
                {
                    vol.Required(CONF_NAME, default=self._name or self._tablet.name): str,
                    vol.Required(CONF_ENTITY_PREFIX, default=self._prefix or _suggest_prefix(self._tablet.name)): str,
                }
            ),
            description_placeholders={"name": self._tablet.name, "host": f"{self._host}:{self._port}"},
            errors=errors,
        )

    async def async_step_verify(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """Confirm mode: the same six digits must show on the tablet, whose user presses Allow."""
        assert self._pairing is not None
        if user_input is not None:
            try:
                await self._pairing.finish(await self._credentials(), None)
            except PairingError as err:
                return self.async_abort(reason=err.code)
            return self._create()
        return self.async_show_form(
            step_id="verify",
            data_schema=vol.Schema({}),
            description_placeholders={"sas": f"{self._pairing.sas[:3]} {self._pairing.sas[3:]}", "name": self._tablet.name if self._tablet else ""},
        )

    async def _credentials(self) -> dict[str, Any]:
        """What the tablet needs to connect back: its token and the address(es) of this Home Assistant."""
        internal: str | None = None
        external: str | None = None
        try:
            internal = get_url(self.hass, allow_internal=True, allow_external=False, allow_cloud=False, prefer_external=False)
        except NoURLAvailableError:
            ip = await async_get_source_ip(self.hass, target_ip=self._host)
            if ip and self.hass.config.api:
                internal = f"http://{ip}:{self.hass.config.api.port}"
        try:
            external = get_url(self.hass, allow_internal=False, allow_external=True, allow_cloud=True, prefer_external=True)
        except NoURLAvailableError:
            pass
        return {
            "token": self._ha_token,
            "internal_url": internal,
            "external_url": external,
            "ha_name": self.hass.config.location_name,
        }

    def _create(self) -> ConfigFlowResult:
        assert self._tablet is not None
        return self.async_create_entry(
            title=self._name,
            data={CONF_DEVICE_ID: self._tablet.device_id, CONF_TOKEN: self._ha_token, CONF_ENTITY_PREFIX: self._prefix},
        )


class SidecarOptionsFlow(OptionsFlow):
    """Entities that drive the tablet's brightness logic."""

    async def async_step_init(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        if user_input is not None:
            return self.async_create_entry(data=user_input)
        opts = self.config_entry.options
        return self.async_show_form(
            step_id="init",
            data_schema=vol.Schema(
                {
                    vol.Optional(
                        CONF_PRESENCE_ENTITIES,
                        description={"suggested_value": opts.get(CONF_PRESENCE_ENTITIES, [])},
                    ): selector.EntitySelector(
                        selector.EntitySelectorConfig(
                            domain=["binary_sensor", "input_boolean", "switch", "group"], multiple=True
                        )
                    ),
                    vol.Optional(
                        CONF_GLANCE_ENTITIES,
                        description={"suggested_value": opts.get(CONF_GLANCE_ENTITIES, [])},
                    ): selector.EntitySelector(selector.EntitySelectorConfig(multiple=True)),
                    vol.Optional(
                        CONF_BEACON_HEAL, default=bool(opts.get(CONF_BEACON_HEAL, False))
                    ): selector.BooleanSelector(),
                    vol.Optional(
                        CONF_BEACON_TIMEOUT, default=int(opts.get(CONF_BEACON_TIMEOUT, 4))
                    ): selector.NumberSelector(
                        selector.NumberSelectorConfig(min=1, max=30, step=1, unit_of_measurement="min", mode=selector.NumberSelectorMode.BOX)
                    ),
                    vol.Optional(
                        CONF_NIGHT_ENTITY,
                        description={"suggested_value": opts.get(CONF_NIGHT_ENTITY)},
                    ): selector.EntitySelector(
                        selector.EntitySelectorConfig(domain=["sun", "binary_sensor", "input_boolean", "switch"])
                    ),
                }
            ),
        )
