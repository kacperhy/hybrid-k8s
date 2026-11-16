from unittest import mock

import redis

import app as api


def test_visit_increments_counter():
    with mock.patch.object(api.r, "incr", return_value=42) as incr:
        res = api.app.test_client().post("/api/visit")
    body = res.get_json()
    assert res.status_code == 200
    assert body["visits"] == 42
    assert body["cluster"] == api.CLUSTER_NAME
    incr.assert_called_once_with("visits")


def test_info_reads_without_incrementing():
    with mock.patch.object(api.r, "get", return_value=b"7"), \
         mock.patch.object(api.r, "incr") as incr:
        res = api.app.test_client().get("/api/info")
    assert res.get_json()["visits"] == 7
    incr.assert_not_called()


def test_info_when_counter_empty():
    with mock.patch.object(api.r, "get", return_value=None):
        res = api.app.test_client().get("/api/info")
    assert res.get_json()["visits"] == 0


def test_visit_requires_post():
    assert api.app.test_client().get("/api/visit").status_code == 405


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
