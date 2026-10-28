"""Apply SQL migrations in order. Run as a Kubernetes Job / Helm pre-upgrade hook,
never on API startup - so N replicas don't race each other on schema changes."""

import logging
import pathlib
import sys

import psycopg

from app.config import database_conninfo

MIGRATIONS_DIR = pathlib.Path(__file__).resolve().parent.parent / "migrations"
LOCK_ID = 727274  # arbitrary constant for pg_advisory_lock

log = logging.getLogger("migrate")


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    with psycopg.connect(database_conninfo(), autocommit=True) as conn:
        # Advisory lock: safe even if two migration jobs ever run concurrently.
        conn.execute("SELECT pg_advisory_lock(%s)", (LOCK_ID,))
        try:
            conn.execute(
                "CREATE TABLE IF NOT EXISTS schema_migrations ("
                " version TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())"
            )
            applied = {r[0] for r in conn.execute("SELECT version FROM schema_migrations")}
            for path in sorted(MIGRATIONS_DIR.glob("*.sql")):
                if path.name in applied:
                    continue
                log.info("applying %s", path.name)
                with conn.transaction():
                    conn.execute(path.read_text())
                    conn.execute("INSERT INTO schema_migrations (version) VALUES (%s)", (path.name,))
            log.info("migrations up to date")
        finally:
            conn.execute("SELECT pg_advisory_unlock(%s)", (LOCK_ID,))
    return 0


if __name__ == "__main__":
    sys.exit(main())
