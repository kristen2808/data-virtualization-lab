FROM apache/superset:6.0.0

USER root
RUN uv pip install --python /app/.venv/bin/python \
      "SQLAlchemy==1.4.54" "psycopg2-binary==2.9.11" "trino[sqlalchemy]==0.340.0" \
    && uv pip check --python /app/.venv/bin/python

COPY --chown=superset:superset superset_config.py init_superset.py /app/local/
ENV SUPERSET_CONFIG_PATH=/app/local/superset_config.py
USER superset

# One process keeps the local in-memory caches consistent; no Celery/Redis.
CMD ["gunicorn", "--bind", "0.0.0.0:8088", "--workers", "1", "--worker-class", "gthread", "--threads", "4", "--timeout", "120", "superset.app:create_app()"]
