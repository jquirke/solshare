import logging
from datetime import timedelta, datetime, timezone

import homeassistant.util.dt as dt_util
from homeassistant.core import HomeAssistant
from homeassistant.config_entries import ConfigEntry
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.update_coordinator import DataUpdateCoordinator, UpdateFailed

from .const import DOMAIN, BASE_URL, SCAN_INTERVAL_MINUTES

_LOGGER = logging.getLogger(__name__)


class SolShareCoordinator(DataUpdateCoordinator):
    def __init__(self, hass: HomeAssistant, entry: ConfigEntry) -> None:
        super().__init__(
            hass,
            _LOGGER,
            name=DOMAIN,
            update_interval=timedelta(minutes=SCAN_INTERVAL_MINUTES),
        )
        self._email = entry.data["email"]
        self._password = entry.data["password"]
        self._token: str | None = None
        self._property_id: int | None = None

    async def _login(self) -> None:
        session = async_get_clientsession(self.hass)
        resp = await session.post(
            f"{BASE_URL}/auth/customer-login",
            json={"email": self._email, "password": self._password},
        )
        if resp.status != 201:
            raise UpdateFailed(f"Login failed: HTTP {resp.status}")
        data = await resp.json()
        self._token = data["accessToken"]

    async def _fetch_properties(self) -> None:
        session = async_get_clientsession(self.hass)
        resp = await session.get(
            f"{BASE_URL}/consumers/me/properties",
            headers={"Authorization": f"Bearer {self._token}"},
        )
        if resp.status in (401, 403):
            self._token = None
            raise UpdateFailed("Token expired fetching properties")
        data = await resp.json()
        self._property_id = data["properties"][0]["id"]

    async def _fetch_snapshots(self, from_ts: int, to_ts: int) -> list | None:
        session = async_get_clientsession(self.hass)
        resp = await session.get(
            f"{BASE_URL}/properties/{self._property_id}/snapshots",
            params={"type": "hourly", "from": from_ts, "to": to_ts},
            headers={"Authorization": f"Bearer {self._token}"},
        )
        if resp.status in (401, 403):
            self._token = None
            return None
        return await resp.json()

    async def _async_update_data(self) -> dict:
        # Re-login if token missing
        if self._token is None:
            await self._login()
        if self._property_id is None:
            await self._fetch_properties()

        # Last hour: previous complete hour window
        now_utc = datetime.now(timezone.utc)
        start_of_hour = now_utc.replace(minute=0, second=0, microsecond=0)
        last_hour_to = int(start_of_hour.timestamp())
        last_hour_from = last_hour_to - 3600

        # Today: start of local day to now
        local_now = dt_util.now()
        start_of_day = local_now.replace(hour=0, minute=0, second=0, microsecond=0)
        today_from = int(start_of_day.timestamp())
        today_to = int(local_now.timestamp())

        # Current 5-min bucket: last closed 5-minute window
        minute_floor = (now_utc.minute // 5) * 5
        current_bucket = now_utc.replace(minute=minute_floor, second=0, microsecond=0)
        five_min_to = int(current_bucket.timestamp())
        five_min_from = five_min_to - 300

        async def fetch_with_retry(from_ts, to_ts):
            snaps = await self._fetch_snapshots(from_ts, to_ts)
            if snaps is None:
                await self._login()
                await self._fetch_properties()
                snaps = await self._fetch_snapshots(from_ts, to_ts)
            return snaps

        last_hour_snaps = await fetch_with_retry(last_hour_from, last_hour_to)
        today_snaps = await fetch_with_retry(today_from, today_to)
        five_min_snaps = await fetch_with_retry(five_min_from, five_min_to)

        if last_hour_snaps is None or today_snaps is None or five_min_snaps is None:
            raise UpdateFailed("Failed to fetch snapshot data after re-login")

        return {
            "last_hour": _aggregate(last_hour_snaps),
            "today": _aggregate(today_snaps),
            "current": _aggregate(five_min_snaps),
        }


def _aggregate(snaps: list) -> dict:
    demand = sum(s.get("energyDemand", 0) for s in snaps)
    solar = sum(max(s.get("solarConsumed", 0), 0) for s in snaps)
    exported = sum(max(s.get("solarExported", 0), 0) for s in snaps)
    delivered = sum(max(s.get("solarDelivered", 0), 0) for s in snaps)
    grid = max(demand - solar, 0)
    percent = solar / demand if demand > 0 else 0
    return {
        "demand": round(demand, 3),
        "solar_consumed": round(solar, 3),
        "solar_exported": round(exported, 3),
        "solar_delivered": round(delivered, 3),
        "solar_generated": round(solar + exported, 3),
        "grid_import": round(grid, 3),
        "solar_percent": round(percent * 100, 1),
    }
