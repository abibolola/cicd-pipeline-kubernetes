"""Redis-backed storage for short codes."""
import os

import redis

ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
COUNTER_KEY = "shortener:counter"
URL_PREFIX = "shortener:url:"


def encode(number: int) -> str:
    """Base62-encode an integer into a short code."""
    if number == 0:
        return ALPHABET[0]
    digits = []
    while number:
        number, remainder = divmod(number, 62)
        digits.append(ALPHABET[remainder])
    return "".join(reversed(digits))


class Store:
    def __init__(self, client: redis.Redis):
        self.client = client

    def ping(self) -> bool:
        try:
            return bool(self.client.ping())
        except redis.RedisError:
            return False

    def create(self, url: str) -> str:
        counter = self.client.incr(COUNTER_KEY)
        code = encode(counter)
        self.client.set(f"{URL_PREFIX}{code}", url)
        return code

    def resolve(self, code: str) -> str | None:
        return self.client.get(f"{URL_PREFIX}{code}")


def build_store() -> Store:
    client = redis.Redis(
        host=os.getenv("REDIS_HOST", "localhost"),
        port=int(os.getenv("REDIS_PORT", "6379")),
        password=os.getenv("REDIS_PASSWORD") or None,
        decode_responses=True,
        socket_connect_timeout=2,
        socket_timeout=2,
    )
    return Store(client)
