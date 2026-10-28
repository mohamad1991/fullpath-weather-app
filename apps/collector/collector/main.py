"""Weather collector - runs as a Kubernetes CronJob.

One run = fetch current weather for all configured locations (single batched
Open-Meteo request), upsert into Postgres, exit. Exit code != 0 marks the Job
failed so it shows up in alerting (kube_job_failed).
"""

import json
import logging
import os
import pathlib
import sys
import time
from datetime import UTC, datetime

import httpx
import psycopg

log = logging.getLogger("collector")

OPEN_METEO_URL = os.environ.get("OPEN_METEO_URL", "https://api.open-meteo.com/v1/forecast")
LOCATIONS_FILE = os.environ.get("LOCATIONS_FILE", "/config/locations.json")
CURRENT_FIELDS = [
    "temperature_2m",
    "apparent_temperature",
    "relative_humidity_2m",
    "precipitation",
    "wind_speed_10m",
    "wind_direction_10m",
    "weather_code",
]
MAX_ATTEMPTS = 4


def database_conninfo() -> str:
    parts = {
        "host": os.environ.get("DB_HOST", "localhost"),
        "port": os.environ.get("DB_PORT", "5432"),
        "dbname": os.environ.get("DB_NAME", "weather"),
        "user": os.environ.get("DB_USER", "weather"),
        "password": os.environ.get("DB_PASSWORD", ""),
        "sslmode": os.environ.get("DB_SSLMODE", "prefer"),
        "connect_timeout": "5",
        "application_name": "weather-collector",
    }
    return " ".join(f"{k}='{v}'" for k, v in parts.items())


def load_locations(path: str) -> list[dict]:
    locations = json.loads(pathlib.Path(path).read_text())
    for loc in locations:
        missing = {"name", "country", "latitude", "longitude"} - loc.keys()
        if missing:
            raise ValueError(f"location {loc} missing {missing}")
    return locations


def fetch_current(client: httpx.Client, locations: list[dict]) -> list[dict]:
    """Fetch current weather for all locations in one call, with exponential backoff."""
    params = {
        "latitude": ",".join(str(loc["latitude"]) for loc in locations),
        "longitude": ",".join(str(loc["longitude"]) for loc in locations),
        "current": ",".join(CURRENT_FIELDS),
        "timezone": "UTC",
    }
    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            resp = client.get(OPEN_METEO_URL, params=params)
            resp.raise_for_status()
            data = resp.json()
            # Open-Meteo returns an object for one location, a list for many.
            return data if isinstance(data, list) else [data]
        except (httpx.HTTPError, ValueError) as exc:
            if attempt == MAX_ATTEMPTS:
                raise
            delay = 2**attempt
            log.warning("fetch attempt %d failed (%s); retrying in %ds", attempt, exc, delay)
            time.sleep(delay)
    raise RuntimeError("unreachable")


def to_observation(payload: dict) -> dict:
    cur = payload["current"]
    observed = datetime.fromisoformat(cur["time"]).replace(tzinfo=UTC)
    return {
        "observed_at": observed,
        "temperature_c": cur.get("temperature_2m"),
        "apparent_temperature_c": cur.get("apparent_temperature"),
        "humidity_pct": cur.get("relative_humidity_2m"),
        "precipitation_mm": cur.get("precipitation"),
        "wind_speed_kmh": cur.get("wind_speed_10m"),
        "wind_direction_deg": cur.get("wind_direction_10m"),
        "weather_code": cur.get("weather_code"),
    }


def store(conn: psycopg.Connection, locations: list[dict], observations: list[dict]) -> int:
    inserted = 0
    with conn.transaction():
        for loc, obs in zip(locations, observations, strict=True):
            loc_id = conn.execute(
                """
                INSERT INTO locations (name, country, latitude, longitude, timezone)
                VALUES (%(name)s, %(country)s, %(latitude)s, %(longitude)s, %(timezone)s)
                ON CONFLICT (name, country) DO UPDATE
                    SET latitude = EXCLUDED.latitude, longitude = EXCLUDED.longitude
                RETURNING id
                """,
                {"timezone": "UTC", **loc},
            ).fetchone()[0]
            cur = conn.execute(
                """
                INSERT INTO weather_observations
                    (location_id, observed_at, temperature_c, apparent_temperature_c, humidity_pct,
                     precipitation_mm, wind_speed_kmh, wind_direction_deg, weather_code)
                VALUES (%(location_id)s, %(observed_at)s, %(temperature_c)s, %(apparent_temperature_c)s,
                        %(humidity_pct)s, %(precipitation_mm)s, %(wind_speed_kmh)s,
                        %(wind_direction_deg)s, %(weather_code)s)
                ON CONFLICT (location_id, observed_at) DO NOTHING
                """,
                {"location_id": loc_id, **obs},
            )
            inserted += cur.rowcount
    return inserted


def main() -> int:
    logging.basicConfig(level=logging.INFO, format='{"ts":"%(asctime)s","level":"%(levelname)s","msg":"%(message)s"}')
    locations = load_locations(LOCATIONS_FILE)
    with httpx.Client(timeout=10.0) as client:
        payloads = fetch_current(client, locations)
    observations = [to_observation(p) for p in payloads]
    with psycopg.connect(database_conninfo()) as conn:
        inserted = store(conn, locations, observations)
    log.info("collected %d locations, inserted %d new observations", len(locations), inserted)
    return 0


if __name__ == "__main__":
    sys.exit(main())
