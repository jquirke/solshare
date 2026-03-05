# TODO

## iOS App

### Widget background refresh
Currently the widget only updates when the main app is opened. To enable true background refresh:
- Register a `BGAppRefreshTask` in `Info.plist` and schedule it on each successful fetch
- In the task handler: fetch today's data → write App Group cache → call `WidgetCenter.shared.reloadAllTimelines()`
- Also call `WidgetCenter.shared.reloadAllTimelines()` in `SummaryViewModel.writeWidgetCache()` so the widget updates immediately on foreground fetch


## Home Assistant Integration

### REST sensor (quick win)
Poll the Allume API from HA using a `rest` sensor in `configuration.yaml` — exposes `solarConsumed`, `gridImport`, `solarPercent` as HA sensors with no custom component needed. JWT refresh every 14 days needs handling (script or automation to re-login and update the token).

### Solar-driven AC automation
Use existing IR blaster AC control + SolShare solar sensors to:
- Pre-cool when solar export exceeds a threshold (use free energy)
- Raise AC setpoint when grid import spikes
- Shift AC runtime to peak solar hours instead of fixed schedule

### strings.json for config flow error messages
Add `strings.json` so HA displays human-readable errors ("Invalid credentials", "Cannot connect") instead of raw keys in the setup UI.

### HACS custom integration (longer term)
Package as a proper Home Assistant custom integration for others in the building to install via HACS. Handles token refresh automatically, exposes sensors via the HA entity registry.

## General

### Weather correlation
Correlate solar generation volatility with BOM weather/clear-sky irradiance model to improve HVAC demand shedding signal quality.
