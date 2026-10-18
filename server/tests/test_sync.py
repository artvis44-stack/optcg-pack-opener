import importlib
import os
import sys

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))


@pytest.fixture
def server(tmp_path, monkeypatch):
    monkeypatch.setenv("OPTCG_SYNC_DB", str(tmp_path / "sync.db"))
    monkeypatch.delenv("OPTCG_SYNC_INVITE", raising=False)
    monkeypatch.delenv("OPTCG_SYNC_REGISTRATION", raising=False)
    import optcg_sync
    mod = importlib.reload(optcg_sync)
    with TestClient(mod.app) as client:
        client.mod = mod
        yield client


PASSWORD = "grand line 2026"


def register(c, name="luffy", device="laptop"):
    r = c.post("/v1/accounts", json={"username": name, "password": PASSWORD, "device": device})
    assert r.status_code == 201, r.text
    return {"Authorization": "Bearer " + r.json()["token"]}


def test_register_login_and_password_is_hashed(server):
    register(server)
    r = server.post("/v1/sessions", json={"username": "LUFFY", "password": PASSWORD, "device": "desktop"})
    assert r.status_code == 201
    db = server.mod.connect()
    row = db.execute("SELECT pw_hash FROM users").fetchone()
    assert row["pw_hash"].startswith("$argon2id$") and PASSWORD not in row["pw_hash"]
    tokens = [x["token_hash"] for x in db.execute("SELECT token_hash FROM sessions")]
    assert r.json()["token"] not in tokens and len(tokens) == 2


def test_rejects_bad_input(server):
    bad = [{"username": "a", "password": PASSWORD, "device": "x"},
           {"username": "zoro'; DROP TABLE users;--", "password": PASSWORD, "device": "x"},
           {"username": "zoro", "password": "short", "device": "x"},
           {"username": "zoro", "password": "zoro-is-lost-again", "device": "x"},
           {"username": "zoro", "password": PASSWORD, "device": ""}]
    for body in bad:
        assert server.post("/v1/accounts", json=body).status_code in (400, 422)
    register(server, "zoro")
    assert server.post("/v1/accounts", json={"username": "Zoro", "password": PASSWORD, "device": "x"}).status_code == 409


def test_wrong_password_and_lockout_dont_reveal_accounts(server):
    register(server)
    for name in ("luffy", "nobody"):
        codes = [server.post("/v1/sessions", json={"username": name, "password": "wrong password!", "device": "x"}).status_code
                 for _ in range(5)]
        assert codes == [401] * 5
        # locked now, even with the right password, and the same for a name that doesn't exist
        r = server.post("/v1/sessions", json={"username": name, "password": PASSWORD, "device": "x"})
        assert r.status_code == 429
        server.mod.login_limit.hits.clear()


def test_ip_rate_limit(server):
    codes = [server.post("/v1/sessions", json={"username": "u%d" % i, "password": "x" * 10, "device": "x"}).status_code
             for i in range(11)]
    assert codes[-1] == 429


def test_needs_a_token(server):
    assert server.get("/v1/docs").status_code == 401
    assert server.get("/v1/docs", headers={"Authorization": "Bearer optcg_nope"}).status_code == 401


def test_docs_versioning_and_conflicts(server):
    a = register(server)
    b = {"Authorization": "Bearer " + server.post("/v1/sessions", json={"username": "luffy", "password": PASSWORD, "device": "pc"}).json()["token"]}
    assert server.put("/v1/docs/progress", headers=a, json={"base": 0, "data": {"berries": 1}}).json() == {"version": 1}
    # b didn't see version 1: refused, and handed the current copy
    r = server.put("/v1/docs/progress", headers=b, json={"base": 0, "data": {"berries": 5}})
    assert r.status_code == 409 and r.json()["version"] == 1 and r.json()["data"] == {"berries": 1}
    assert server.put("/v1/docs/progress", headers=b, json={"base": 1, "data": {"berries": 6}}).json() == {"version": 2}
    assert server.get("/v1/docs/progress", headers=a).json() == {"version": 2, "data": {"berries": 6}}
    assert server.get("/v1/docs", headers=a).json()["docs"]["progress"]["version"] == 2
    for name in ("../etc/passwd", "settings", "case-OP-01;x"):
        assert server.put("/v1/docs/" + name, headers=a, json={"base": 0, "data": {}}).status_code == 404
    assert server.put("/v1/docs/case-OP-01", headers=a, json={"base": 0, "data": {"box": 1}}).status_code == 200


def test_accounts_are_separate(server):
    a = register(server, "luffy")
    z = register(server, "zoro")
    server.put("/v1/docs/collection", headers=a, json={"base": 0, "data": {"cards": {"OP-01:x.png": {"count": 1}}}})
    assert server.get("/v1/docs/collection", headers=z).status_code == 404
    assert server.get("/v1/docs", headers=z).json() == {"docs": {}}


def test_size_limits(server):
    a = register(server)
    big = {"x": "a" * (server.mod.MAX_DOC + 10)}
    assert server.put("/v1/docs/progress", headers=a, json={"base": 0, "data": big}).status_code == 413
    r = server.put("/v1/docs/progress", headers={**a, "Content-Type": "application/json"},
                   content=b"{" + b" " * (server.mod.MAX_REQUEST + 1) + b"}")
    assert r.status_code == 413


def test_devices_logout_and_password_change(server):
    a = register(server)
    b = {"Authorization": "Bearer " + server.post("/v1/sessions", json={"username": "luffy", "password": PASSWORD, "device": "pc"}).json()["token"]}
    devices = server.get("/v1/sessions", headers=a).json()["devices"]
    assert sorted(d["device"] for d in devices) == ["laptop", "pc"]
    assert server.post("/v1/account/password", headers=a, json={"old": "wrong one!!", "new": "another long one"}).status_code == 401
    assert server.post("/v1/account/password", headers=a, json={"old": PASSWORD, "new": "another long one"}).status_code == 200
    assert server.get("/v1/docs", headers=b).status_code == 401      # signed out elsewhere
    assert server.get("/v1/docs", headers=a).status_code == 200
    assert server.post("/v1/sessions", json={"username": "luffy", "password": PASSWORD, "device": "x"}).status_code == 401
    assert server.delete("/v1/sessions/current", headers=a).status_code == 200
    assert server.get("/v1/docs", headers=a).status_code == 401


def test_revoke_other_device_only_own(server):
    a = register(server, "luffy")
    z = register(server, "zoro")
    zid = server.get("/v1/sessions", headers=z).json()["devices"][0]["id"]
    assert server.delete("/v1/sessions/" + zid, headers=a).status_code == 404
    assert server.delete("/v1/sessions/" + zid, headers=z).status_code == 200


def test_delete_account(server):
    a = register(server)
    server.put("/v1/docs/progress", headers=a, json={"base": 0, "data": {"berries": 1}})
    assert server.post("/v1/account/delete", headers=a, json={"password": PASSWORD}).status_code == 200
    db = server.mod.connect()
    assert db.execute("SELECT COUNT(*) FROM docs").fetchone()[0] == 0
    assert db.execute("SELECT COUNT(*) FROM sessions").fetchone()[0] == 0


def test_invite_only(server, monkeypatch):
    server.mod.REGISTRATION, server.mod.INVITE = "invite", "secret-code"
    body = {"username": "nami", "password": PASSWORD, "device": "x"}
    assert server.post("/v1/accounts", json=body).status_code == 403
    assert server.post("/v1/accounts", json={**body, "invite": "secret-code"}).status_code == 201


def test_security_headers(server):
    r = server.get("/v1/health")
    assert r.headers["x-content-type-options"] == "nosniff" and r.headers["cache-control"] == "no-store"
    assert server.get("/docs").status_code == 404 and server.get("/openapi.json").status_code == 404
