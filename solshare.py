#!/usr/bin/env python3
"""
solshare.py - Fetch and display energy data from the Allume Energy SolCentre API.

Usage:
    python3 solshare.py                        # last 24 hours
    python3 solshare.py --from 2026-02-25      # single day (AEDT)
    python3 solshare.py --from 2026-02-20 --to 2026-02-27  # date range (AEDT)

Config file (~/.solshare):
    [credentials]
    email = your@email.com
    password = yourpassword
"""

import argparse
import configparser
import json
import os
import sys
import urllib.request
import urllib.error
from datetime import datetime, timezone, timedelta

API_BASE   = "https://api.allumeenergy.com.au/v2"
CONFIG_PATH = os.path.expanduser("~/.solshare")
AEDT        = timezone(timedelta(hours=11))
BAR_WIDTH   = 20


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

def load_config():
    config = configparser.ConfigParser()
    if os.path.exists(CONFIG_PATH):
        config.read(CONFIG_PATH)
    email    = config.get("credentials", "email",    fallback=None)
    password = config.get("credentials", "password", fallback=None)
    return email, password


def save_config(email, password):
    config = configparser.ConfigParser()
    config["credentials"] = {"email": email, "password": password}
    with open(CONFIG_PATH, "w") as f:
        config.write(f)
    os.chmod(CONFIG_PATH, 0o600)
    print(f"Credentials saved to {CONFIG_PATH}")


# ---------------------------------------------------------------------------
# API helpers
# ---------------------------------------------------------------------------

def api_post(path, payload):
    url  = API_BASE + path
    data = json.dumps(payload).encode()
    req  = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as e:
        body = json.load(e)
        print(f"Error {e.code}: {body.get('message', e.reason)}", file=sys.stderr)
        sys.exit(1)


def api_get(path, token):
    url = API_BASE + path
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as e:
        body = json.load(e)
        print(f"Error {e.code}: {body.get('message', e.reason)}", file=sys.stderr)
        sys.exit(1)


def login(email, password):
    resp = api_post("/auth/customer-login", {"email": email, "password": password})
    return resp["accessToken"]


def get_property_id(token):
    resp = api_get("/consumers/me/properties", token)
    properties = resp.get("properties", [])
    if not properties:
        print("No properties found for this account.", file=sys.stderr)
        sys.exit(1)
    return properties[0]["id"]


def get_snapshots(token, property_id, from_ts, to_ts):
    path = f"/properties/{property_id}/snapshots?type=hourly&from={from_ts}&to={to_ts}"
    return api_get(path, token)


# ---------------------------------------------------------------------------
# Display
# ---------------------------------------------------------------------------

def bar(val, max_val, width=BAR_WIDTH):
    if max_val <= 0 or val <= 0:
        return '░' * width
    filled = min(int(round(val / max_val * width)), width)
    return '█' * filled + '░' * (width - filled)


def print_table(data):
    if not data:
        print("No data returned for this time range.")
        return

    max_demand = max(r['energyDemand'] for r in data) or 1

    print()
    print('┌─────────────────────┬────────┬────────┬────────┬──────────────────────────┐')
    print('│ Time (AEDT)         │ Demand │  Solar │   Grid │ Solar coverage           │')
    print('├─────────────────────┼────────┼────────┼────────┼──────────────────────────┤')

    total_demand = 0
    total_solar  = 0

    for r in data:
        t      = datetime.fromisoformat(r['startAt'].replace('Z', '+00:00')).astimezone(AEDT)
        demand = r['energyDemand']
        solar  = max(r['solarConsumed'], 0)   # clamp API rounding artefacts
        grid   = round(demand - solar, 2)
        pct    = solar / demand * 100 if demand > 0 else 0
        b      = bar(solar, max_demand)
        print(f'│ {t.strftime("%a %d %b %H:%M"):19} │ {demand:5.2f}  │ {solar:5.2f}  │ {grid:5.2f}  │ {b} {pct:3.0f}% │')
        total_demand += demand
        total_solar  += solar

    total_grid    = round(total_demand - total_solar, 2)
    overall_pct   = total_solar / total_demand * 100 if total_demand > 0 else 0
    print('├─────────────────────┼────────┼────────┼────────┼──────────────────────────┤')
    print(f'│ {"TOTAL":19} │ {total_demand:5.2f}  │ {total_solar:5.2f}  │ {total_grid:5.2f}  │ {"Overall solar:":14} {overall_pct:3.0f}%    │')
    print('└─────────────────────┴────────┴────────┴────────┴──────────────────────────┘')
    print()


# ---------------------------------------------------------------------------
# Time window helpers
# ---------------------------------------------------------------------------

def last_24h():
    now = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)
    return int((now - timedelta(hours=24)).timestamp()), int(now.timestamp())


def date_range(from_str, to_str):
    """Parse YYYY-MM-DD strings as AEDT midnight boundaries, return UTC unix seconds."""
    fmt = "%Y-%m-%d"
    try:
        from_dt = datetime.strptime(from_str, fmt).replace(tzinfo=AEDT)
    except ValueError:
        print(f"Invalid --from date '{from_str}'. Use YYYY-MM-DD.", file=sys.stderr)
        sys.exit(1)
    try:
        to_dt = datetime.strptime(to_str, fmt).replace(tzinfo=AEDT) + timedelta(days=1)
    except ValueError:
        print(f"Invalid --to date '{to_str}'. Use YYYY-MM-DD.", file=sys.stderr)
        sys.exit(1)
    return int(from_dt.timestamp()), int(to_dt.timestamp())


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args():
    parser = argparse.ArgumentParser(
        description="Display SolShare energy data from the Allume Energy API."
    )
    parser.add_argument("--from", dest="from_date", metavar="YYYY-MM-DD",
                        help="Start date in AEDT (default: 24 hours ago)")
    parser.add_argument("--to",   dest="to_date",   metavar="YYYY-MM-DD",
                        help="End date in AEDT, inclusive (default: today)")
    parser.add_argument("--email",    help="Override email from config")
    parser.add_argument("--password", help="Override password from config")
    parser.add_argument("--save",     action="store_true",
                        help="Save --email and --password to ~/.solshare")
    return parser.parse_args()


def main():
    args = parse_args()

    # Credentials
    cfg_email, cfg_password = load_config()
    email    = args.email    or cfg_email
    password = args.password or cfg_password

    if not email or not password:
        print("No credentials found. Provide --email and --password, or create ~/.solshare.")
        print("  Example ~/.solshare:")
        print("    [credentials]")
        print("    email = your@email.com")
        print("    password = yourpassword")
        sys.exit(1)

    if args.save:
        save_config(email, password)

    # Time window
    if args.from_date:
        to_str   = args.to_date or args.from_date
        from_ts, to_ts = date_range(args.from_date, to_str)
    else:
        from_ts, to_ts = last_24h()

    # Fetch data
    token       = login(email, password)
    property_id = get_property_id(token)
    snapshots   = get_snapshots(token, property_id, from_ts, to_ts)

    print_table(snapshots)


if __name__ == "__main__":
    main()
