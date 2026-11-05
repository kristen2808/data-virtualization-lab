"""Local synchronous Superset configuration; credentials are runtime-only."""

import os

from sqlalchemy.engine import URL

SECRET_KEY = os.environ["SUPERSET_SECRET_KEY"]
if len(SECRET_KEY) < 42:
    raise ValueError("SUPERSET_SECRET_KEY must contain at least 42 characters")

SQLALCHEMY_DATABASE_URI = URL.create(
    "postgresql+psycopg2",
    username="superset",
    password=os.environ["SUPERSET_DB_PASSWORD"],
    host="postgres",
    port=5432,
    database="superset_metadata",
).render_as_string(hide_password=False)
SQLALCHEMY_ENGINE_OPTIONS = {"pool_pre_ping": True}

FEATURE_FLAGS = {"GLOBAL_ASYNC_QUERIES": False, "ALERT_REPORTS": False}
CACHE_CONFIG = {"CACHE_TYPE": "NullCache"}
DATA_CACHE_CONFIG = {"CACHE_TYPE": "NullCache"}
FILTER_STATE_CACHE_CONFIG = {"CACHE_TYPE": "SimpleCache", "CACHE_DEFAULT_TIMEOUT": 3600}
EXPLORE_FORM_DATA_CACHE_CONFIG = {"CACHE_TYPE": "SimpleCache", "CACHE_DEFAULT_TIMEOUT": 3600}
RESULTS_BACKEND = None
WTF_CSRF_ENABLED = True
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = "Lax"
# HTTP is bound to the host loopback only for this local PoC.
SESSION_COOKIE_SECURE = False
TALISMAN_ENABLED = False
