FROM python:3.12-slim-bookworm AS openapi-plugin

# Release v2.2 is built for Trino 484. Verify the artifact before extraction.
RUN python - <<'PY'
import hashlib
import io
from pathlib import Path
import shutil
import urllib.request
import zipfile

url = "https://github.com/nineinchnick/trino-openapi/releases/download/v2.2/trino-openapi-2.2.zip"
expected = "b7033a243ed8dd27fbbe256d75eb27d44fab95bdad355c06b7d87325dc041b54"
with urllib.request.urlopen(url, timeout=120) as response:
    data = response.read()
if hashlib.sha256(data).hexdigest() != expected:
    raise RuntimeError("OpenAPI plugin SHA-256 mismatch")
with zipfile.ZipFile(io.BytesIO(data)) as archive:
    archive.extractall("/tmp/openapi")
source = Path("/tmp/openapi/trino-openapi-2.2")
if not source.is_dir():
    raise RuntimeError("Unexpected OpenAPI plugin archive layout")
shutil.copytree(source, "/plugin")
PY

FROM trinodb/trino:484
COPY --from=openapi-plugin --chown=trino:trino /plugin/ /usr/lib/trino/plugin/openapi/
