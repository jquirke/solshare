from homeassistant.components.sensor import SensorEntity, SensorDeviceClass, SensorStateClass
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import DOMAIN
from .coordinator import SolShareCoordinator

# (key, period, name, unit, device_class, icon)
SENSORS = [
    ("solar_consumed", "last_hour", "Last Hour Solar Consumed", "kWh", SensorDeviceClass.ENERGY, "mdi:solar-power"),
    ("grid_import",    "last_hour", "Last Hour Grid Import",    "kWh", SensorDeviceClass.ENERGY, "mdi:transmission-tower"),
    ("solar_exported", "last_hour", "Last Hour Solar Exported", "kWh", SensorDeviceClass.ENERGY, "mdi:solar-power"),
    ("solar_percent",  "last_hour", "Last Hour Solar Percent",  "%",   None,                     "mdi:percent"),
    ("solar_consumed", "today",     "Today Solar Consumed",     "kWh", SensorDeviceClass.ENERGY, "mdi:solar-power"),
    ("grid_import",    "today",     "Today Grid Import",        "kWh", SensorDeviceClass.ENERGY, "mdi:transmission-tower"),
    ("solar_exported", "today",     "Today Solar Exported",     "kWh", SensorDeviceClass.ENERGY, "mdi:solar-power"),
    ("solar_percent",  "today",     "Today Solar Percent",      "%",   None,                     "mdi:percent"),
    ("demand",         "today",     "Today Total Demand",       "kWh", SensorDeviceClass.ENERGY, "mdi:lightning-bolt"),
]


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    coordinator: SolShareCoordinator = hass.data[DOMAIN][entry.entry_id]
    async_add_entities([
        SolShareSensor(coordinator, key, period, name, unit, device_class, icon)
        for key, period, name, unit, device_class, icon in SENSORS
    ])


class SolShareSensor(CoordinatorEntity, SensorEntity):
    def __init__(self, coordinator, key, period, name, unit, device_class, icon):
        super().__init__(coordinator)
        self._key = key
        self._period = period
        self._attr_name = f"SolShare {name}"
        self._attr_unique_id = f"solshare_{period}_{key}"
        self._attr_native_unit_of_measurement = unit
        self._attr_device_class = device_class
        self._attr_state_class = SensorStateClass.MEASUREMENT
        self._attr_icon = icon

    @property
    def native_value(self):
        if self.coordinator.data is None:
            return None
        return self.coordinator.data[self._period][self._key]
