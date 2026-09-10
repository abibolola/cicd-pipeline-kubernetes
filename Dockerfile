# Multi-stage: build deps in one layer, ship only what runs.
# Hardening note: pin the base by digest (python:3.12-slim@sha256:...) once
# you have chosen one, so rebuilds are byte-identical.
FROM python:3.12-slim AS builder

WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


FROM python:3.12-slim

RUN useradd --uid 10001 --system --no-create-home --shell /sbin/nologin appuser

COPY --from=builder /install /usr/local
WORKDIR /app
COPY app/ ./app/

USER 10001
EXPOSE 8000

ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
