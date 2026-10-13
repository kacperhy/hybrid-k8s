from unittest import mock

import redis

import app as api


def test_info_increments_visits():
    with mock.patch.object(api.r, "incr", return_value=42):
        res = api.app.test_client().get("/api/info")
    body = res.get_json()
    assert res.status_code == 200
    assert body["visits"] == 42
    assert body["cluster"] == api.CLUSTER_NAME


def test_healthz_fails_without_redis():
    with mock.patch.object(api.r, "ping", side_effect=redis.ConnectionError):
        res = api.app.test_client().get("/healthz")
    assert res.status_code == 503


def test_healthz_ok():
    with mock.patch.object(api.r, "ping", return_value=True):
        res = api.app.test_client().get("/healthz")
    assert res.status_code == 200


def test_metrics():
    res = api.app.test_client().get("/metrics")
    assert b"app_requests_total" in res.data
