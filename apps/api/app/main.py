import logging
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Query, Response
from prometheus_client import CONTENT_TYPE_LATEST, REGISTRY, Counter, Histogram, generate_latest
from prometheus_client.core import GaugeMetricFamily
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool
from starlette.requests import Request

from app import config

logging.basicConfig(level=logging.INFO, format='{"ts":"%(asctime)s","level":"%(levelname)s","msg":"%(message)s"}')
log = logging.getLogger("api")

REQUESTS = Counter("http_requests_total", "HTTP requests", ["method", "route", "status"])
LATENCY = Histogram("http_request_duration_seconds", "HTTP request latency", ["method", "route"])

pool: ConnectionPool | None = None


class ScrapeTimeCollector:
    """Metrics computed when Prometheus scrapes, not on the request path.

    - Data freshness: newest observation per location, exported as a *timestamp* so
      PromQL computes age with time() - x (an "age" gauge would be stale between scrapes).
      This is what catches a silently broken collector: no errors anywhere, just old data.
    - Pool saturation: in-use vs max connections and waiting requests (USE method).
    """

    def collect(self):
        if pool is None:
            return
        stats = pool.get_stats()
        size = GaugeMetricFamily("weather_db_pool_connections", "Connections in the pool", labels=["state"])
        size.add_metric(["total"], stats.get("pool_size", 0))
        size.add_metric(["idle"], stats.get("pool_available", 0))
        size.add_metric(["max"], config.POOL_MAX)
        yield size
        yield GaugeMetricFamily(
            "weather_db_pool_requests_waiting",
            "Requests waiting for a connection",
            value=stats.get("requests_waiting", 0),
        )

        fresh = GaugeMetricFamily(
            "weather_latest_observation_timestamp_seconds",
            "Unix time of the newest stored observation per location",
            labels=["location"],
        )
        try:
            with pool.connection(timeout=2) as conn:
                rows = conn.execute(
                    "SELECT l.name, extract(epoch FROM max(o.observed_at))::float8 AS ts"
                    " FROM locations l JOIN weather_observations o ON o.location_id = l.id GROUP BY l.name"
                ).fetchall()
        except Exception as exc:  # noqa: BLE001 - a scrape must never crash on DB trouble
            log.warning("freshness metric unavailable: %s", exc)
            return  # series disappear -> absent()/staleness alerts cover it
        for r in rows:
            fresh.add_metric([r["name"]], r["ts"])
        yield fresh


REGISTRY.register(ScrapeTimeCollector())


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
        # After a DB failover (CNPG promotion / RDS Multi-AZ DNS flip) pooled connections
        # point at the dead primary. Validate on checkout so they're silently replaced
        # instead of surfacing as 500s, and recycle periodically.
        check=ConnectionPool.check_connection,
        max_lifetime=config.POOL_MAX_LIFETIME,
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
