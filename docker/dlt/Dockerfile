FROM python:3.12-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    RUNTIME__DLTHUB_TELEMETRY=false

# The declarative REST API source is included in dlt itself.
RUN pip install --no-cache-dir "dlt[postgres]==1.32.0" \
    && useradd --create-home --uid 1000 dlt

WORKDIR /app
COPY pipelines/api_users.py /app/pipelines/api_users.py
USER dlt

CMD ["python", "/app/pipelines/api_users.py"]
