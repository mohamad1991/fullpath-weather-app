import os


def database_conninfo() -> str:
    """Build a libpq conninfo string from discrete env vars.

    Discrete vars (rather than one DATABASE_URL) map cleanly onto Kubernetes
    Secrets synced from AWS Secrets Manager, and avoid URL-encoding issues
    with generated passwords.
    """
    parts = {
        "host": os.environ.get("DB_HOST", "localhost"),
        "port": os.environ.get("DB_PORT", "5432"),
        "dbname": os.environ.get("DB_NAME", "weather"),
        "user": os.environ.get("DB_USER", "weather"),
        "password": os.environ.get("DB_PASSWORD", ""),
        "sslmode": os.environ.get("DB_SSLMODE", "prefer"),
        "connect_timeout": os.environ.get("DB_CONNECT_TIMEOUT", "5"),
        "application_name": "weather-api",
    }
    return " ".join(f"{k}='{v}'" for k, v in parts.items())


POOL_MIN = int(os.environ.get("DB_POOL_MIN", "1"))
POOL_MAX = int(os.environ.get("DB_POOL_MAX", "10"))
POOL_MAX_LIFETIME = float(os.environ.get("DB_POOL_MAX_LIFETIME", "600"))
MAX_HISTORY_HOURS = int(os.environ.get("MAX_HISTORY_HOURS", "720"))  # 30 days
