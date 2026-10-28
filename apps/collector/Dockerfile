# syntax=docker/dockerfile:1.7
FROM python:3.12-slim AS build
WORKDIR /build
COPY requirements.txt .
# --require-hashes: every package (incl. transitive) must match the lock file hash.
RUN pip install --no-cache-dir --require-hashes --prefix=/install -r requirements.txt

FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN groupadd --system --gid 10001 app && useradd --system --uid 10001 --gid app --no-create-home app
COPY --from=build /install /usr/local
WORKDIR /srv
COPY collector ./collector
# Default list for local runs; in Kubernetes a ConfigMap is mounted at /config.
COPY locations.json /config/locations.json
USER 10001
CMD ["python", "-m", "collector.main"]
