import voluptuous as vol
from homeassistant import config_entries
from homeassistant.helpers.aiohttp_client import async_get_clientsession

from .const import DOMAIN, BASE_URL


class SolShareConfigFlow(config_entries.ConfigFlow, domain=DOMAIN):
    VERSION = 1

    async def async_step_user(self, user_input=None):
        errors = {}
        if user_input is not None:
            try:
                session = async_get_clientsession(self.hass)
                resp = await session.post(
                    f"{BASE_URL}/auth/customer-login",
                    json={"email": user_input["email"], "password": user_input["password"]},
                )
                if resp.status == 201:
                    await self.async_set_unique_id(user_input["email"])
                    self._abort_if_unique_id_configured()
                    return self.async_create_entry(title=user_input["email"], data=user_input)
                errors["base"] = "invalid_auth"
            except Exception:
                errors["base"] = "cannot_connect"

        return self.async_show_form(
            step_id="user",
            data_schema=vol.Schema({
                vol.Required("email"): str,
                vol.Required("password"): str,
            }),
            errors=errors,
        )
