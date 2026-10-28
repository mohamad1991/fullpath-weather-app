# syntax=docker/dockerfile:1.7
# ---- build stage: compile wheels with full toolchain ----
FROM python:3.12-slim AS build
WORKDIR /build
COPY requirements.txt .
# --require-hashes: every package (incl. transitive) must match the lock file hash.
RUN pip install --no-cache-dir --require-hashes --prefix=/install -r requirements.txt

# ---- runtime stage: minimal, non-root, no build tools ----
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN groupadd --system --gid 10001 app && useradd --system --uid 10001 --gid app --no-create-home app
COPY --from=build /install /usr/local
WORKDIR /srv
COPY app ./app
COPY migrations ./migrations
USER 10001
EXPOSE 8000
# Same image runs the migration Job: `python -m app.migrate`
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
