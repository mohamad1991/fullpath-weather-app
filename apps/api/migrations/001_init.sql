-- Locations we track. Seeded/upserted by the collector from its config.
CREATE TABLE IF NOT EXISTS locations (
    id          SERIAL PRIMARY KEY,
    name        TEXT             NOT NULL,
    country     TEXT             NOT NULL,
    latitude    DOUBLE PRECISION NOT NULL,
    longitude   DOUBLE PRECISION NOT NULL,
    timezone    TEXT             NOT NULL DEFAULT 'UTC',
    created_at  TIMESTAMPTZ      NOT NULL DEFAULT now(),
    UNIQUE (name, country)
);

-- Append-only history. One row per location per provider observation time.
-- The UNIQUE constraint makes collector runs idempotent (retries / overlapping runs
-- never create duplicates).
CREATE TABLE IF NOT EXISTS weather_observations (
    id                      BIGSERIAL PRIMARY KEY,
    location_id             INTEGER     NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
    observed_at             TIMESTAMPTZ NOT NULL,
    temperature_c           REAL,
    apparent_temperature_c  REAL,
    humidity_pct            REAL,
    precipitation_mm        REAL,
    wind_speed_kmh          REAL,
    wind_direction_deg      REAL,
    weather_code            SMALLINT,
    fetched_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (location_id, observed_at)
);

-- Serves both "latest per location" and "history for a location" queries.
CREATE INDEX IF NOT EXISTS idx_obs_location_time
    ON weather_observations (location_id, observed_at DESC);
