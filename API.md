# Allume Energy / SolCentre API

Reverse-engineered from the SolCentre customer portal JS bundle.

## Base URL

```
https://api.allumeenergy.com.au/v2
```

## Authentication

### Login

```
POST /auth/customer-login
Content-Type: application/json

{ "email": "<email>", "password": "<password>" }
```

**Response `201 Created`:**
```json
{
  "accessToken": "<JWT>",
  "user": {
    "id": "<userId>",
    "email": "<email>",
    "firstName": "<firstName>",
    "lastName": "<lastName>",
    "role": "Consumer",
    "activated": true,
    "tcAccepted": true,
    "emailVerified": true,
    "createdAt": "...",
    "updatedAt": "..."
  }
}
```

The `accessToken` is a JWT. All subsequent requests must include:

```
Authorization: Bearer <accessToken>
```

---

## Consumer Endpoints

### Get My Properties

```
GET /consumers/me/properties
```

**Response `200 OK`:**
```json
{
  "email": "...",
  "properties": [
    {
      "id": "<propertyId>",
      "meterId": "<meterId>",
      "projectId": "<projectId>",
      "siteId": "<siteId>",
      "consumerId": "<consumerId>",
      "address1": "<unit>",
      "address2": "<street address>",
      "NMI": "<NMI>",
      "billingFrom": "2026-02-24T00:00:00.000Z",
      "isInvoiceEnabled": false,
      "calcStrategy": "Standard",
      "isSnapshotEnabled": true,
      "remark": ""
    }
  ]
}
```

---

## Energy Snapshot Endpoints

Date parameters (`from`, `to`) are **Unix timestamps in seconds** (not milliseconds).
The `to` value is exclusive — to fetch a single day, set `to = from + 86400`.

### Hourly Snapshots by Property

```
GET /properties/{propertyId}/snapshots?type=hourly&from={unixSecs}&to={unixSecs}
```

**Example** — fetch 25 Feb 2026:
```
GET /properties/<propertyId>/snapshots?type=hourly&from=1771977600&to=1772064000
```

**Response `200 OK`** — array of hourly records:
```json
[
  {
    "startAt": "2026-02-25T00:00:00.000Z",
    "endAt":   "2026-02-25T01:00:00.000Z",
    "energyDemand":     0.28,
    "solarConsumed":    0.28,
    "solarDelivered":   0.52,
    "solarExported":    0.23,
    "emissionReduced":  0.348244,
    "emissionReducedUnit": "kg"
  },
  ...
]
```

| Field | Unit | Description |
|---|---|---|
| `startAt` / `endAt` | ISO 8601 | Start and end of the hour window |
| `energyDemand` | kWh | Total electricity consumed by the property |
| `solarConsumed` | kWh | Solar energy actually used by the property |
| `solarDelivered` | kWh | Solar energy delivered to the property (consumed + exported) |
| `solarExported` | kWh | Solar energy exported to the grid from the property |
| `emissionReduced` | kg CO₂ | Emissions avoided by using solar |

**Derived values:**
- `gridImport = energyDemand - solarConsumed`
- `solarSelfConsumptionRate = solarConsumed / solarDelivered`

**Field notes:**
- Despite the endpoint being named `type=hourly`, the actual bucket size depends on the query window — narrow windows return finer-grained buckets (see [Observed Behaviour](#observed-behaviour) below).
- `solarDelivered` ≠ `solarConsumed` + `solarExported` in all cases — small discrepancies observed, possibly due to rounding or metering losses. Do not assume they are identical.
- `solarConsumed` can be negative in raw API responses; clamp to 0 before use.

### Hourly Snapshots by Project

```
GET /projects/{projectId}/snapshots?type=hourly&from={unixSecs}&to={unixSecs}
```

### Hourly Snapshots by Meter

```
GET /meters/{meterId}/snapshots?type=hourly&from={unixSecs}&to={unixSecs}
```

---

## Other Discovered Endpoints

These were found in the JS bundle but are not the focus of this project.

| Method | Path | Description |
|---|---|---|
| `POST` | `/auth/register` | Register new consumer |
| `POST` | `/auth/forget-password` | Request password reset |
| `POST` | `/auth/reset-password` | Complete password reset |
| `POST` | `/auth/change-email` | Change email address |
| `POST` | `/auth/change-pwd` | Change password |
| `DELETE` | `/auth/delete-account/{id}` | Initiate account deletion |
| `GET` | `/projects/{id}` | Get project details |
| `GET` | `/projects/{id}/alerts` | Get alert configuration |
| `GET` | `/projects/{id}/batteries` | Get battery info |
| `GET` | `/meters/{id}/properties` | Get properties for a meter |
| `GET` | `/meters/{id}/revenue` | Get meter revenue data |
| `GET` | `/meters/{id}/property-savings` | Get property savings data |
| `GET` | `/snapshot/{id}/csv` | Download snapshot as CSV |
| `GET` | `/payment/subscription` | Get subscription details |
| `GET` | `/service-interface/system-info/{id}` | Get SolShare system info |

---

## Observed Behaviour

Findings from empirical testing (2026-03-04/05).

### Bucket granularity scales with query window

Despite `type=hourly`, the API returns sub-hourly buckets when the query window is narrow:

| Query window | Observed bucket size |
|---|---|
| 5 minutes | 5 minutes |
| 1 hour | 5 minutes |
| 6 hours | 1 hour |

The exact threshold where it coarsens is unknown — somewhere between 1 hour and 6 hours. Querying hour-by-hour is a reliable way to get 5-minute resolution across a longer period.

**Confirmed working pattern for 5-min data** (2026-04-11):
```
# One call per hour, aligned to hour boundaries
python3 cli/solshare.py --from 2026-04-11T14:00 --to 2026-04-11T15:00
python3 cli/solshare.py --from 2026-04-11T15:00 --to 2026-04-11T16:00
# etc.
```
Large single-window queries (e.g. full day) return 0 records when data is recent/sparse. Hour-by-hour queries return data reliably. For 5-min resolution, use 5-min aligned windows within each hour call.

**Note:** Large windows (24h+) work fine for older historical data but fail silently (return 0 records) for recent/current-day data. Always use 1h windows for same-day queries.

**Uncertainty:** It is not known whether this behaviour is intentional, documented, or stable across API versions.

### 5-minute data retention window (~48 hours)

5-minute resolution data is only available for approximately the most recent 48 hours. Older data is rolled up to hourly and the 5-minute buckets become permanently inaccessible.

Observed boundary (2026-03-23): 5-min data available back to ~Sat 21 Mar 22:00 AEDT at 22:05 Mon 23 Mar — consistent with a ~48h rolling window. The rollup appears to run as a batch job at or shortly after the top of each hour rather than on an exact 48h boundary.

**Implication:** Any 5-minute drill-down on a sampling session must be performed within 48 hours of the reading. Do not defer 5-min analysis — once the window closes it cannot be recovered.

### Data latency

Data appears in the API within ~1 minute of the interval closing. A 5-minute bucket ending at 01:05 was visible by 01:06. This makes the API suitable for near-real-time monitoring applications.

**Uncertainty:** Only tested at night (no solar generation). Latency during peak generation hours is unknown and may differ.

### Solar generation volatility (2026-03-04, partly cloudy)

Analysed 72 × 5-minute `solarDelivered` readings from 12:00–18:00 AEDT:

- **Min/Max:** 0.00 / 0.17 kWh per 5-min interval
- **Coefficient of variation:** 114% — highly volatile signal
- **Largest single-step drop:** 87% in one 5-minute interval (cloud event at 13:10)
- **Zero-delivery periods:** 18% of intervals; two sustained outages of 30 min and 20 min between 14:15–15:10
- **Most stable hour:** 16:00–16:55 (CV ~35%), low but consistent

Implication: the raw 5-minute signal is too noisy for direct HVAC actuation. A 15-minute rolling average with hysteresis is recommended for demand-shedding applications. Future work: correlate with BOM weather/cloud cover data and clear-sky irradiance model to separate cloud events from sun-angle decline.

### Real-time availability and data latency (2026-03-05)

To test data freshness and rule out backfill or correction behaviour, several high-draw appliances (washing machine, dryer) were run at known times with known cycle lengths and the API was polled at 5-minute resolution immediately after each interval closed.

Findings:
- Data for a closed 5-minute bucket appeared in the API within ~1 minute of the interval ending, with no detectable ingestion lag beyond that.
- Appliance start and stop times matched the API data to within one 5-minute bucket — consistent with the meter reporting promptly with no delayed correction or backfill observed.
- No evidence of values being revised after initial appearance. The first value returned for a bucket remained stable on subsequent polls.

The API appears suitable for near-real-time monitoring (polling cadence of 5–15 minutes is reasonable). There is no evidence of delayed ingestion or retroactive correction.

---

## Notes

- The portal is a Vue.js SPA served from `https://solcentre.allumeenergy.com`
- The API is at a separate origin (`api.allumeenergy.com.au`)
- JWT tokens have a ~14-day expiry (`exp` claim)
- Timestamps in API responses are UTC; the `$g()` frontend function passes a UTC offset as a third parameter to snapshot calls — this may affect how daily boundaries are computed server-side