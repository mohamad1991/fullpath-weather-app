import json

import httpx
import pytest

from collector import main as c

SAMPLE = {
    "current": {
        "time": "2026-10-28T12:00",
        "temperature_2m": 24.1,
        "apparent_temperature": 25.0,
        "relative_humidity_2m": 60,
        "precipitation": 0.0,
        "wind_speed_10m": 12.3,
        "wind_direction_10m": 270,
        "weather_code": 1,
    }
}
LOCS = [{"name": "A", "country": "X", "latitude": 1, "longitude": 2}]


def test_to_observation_maps_fields_and_utc():
    obs = c.to_observation(SAMPLE)
    assert obs["temperature_c"] == 24.1
    assert obs["observed_at"].tzinfo is not None
    assert obs["observed_at"].isoformat() == "2026-10-28T12:00:00+00:00"


def test_load_locations_validates(tmp_path):
    f = tmp_path / "l.json"
    f.write_text(json.dumps([{"name": "A"}]))
    with pytest.raises(ValueError):
        c.load_locations(str(f))


def test_fetch_single_location_normalised_to_list():
    transport = httpx.MockTransport(lambda req: httpx.Response(200, json=SAMPLE))
    with httpx.Client(transport=transport) as client:
        assert c.fetch_current(client, LOCS) == [SAMPLE]


def test_fetch_retries_then_succeeds(monkeypatch):
    monkeypatch.setattr(c.time, "sleep", lambda _: None)
    calls = iter([httpx.Response(503), httpx.Response(200, json=[SAMPLE])])
    transport = httpx.MockTransport(lambda req: next(calls))
    with httpx.Client(transport=transport) as client:
        assert c.fetch_current(client, LOCS) == [SAMPLE]


def test_fetch_gives_up(monkeypatch):
    monkeypatch.setattr(c.time, "sleep", lambda _: None)
    transport = httpx.MockTransport(lambda req: httpx.Response(500))
    with httpx.Client(transport=transport) as client, pytest.raises(httpx.HTTPStatusError):
        c.fetch_current(client, LOCS)
