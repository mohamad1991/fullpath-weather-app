import logging
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Query, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool
from starlette.requests import Request

from app import config

logging.basicConfig(level=logging.INFO, format='{"ts":"%(asctime)s","level":"%(levelname)s","msg":"%(message)s"}')
log = logging.getLogger("api")

REQUESTS = Counter("http_requests_total", "HTTP requests", ["method", "route", "status"])
LATENCY = Histogram("http_request_duration_seconds", "HTTP request latency", ["method", "route"])

pool: ConnectionPool | None = None


@asynccontextmanager
async def lifespan(_: FastAPI):
    global pool
    # open=False + wait=False: the API starts even if the DB is briefly down;
    # /readyz keeps the pod out of the Service until the DB is reachable.
    pool = ConnectionPool(
        config.database_conninfo(),
        min_size=config.POOL_MIN,
        max_size=config.POOL_MAX,
        kwargs={"row_factory": dict_row},
        open=False,
    )
    pool.open(wait=False)
    yield
    pool.close()


app = FastAPI(title="Weather API", version="1.0.0", lifespan=lifespan)


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    route = request.scope.get("route")
    path = route.path if route else "unmatched"  # template path -> bounded label cardinality
    LATENCY.labels(request.method, path).observe(time.perf_counter() - start)
    REQUESTS.labels(request.method, path, response.status_code).inc()
    return response


def _query(sql: str, params: tuple = ()) -> list[dict]:
    with pool.connection() as conn:
        return conn.execute(sql, params).fetchall()


@app.get("/healthz")
def healthz():
    """Liveness: process is up. Deliberately does NOT touch the DB, so a DB outage
    doesn't make Kubernetes restart every API pod."""
    return {"status": "ok"}


@app.get("/readyz")
def readyz():
    """Readiness: can we serve traffic (DB reachable)?"""
    try:
        with pool.connection(timeout=2) as conn:
            conn.execute("SELECT 1")
    except Exception as exc:  # noqa: BLE001
        log.warning("readiness check failed: %s", exc)
        raise HTTPException(status_code=503, detail="database unavailable") from exc
    return {"status": "ready"}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/api/locations")
def list_locations():
    return _query("SELECT id, name, country, latitude, longitude, timezone FROM locations ORDER BY name")


@app.get("/api/weather/current")
def current_weather():
    return _query(
        """
        SELECT DISTINCT ON (l.id)
               l.id AS location_id, l.name, l.country, l.latitude, l.longitude,
               o.observed_at, o.temperature_c, o.apparent_temperature_c, o.humidity_pct,
               o.precipitation_mm, o.wind_speed_kmh, o.wind_direction_deg, o.weather_code
        FROM locations l
        JOIN weather_observations o ON o.location_id = l.id
        ORDER BY l.id, o.observed_at DESC
        """
    )


@app.get("/api/weather/{location_id}/history")
def weather_history(location_id: int, hours: int = Query(24, ge=1)):
    hours = min(hours, config.MAX_HISTORY_HOURS)
    if not _query("SELECT 1 FROM locations WHERE id = %s", (location_id,)):
        raise HTTPException(status_code=404, detail="location not found")
    return _query(
        """
        SELECT observed_at, temperature_c, apparent_temperature_c, humidity_pct,
               precipitation_mm, wind_speed_kmh, wind_direction_deg, weather_code
        FROM weather_observations
        WHERE location_id = %s AND observed_at >= now() - make_interval(hours => %s)
        ORDER BY observed_at
        """,
        (location_id, hours),
    )
