"""Config flow: one entry per tablet; shows a pairing token to type into the app."""

from __future__ import annotations

import secrets
import uuid
from typing import Any

import voluptuous as vol

from homeassistant.config_entries import ConfigEntry, ConfigFlow, ConfigFlowResult, OptionsFlow
from homeassistant.core import callback
from homeassistant.helpers import selector
from homeassistant.const import CONF_NAME

from .const import CONF_DEVICE_ID, CONF_NIGHT_ENTITY, CONF_PRESENCE_ENTITIES, CONF_TOKEN, DOMAIN


class SidecarConfigFlow(ConfigFlow, domain=DOMAIN):
    VERSION = 1

    @staticmethod
    @callback
    def async_get_options_flow(config_entry: ConfigEntry) -> OptionsFlow:
        return SidecarOptionsFlow()

    def __init__(self) -> None:
        self._name = ""
        self._device_id = ""
        self._token = ""

    async def async_step_user(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        if user_input is not None:
            self._name = user_input[CONF_NAME]
            self._device_id = uuid.uuid4().hex
            self._token = secrets.token_urlsafe(32)
            return await self.async_step_pair()
        return self.async_show_form(
            step_id="user",
            data_schema=vol.Schema({vol.Required(CONF_NAME, default="Wall tablet"): str}),
        )

    async def async_step_pair(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        if user_input is not None:
            await self.async_set_unique_id(self._device_id)
            return self.async_create_entry(
                title=self._name,
                data={CONF_DEVICE_ID: self._device_id, CONF_TOKEN: self._token},
            )
        return self.async_show_form(
            step_id="pair",
            data_schema=vol.Schema({}),
            description_placeholders={"token": self._token},
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
                        CONF_NIGHT_ENTITY,
                        description={"suggested_value": opts.get(CONF_NIGHT_ENTITY)},
                    ): selector.EntitySelector(
                        selector.EntitySelectorConfig(domain=["sun", "binary_sensor", "input_boolean", "switch"])
                    ),
                }
            ),
        )
