from homeassistant.components.sensor import SensorEntity, SensorDeviceClass, SensorStateClass
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity
import homeassistant.util.dt as dt_util

from .const import DOMAIN
from .coordinator import SolShareCoordinator

# (key, period, name, unit, icon)
SENSORS = [
    ("solar_consumed", "last_hour", "Last Hour Solar Consumed", "kWh", "mdi:solar-power"),
    ("grid_import",    "last_hour", "Last Hour Grid Import",    "kWh", "mdi:transmission-tower"),
    ("solar_exported", "last_hour", "Last Hour Solar Exported", "kWh", "mdi:solar-power"),
    ("solar_percent",  "last_hour", "Last Hour Solar Percent",  "%",   "mdi:percent"),
    ("solar_consumed", "today",     "Today Solar Consumed",     "kWh", "mdi:solar-power"),
    ("solar_generated","today",     "Today Solar Generated",    "kWh", "mdi:solar-power"),
    ("grid_import",    "today",     "Today Grid Import",        "kWh", "mdi:transmission-tower"),
    ("solar_exported", "today",     "Today Solar Exported",     "kWh", "mdi:solar-power"),
    ("solar_percent",  "today",     "Today Solar Percent",      "%",   "mdi:percent"),
    ("demand",         "today",     "Today Total Demand",       "kWh", "mdi:lightning-bolt"),
    ("solar_consumed", "current",   "Current Solar Consumed",   "kWh", "mdi:solar-power"),
    ("grid_import",    "current",   "Current Grid Import",      "kWh", "mdi:transmission-tower"),
    ("solar_exported", "current",   "Current Solar Exported",   "kWh", "mdi:solar-power"),
    ("solar_percent",  "current",   "Current Solar Percent",    "%",   "mdi:percent"),
]


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    coordinator: SolShareCoordinator = hass.data[DOMAIN][entry.entry_id]
    async_add_entities([
        SolShareSensor(coordinator, key, period, name, unit, icon)
        for key, period, name, unit, icon in SENSORS
    ])


class SolShareSensor(CoordinatorEntity, SensorEntity):
    def __init__(self, coordinator, key, period, name, unit, icon):
        super().__init__(coordinator)
        self._key = key
        self._period = period
        self._attr_name = f"SolShare {name}"
        self._attr_unique_id = f"solshare_{period}_{key}"
        self._attr_native_unit_of_measurement = unit
        self._attr_icon = icon
        if period == "today" and unit == "kWh":
            self._attr_device_class = SensorDeviceClass.ENERGY
            self._attr_state_class = SensorStateClass.TOTAL
        else:
            self._attr_state_class = SensorStateClass.MEASUREMENT

    @property
    def last_reset(self):
        if self._period == "today" and self._attr_native_unit_of_measurement == "kWh":
            return dt_util.start_of_local_day()
        return None

    @property
    def native_value(self):
        if self.coordinator.data is None:
            return None
        return self.coordinator.data[self._period][self._key]
