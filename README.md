# solsharescript

A command-line tool to fetch and display your solar and electricity demand data from the [Allume Energy SolCentre](https://solcentre.allumeenergy.com) portal.

## What it does

Displays an hourly table of your energy demand vs solar consumption for any time window, with a bar chart showing solar coverage per hour.

```
┌─────────────────────┬────────┬────────┬────────┬──────────────────────────┐
│ Time (AEDT)         │ Demand │  Solar │   Grid │ Solar coverage           │
├─────────────────────┼────────┼────────┼────────┼──────────────────────────┤
│ Thu 26 Feb 07:00    │  0.16  │  0.06  │  0.10  │ █░░░░░░░░░░░░░░░░░░░  38% │
│ Thu 26 Feb 08:00    │  0.13  │  0.00  │  0.13  │ ░░░░░░░░░░░░░░░░░░░░   0% │
│ Thu 26 Feb 11:00    │  1.52  │  1.52  │  0.00  │ ████████████████░░░░ 100% │
│ Thu 26 Feb 19:00    │  1.94  │  0.14  │  1.80  │ █░░░░░░░░░░░░░░░░░░░   7% │
│           ...       │        │        │        │                          │
├─────────────────────┼────────┼────────┼────────┼──────────────────────────┤
│ TOTAL               │ 14.48  │  3.27  │ 11.21  │ Overall solar:  23%    │
└─────────────────────┴────────┴────────┴────────┴──────────────────────────┘
```

All values are in **kWh**. Times are displayed in **AEDT (UTC+11)**.

## Requirements

Python 3.6+, no third-party libraries required.

## Setup

### 1. Clone the repo

```bash
git clone https://github.com/jquirke/solsharescript.git
cd solsharescript
```

### 2. Save your credentials

```bash
python3 solshare.py --email your@email.com --password yourpassword --save
```

This writes `~/.solshare` (mode 600):

```ini
[credentials]
email = your@email.com
password = yourpassword
```

You can also create or edit `~/.solshare` manually.

## Usage

```bash
# Last 24 hours (default)
python3 solshare.py

# A specific day
python3 solshare.py --from 2026-02-25

# A date range
python3 solshare.py --from 2026-02-20 --to 2026-02-26

# Override credentials without saving
python3 solshare.py --email your@email.com --password yourpassword
```

### Arguments

| Argument | Description |
|---|---|
| `--from YYYY-MM-DD` | Start date in AEDT (default: 24 hours ago) |
| `--to YYYY-MM-DD` | End date in AEDT, inclusive (default: same as `--from`) |
| `--email` | Email address (overrides `~/.solshare`) |
| `--password` | Password (overrides `~/.solshare`) |
| `--save` | Save `--email` and `--password` to `~/.solshare` |

## Data fields

| Field | Description |
|---|---|
| Demand | Total electricity consumed (kWh) |
| Solar | Solar energy consumed directly from SolShare (kWh) |
| Grid | Energy drawn from the grid (`Demand - Solar`) |
| Solar% | Proportion of demand met by solar |

See [API.md](API.md) for full documentation of the underlying Allume Energy API.

## Background

This is the first step in a project to maximise rooftop PV energy received via [Allume Energy's SolShare](https://allumeenergy.com.au) system, which distributes solar energy across apartments in a strata building.
