"""Config flow: one entry per tablet; shows a pairing token to type into the app."""

from __future__ import annotations

import re
import secrets
import uuid
from typing import Any

import voluptuous as vol

from homeassistant.config_entries import ConfigEntry, ConfigFlow, ConfigFlowResult, OptionsFlow
from homeassistant.core import callback
from homeassistant.helpers import selector
from homeassistant.const import CONF_NAME

from .const import (
    CONF_DEVICE_ID,
    CONF_ENTITY_PREFIX,
    CONF_GLANCE_ENTITIES,
    CONF_NIGHT_ENTITY,
    CONF_PRESENCE_ENTITIES,
    CONF_TOKEN,
    DOMAIN,
)


PREFIX_RE = re.compile(r"^[a-z][a-z0-9]*(_[a-z0-9]+)*$")  # lower-case words, single underscores (HA forbids "__")


class SidecarConfigFlow(ConfigFlow, domain=DOMAIN):
    VERSION = 1

    @staticmethod
    @callback
    def async_get_options_flow(config_entry: ConfigEntry) -> OptionsFlow:
        return SidecarOptionsFlow()

    def __init__(self) -> None:
        self._device_id = uuid.uuid4().hex
        self._token = secrets.token_urlsafe(32)

    async def async_step_user(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """Shows the pairing token (type it into the app), and asks for the tablet's name and entity prefix."""
        errors: dict[str, str] = {}
        if user_input is not None:
            prefix = user_input[CONF_ENTITY_PREFIX].strip()
            if not PREFIX_RE.match(prefix):
                errors[CONF_ENTITY_PREFIX] = "invalid_prefix"
            elif any(e.data.get(CONF_ENTITY_PREFIX) == prefix for e in self._async_current_entries()):
                errors[CONF_ENTITY_PREFIX] = "prefix_in_use"
            else:
                await self.async_set_unique_id(self._device_id)
                return self.async_create_entry(
                    title=user_input[CONF_NAME].strip(),
                    data={CONF_DEVICE_ID: self._device_id, CONF_TOKEN: self._token, CONF_ENTITY_PREFIX: prefix},
                )
        suggested = user_input or {}
        return self.async_show_form(
            step_id="user",
            data_schema=vol.Schema(
                {
                    vol.Required(CONF_NAME, default=suggested.get(CONF_NAME, "Wall panel")): str,
                    vol.Required(CONF_ENTITY_PREFIX, default=suggested.get(CONF_ENTITY_PREFIX, "wallpanel")): str,
                }
            ),
            description_placeholders={"token": self._token},
            errors=errors,
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
                        CONF_NIGHT_ENTITY,
                        description={"suggested_value": opts.get(CONF_NIGHT_ENTITY)},
                    ): selector.EntitySelector(
                        selector.EntitySelectorConfig(domain=["sun", "binary_sensor", "input_boolean", "switch"])
                    ),
                }
            ),
        )
