"""URL shortener API.

Health endpoints are split deliberately:
  /healthz  liveness  - is the process alive
  /readyz   readiness - can it actually serve traffic (Redis reachable)
"""
import os

from fastapi import Depends, FastAPI, HTTPException
from fastapi.responses import JSONResponse, RedirectResponse
from pydantic import BaseModel, HttpUrl

from .store import Store, build_store

APP_VERSION = os.getenv("APP_VERSION", "dev")
BASE_URL = os.getenv("BASE_URL", "http://localhost:8000")

app = FastAPI(title="URL Shortener", version=APP_VERSION)
_store: Store | None = None


def get_store() -> Store:
    global _store
    if _store is None:
        _store = build_store()
    return _store


class ShortenRequest(BaseModel):
    url: HttpUrl


class ShortenResponse(BaseModel):
    code: str
    short_url: str


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok", "version": APP_VERSION}


@app.get("/readyz")
def readyz(store: Store = Depends(get_store)):
    if not store.ping():
        return JSONResponse({"status": "unavailable"}, status_code=503)
    return {"status": "ready"}


@app.post("/shorten", response_model=ShortenResponse, status_code=201)
def shorten(payload: ShortenRequest, store: Store = Depends(get_store)):
    code = store.create(str(payload.url))
    return ShortenResponse(code=code, short_url=f"{BASE_URL.rstrip('/')}/{code}")


@app.get("/{code}")
def follow(code: str, store: Store = Depends(get_store)):
    url = store.resolve(code)
    if url is None:
        raise HTTPException(status_code=404, detail="unknown code")
    return RedirectResponse(url, status_code=307)
