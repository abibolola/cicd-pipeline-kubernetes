"""Tests run against fakeredis so CI needs no Redis container."""
import fakeredis
import pytest
from fastapi.testclient import TestClient

from app.main import app, get_store
from app.store import Store, encode


@pytest.fixture
def client():
    store = Store(fakeredis.FakeStrictRedis(decode_responses=True))
    app.dependency_overrides[get_store] = lambda: store
    yield TestClient(app)
    app.dependency_overrides.clear()


def test_encode_is_base62():
    assert encode(0) == "0"
    assert encode(61) == "Z"
    assert encode(62) == "10"


def test_healthz_does_not_touch_redis(client):
    assert client.get("/healthz").status_code == 200


def test_readyz_reports_ready(client):
    assert client.get("/readyz").json()["status"] == "ready"


def test_shorten_then_follow(client):
    created = client.post("/shorten", json={"url": "https://example.com/a"})
    assert created.status_code == 201
    code = created.json()["code"]

    followed = client.get(f"/{code}", follow_redirects=False)
    assert followed.status_code == 307
    assert followed.headers["location"] == "https://example.com/a"


def test_unknown_code_is_404(client):
    assert client.get("/nope", follow_redirects=False).status_code == 404


def test_rejects_invalid_url(client):
    assert client.post("/shorten", json={"url": "not-a-url"}).status_code == 422
