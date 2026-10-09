from homeassistant.config_entries import ConfigFlow


class LabVoiceFlow(ConfigFlow, domain="lab_voice"):
    VERSION = 1

    async def async_step_user(self, user_input=None):
        await self.async_set_unique_id("lab_voice")
        self._abort_if_unique_id_configured()
        return self.async_create_entry(title="Lab voice", data={})
