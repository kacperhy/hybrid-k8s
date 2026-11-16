"""API usługi demonstracyjnej.

Zwraca informację o tym, który klaster obsłużył żądanie, oraz licznik
odwiedzin przechowywany w Redisie (stan, który przenosimy między
klastrami przez Velero).
"""
import os
import socket
import time

import redis
from flask import Flask, jsonify
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

CLUSTER_NAME = os.getenv("CLUSTER_NAME", "unknown")
CLUSTER_REGION = os.getenv("CLUSTER_REGION", "unknown")
CLUSTER_COLOR = os.getenv("CLUSTER_COLOR", "#888888")
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))

app = Flask(__name__)
r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, socket_timeout=1, socket_connect_timeout=1)

REQUESTS = Counter("app_requests_total", "Liczba żądań do API", ["endpoint", "cluster", "status"])
LATENCY = Histogram("app_request_seconds", "Czas obsługi żądania", ["endpoint", "cluster"])


def _info(endpoint, count_visit):
    """Wspólna odpowiedź: który klaster/pod odpowiada + licznik odwiedzin z Redisa."""
    start = time.time()
    try:
        visits = r.incr("visits") if count_visit else int(r.get("visits") or 0)
        status = "ok"
    except redis.RedisError:
        visits = None
        status = "redis_error"
    REQUESTS.labels(endpoint, CLUSTER_NAME, status).inc()
    LATENCY.labels(endpoint, CLUSTER_NAME).observe(time.time() - start)
    return jsonify(
        cluster=CLUSTER_NAME,
        region=CLUSTER_REGION,
        color=CLUSTER_COLOR,
        pod=socket.gethostname(),
        visits=visits,
        status=status,
    )


@app.get("/api/info")
def info():
    """Odczyt stanu – NIE zwiększa licznika (strona odpytuje to co 2 s, HAProxy i sondy też)."""
    return _info("info", count_visit=False)


@app.post("/api/visit")
def visit():
    """Jedna odwiedzina = jedno wejście na stronę (frontend woła to raz, przy załadowaniu)."""
    return _info("visit", count_visit=True)


@app.get("/healthz")
def healthz():
    """Health check całego łańcucha api -> redis.

    Używany przez Kubernetes (readiness) oraz przez Azure Traffic Manager
    (przez frontend), więc awaria Redisa również powoduje przełączenie ruchu.
    """
    try:
        r.ping()
    except redis.RedisError:
        REQUESTS.labels("healthz", CLUSTER_NAME, "fail").inc()
        return jsonify(status="fail", cluster=CLUSTER_NAME), 503
    REQUESTS.labels("healthz", CLUSTER_NAME, "ok").inc()
    return jsonify(status="ok", cluster=CLUSTER_NAME)


@app.get("/livez")
def livez():
    return "ok"


@app.get("/metrics")
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
