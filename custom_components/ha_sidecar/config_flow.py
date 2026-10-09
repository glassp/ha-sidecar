"""Config flow: one entry per tablet; shows a pairing token to type into the app."""

from __future__ import annotations

import secrets
import uuid
from typing import Any

import voluptuous as vol

from homeassistant.config_entries import ConfigFlow, ConfigFlowResult
from homeassistant.const import CONF_NAME

from .const import CONF_DEVICE_ID, CONF_TOKEN, DOMAIN


class SidecarConfigFlow(ConfigFlow, domain=DOMAIN):
    VERSION = 1

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
