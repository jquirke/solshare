# TODO

## iOS App

### Widget background refresh
Currently the widget only updates when the main app is opened. To enable true background refresh:
- Register a `BGAppRefreshTask` in `Info.plist` and schedule it on each successful fetch
- In the task handler: fetch today's data → write App Group cache → call `WidgetCenter.shared.reloadAllTimelines()`
- Also call `WidgetCenter.shared.reloadAllTimelines()` in `SummaryViewModel.writeWidgetCache()` so the widget updates immediately on foreground fetch

## Home Assistant

### HA Energy dashboard support
Today's cumulative sensors (`today_solar_consumed`, `today_grid_import`, `today_solar_exported`) are currently `SensorStateClass.MEASUREMENT`. To feed the HA Energy dashboard they need `SensorStateClass.TOTAL` with a `last_reset` attribute set to start of local day. This would allow proper daily/weekly/monthly energy tracking in the Energy dashboard.

### Solar-driven AC automation
Use existing IR blaster AC control + SolShare solar sensors to:
- Pre-cool when solar export exceeds a threshold (use free energy)
- Raise AC setpoint when grid import spikes
- Shift AC runtime to peak solar hours instead of fixed schedule


### HACS custom integration (longer term)
Package as a proper Home Assistant custom integration for others in the building to install via HACS.

## General

### Weather correlation
Correlate solar generation volatility with BOM weather/clear-sky irradiance model to improve HVAC demand shedding signal quality.
