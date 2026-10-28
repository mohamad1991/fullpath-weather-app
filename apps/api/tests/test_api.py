"""Integration tests against a real Postgres (docker-compose locally, a service
container in CI). Real DB > mocks here: the interesting logic lives in SQL."""

from datetime import UTC, datetime, timedelta

import psycopg
import pytest
from fastapi.testclient import TestClient

from app import migrate
from app.config import database_conninfo
from app.main import app


@pytest.fixture(scope="session", autouse=True)
def schema():
    migrate.main()


@pytest.fixture(autouse=True)
def seed():
    now = datetime.now(UTC).replace(minute=0, second=0, microsecond=0)
    with psycopg.connect(database_conninfo(), autocommit=True) as conn:
        conn.execute("TRUNCATE locations RESTART IDENTITY CASCADE")
        conn.execute(
            "INSERT INTO locations (name, country, latitude, longitude) VALUES"
            " ('Tel Aviv', 'IL', 32.08, 34.78), ('London', 'GB', 51.51, -0.13)"
        )
        for hours_ago, temp in [(0, 25.0), (1, 24.0), (48, 18.0)]:
            conn.execute(
                "INSERT INTO weather_observations (location_id, observed_at, temperature_c) VALUES (1, %s, %s)",
                (now - timedelta(hours=hours_ago), temp),
            )
        conn.execute(
            "INSERT INTO weather_observations (location_id, observed_at, temperature_c) VALUES (2, %s, 12.0)",
            (now,),
        )


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c


def test_health_and_ready(client):
    assert client.get("/healthz").status_code == 200
    assert client.get("/readyz").status_code == 200


def test_locations(client):
    names = [loc["name"] for loc in client.get("/api/locations").json()]
    assert names == ["London", "Tel Aviv"]


def test_current_returns_latest_per_location(client):
    by_name = {r["name"]: r for r in client.get("/api/weather/current").json()}
    assert by_name["Tel Aviv"]["temperature_c"] == 25.0
    assert by_name["London"]["temperature_c"] == 12.0


def test_history_window(client):
    assert len(client.get("/api/weather/1/history?hours=24").json()) == 2
    assert len(client.get("/api/weather/1/history?hours=72").json()) == 3


def test_history_unknown_location(client):
    assert client.get("/api/weather/999/history").status_code == 404


def test_metrics_exposed(client):
    client.get("/api/locations")
    body = client.get("/metrics").text
    assert 'http_requests_total{method="GET",route="/api/locations",status="200"}' in body


def test_freshness_and_pool_metrics(client):
    body = client.get("/metrics").text
    assert 'weather_latest_observation_timestamp_seconds{location="Tel Aviv"}' in body
    assert 'weather_latest_observation_timestamp_seconds{location="London"}' in body
    assert 'weather_db_pool_connections{state="max"} 10.0' in body
    assert "weather_db_pool_requests_waiting" in body
