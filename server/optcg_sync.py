"""OPTCG sync server: accounts, and a versioned copy of each player's saves.

The pack opener keeps working on its local files; when you sign in it pushes
them here and pulls what your other computers pushed (see app/sync.js). This
server only stores documents ("collection", "progress", "case-<set>"), each
with a version number: an update names the version it was based on and is
refused with 409 if another device got there first, so the client can merge
and retry instead of overwriting.

Security:
  - passwords hashed with Argon2id (re-hashed on login when the parameters
    change), at most a few hashes at once so logins can't exhaust memory
  - sign-in gives each device its own random token; only its SHA-256 is
    stored, it expires when unused and can be revoked (sign out, the device
    list, a password change signs out the other devices)
  - rate limits per IP, and an exponential lockout per username after failed
    sign-ins (kept for unknown usernames too, so it doesn't reveal accounts);
    unknown usernames still cost a hash, so timing doesn't either
  - optional invite code (or closed registration), size and count quotas,
    request size limit, strict input validation, parameterised SQL only
  - no HTML, no CORS, security headers on every response; meant to run on
    localhost behind a TLS reverse proxy (Caddy), see server/README.md

Run: uvicorn optcg_sync:app --host 127.0.0.1 --port 8787 --proxy-headers --no-server-header
Settings (environment):
  OPTCG_SYNC_DB            SQLite database path (default ./optcg-sync.db)
  OPTCG_SYNC_REGISTRATION  open | invite | closed (default: invite if an invite code is set, else open)
  OPTCG_SYNC_INVITE        the invite code new accounts need
  OPTCG_SYNC_TOKEN_DAYS    days a device stays signed in without syncing (default 180)
"""

import hashlib
import hmac
import json
import os
import re
import secrets
import sqlite3
import threading
import time
from collections import defaultdict, deque
from contextlib import asynccontextmanager, contextmanager

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError
from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, field_validator

DB_PATH = os.environ.get("OPTCG_SYNC_DB", "optcg-sync.db")
INVITE = os.environ.get("OPTCG_SYNC_INVITE", "")
REGISTRATION = os.environ.get("OPTCG_SYNC_REGISTRATION", "invite" if INVITE else "open")
TOKEN_DAYS = int(os.environ.get("OPTCG_SYNC_TOKEN_DAYS", "180"))

MAX_REQUEST = 6 * 1024 * 1024        # bytes in one request
MAX_DOC = 4 * 1024 * 1024            # one stored document
MAX_TOTAL = 64 * 1024 * 1024         # everything one account stores
MAX_DOCS = 100
MAX_SESSIONS = 20                    # signed-in devices per account

USERNAME = re.compile(r"^[A-Za-z0-9_.-]{3,32}$")
DOC_NAME = re.compile(r"^(collection|progress|case-[A-Za-z0-9-]{1,24})$")
TOKEN_PREFIX = "optcg_"

hasher = PasswordHasher()            # Argon2id, 64 MiB, 3 passes
hash_slots = threading.BoundedSemaphore(4)
# verified against when the username doesn't exist, so it takes as long
DUMMY_HASH = hasher.hash(secrets.token_hex(16))


# ---- database ---------------------------------------------------------------------

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id          INTEGER PRIMARY KEY,
    username    TEXT NOT NULL UNIQUE COLLATE NOCASE,
    pw_hash     TEXT NOT NULL,
    created_at  INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
    id          TEXT PRIMARY KEY,               -- public id (device list), not the token
    user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash  TEXT NOT NULL UNIQUE,           -- sha256 of the token
    device      TEXT NOT NULL,
    created_at  INTEGER NOT NULL,
    last_used   INTEGER NOT NULL,
    expires_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS sessions_user ON sessions(user_id);
CREATE TABLE IF NOT EXISTS docs (
    user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    version     INTEGER NOT NULL,
    data        TEXT NOT NULL,
    size        INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL,
    device      TEXT NOT NULL,
    PRIMARY KEY (user_id, name)
);
CREATE TABLE IF NOT EXISTS login_failures (
    username     TEXT PRIMARY KEY COLLATE NOCASE,   -- any username tried, existing or not
    count        INTEGER NOT NULL,
    locked_until INTEGER NOT NULL
);
"""


def connect():
    db = sqlite3.connect(DB_PATH, timeout=10, isolation_level=None)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys = ON")
    db.execute("PRAGMA busy_timeout = 10000")
    return db


def init_db():
    db = connect()
    db.execute("PRAGMA journal_mode = WAL")
    db.executescript(SCHEMA)
    db.close()
    try:
        os.chmod(DB_PATH, 0o600)
    except OSError:
        pass


@contextmanager
def transaction():
    db = connect()
    try:
        db.execute("BEGIN IMMEDIATE")
        yield db
        db.execute("COMMIT")
    except BaseException:
        db.execute("ROLLBACK")
        raise
    finally:
        db.close()


def now():
    return int(time.time())


# ---- rate limits ------------------------------------------------------------------

class RateLimit:
    """At most `limit` hits per key in a sliding `window` (seconds)."""

    def __init__(self, limit, window):
        self.limit, self.window = limit, window
        self.hits = defaultdict(deque)
        self.lock = threading.Lock()

    def hit(self, key):
        t = time.monotonic()
        with self.lock:
            q = self.hits[key]
            while q and q[0] <= t - self.window:
                q.popleft()
            if len(q) >= self.limit:
                raise HTTPException(429, "Too many requests. Try again later.")
            q.append(t)
            if len(self.hits) > 100_000:   # don't grow without bound
                for k in [k for k, v in self.hits.items() if not v or v[-1] <= t - self.window]:
                    del self.hits[k]


login_limit = RateLimit(10, 300)        # sign-ins per IP per 5 minutes
register_limit = RateLimit(5, 3600)     # new accounts per IP per hour
api_limit = RateLimit(300, 60)          # sync calls per device per minute

LOCKOUT_AFTER = 5                       # failed sign-ins before a lockout
LOCKOUT_MAX = 3600


def client_ip(request: Request):
    return request.client.host if request.client else "?"


def check_lockout(db, username):
    row = db.execute("SELECT locked_until FROM login_failures WHERE username = ?", (username,)).fetchone()
    if row and row["locked_until"] > now():
        raise HTTPException(429, "Too many failed sign-ins. Try again later.")


def record_failure(db, username):
    row = db.execute("SELECT count FROM login_failures WHERE username = ?", (username,)).fetchone()
    count = (row["count"] if row else 0) + 1
    locked = now() + min(LOCKOUT_MAX, 60 * 2 ** (count - LOCKOUT_AFTER)) if count >= LOCKOUT_AFTER else 0
    db.execute("INSERT INTO login_failures (username, count, locked_until) VALUES (?, ?, ?) "
               "ON CONFLICT(username) DO UPDATE SET count = excluded.count, locked_until = excluded.locked_until",
               (username, count, locked))


# ---- passwords and tokens ------------------------------------------------------------

def hash_password(password):
    with hash_slots:
        return hasher.hash(password)


def verify_password(pw_hash, password):
    with hash_slots:
        try:
            return hasher.verify(pw_hash, password)
        except (VerifyMismatchError, VerificationError, InvalidHashError):
            return False


def token_hash(token):
    return hashlib.sha256(token.encode()).hexdigest()


def new_session(db, user_id, device):
    token = TOKEN_PREFIX + secrets.token_urlsafe(32)
    t = now()
    db.execute("INSERT INTO sessions (id, user_id, token_hash, device, created_at, last_used, expires_at) "
               "VALUES (?, ?, ?, ?, ?, ?, ?)",
               (secrets.token_hex(8), user_id, token_hash(token), device, t, t, t + TOKEN_DAYS * 86400))
    # too many devices: drop the longest unused
    db.execute("DELETE FROM sessions WHERE user_id = ? AND id NOT IN "
               "(SELECT id FROM sessions WHERE user_id = ? ORDER BY last_used DESC LIMIT ?)",
               (user_id, user_id, MAX_SESSIONS))
    return token


class Session:
    def __init__(self, row):
        self.id, self.user_id, self.device, self.username = row["id"], row["user_id"], row["device"], row["username"]


def session(authorization: str = Header(default="")):
    """The signed-in device, from 'Authorization: Bearer <token>'."""
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token.startswith(TOKEN_PREFIX) or len(token) > 100:
        raise HTTPException(401, "Not signed in.")
    t = now()
    db = connect()
    try:
        row = db.execute("SELECT s.id, s.user_id, s.device, s.last_used, s.expires_at, u.username "
                         "FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = ?",
                         (token_hash(token),)).fetchone()
        if not row or row["expires_at"] <= t:
            raise HTTPException(401, "Not signed in.")
        if t - row["last_used"] > 60:   # sliding expiry, written at most once a minute
            db.execute("UPDATE sessions SET last_used = ?, expires_at = ? WHERE id = ?",
                       (t, t + TOKEN_DAYS * 86400, row["id"]))
    finally:
        db.close()
    api_limit.hit(row["id"])
    return Session(row)


# ---- requests -------------------------------------------------------------------------

def check_device(v):
    v = " ".join(v.split())
    if not 1 <= len(v) <= 64 or not v.isprintable():
        raise ValueError("device name: 1-64 printable characters")
    return v


class Register(BaseModel):
    username: str = Field(max_length=32)
    password: str = Field(max_length=256)
    device: str = Field(max_length=200)
    invite: str = Field(default="", max_length=200)

    @field_validator("username")
    @classmethod
    def _username(cls, v):
        if not USERNAME.match(v):
            raise ValueError("username: 3-32 letters, digits, '.', '_' or '-'")
        return v

    @field_validator("device")
    @classmethod
    def _device(cls, v):
        return check_device(v)


class Login(BaseModel):
    username: str = Field(max_length=32)
    password: str = Field(max_length=256)
    device: str = Field(max_length=200)

    @field_validator("device")
    @classmethod
    def _device(cls, v):
        return check_device(v)


class PasswordChange(BaseModel):
    old: str = Field(max_length=256)
    new: str = Field(max_length=256)


class Confirm(BaseModel):
    password: str = Field(max_length=256)


class DocPut(BaseModel):
    base: int = Field(ge=0)      # the version this is based on; 0: the document is new
    data: dict


def password_problem(password, username):
    if len(password) < 10:
        return "Use at least 10 characters for the password."
    if username.lower() in password.lower():
        return "The password can't contain the username."
    if len(set(password)) < 4:
        return "That password is too simple."
    return ""


# ---- the app ------------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(_app):
    init_db()
    yield


app = FastAPI(title="OPTCG sync", docs_url=None, redoc_url=None, openapi_url=None, lifespan=lifespan)


@app.middleware("http")
async def guard(request: Request, call_next):
    # refuse big bodies before reading them
    length = request.headers.get("content-length")
    if length is not None and (not length.isdigit() or int(length) > MAX_REQUEST):
        return JSONResponse({"detail": "Request too large."}, status_code=413)
    if request.method in ("POST", "PUT") and length is None:
        return JSONResponse({"detail": "Content-Length required."}, status_code=411)
    response = await call_next(request)
    response.headers["Cache-Control"] = "no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Content-Security-Policy"] = "default-src 'none'; frame-ancestors 'none'"
    if request.url.scheme == "https":
        response.headers["Strict-Transport-Security"] = "max-age=31536000"
    return response


@app.get("/v1/health")
def health():
    return {"ok": True, "registration": REGISTRATION}


@app.post("/v1/accounts", status_code=201)
def register(body: Register, request: Request):
    register_limit.hit(client_ip(request))
    if REGISTRATION == "closed":
        raise HTTPException(403, "This server isn't taking new accounts.")
    if REGISTRATION == "invite" and not (INVITE and hmac.compare_digest(body.invite.encode(), INVITE.encode())):
        raise HTTPException(403, "That invite code isn't right.")
    problem = password_problem(body.password, body.username)
    if problem:
        raise HTTPException(400, problem)
    pw_hash = hash_password(body.password)
    with transaction() as db:
        try:
            cur = db.execute("INSERT INTO users (username, pw_hash, created_at) VALUES (?, ?, ?)",
                             (body.username, pw_hash, now()))
        except sqlite3.IntegrityError:
            raise HTTPException(409, "That username is taken.")
        token = new_session(db, cur.lastrowid, body.device)
    return {"token": token, "username": body.username}


@app.post("/v1/sessions", status_code=201)
def login(body: Login, request: Request):
    login_limit.hit(client_ip(request))
    db = connect()
    try:
        check_lockout(db, body.username)
        user = db.execute("SELECT id, username, pw_hash FROM users WHERE username = ?", (body.username,)).fetchone()
    finally:
        db.close()
    ok = verify_password(user["pw_hash"] if user else DUMMY_HASH, body.password) and user is not None
    if not ok:
        with transaction() as db:   # committed: the failure must count
            record_failure(db, body.username)
        raise HTTPException(401, "Wrong username or password.")
    with transaction() as db:
        db.execute("DELETE FROM login_failures WHERE username = ?", (body.username,))
        if hasher.check_needs_rehash(user["pw_hash"]):
            db.execute("UPDATE users SET pw_hash = ? WHERE id = ?", (hash_password(body.password), user["id"]))
        token = new_session(db, user["id"], body.device)
    return {"token": token, "username": user["username"]}


@app.delete("/v1/sessions/current")
def logout(s: Session = Depends(session)):
    with transaction() as db:
        db.execute("DELETE FROM sessions WHERE id = ?", (s.id,))
    return {"ok": True}


@app.get("/v1/sessions")
def devices(s: Session = Depends(session)):
    db = connect()
    try:
        rows = db.execute("SELECT id, device, created_at, last_used FROM sessions WHERE user_id = ? "
                          "ORDER BY last_used DESC", (s.user_id,)).fetchall()
    finally:
        db.close()
    return {"devices": [dict(r, current=r["id"] == s.id) for r in rows]}


@app.delete("/v1/sessions/{sid}")
def revoke(sid: str, s: Session = Depends(session)):
    if not re.fullmatch(r"[0-9a-f]{16}", sid):
        raise HTTPException(404, "No such device.")
    with transaction() as db:
        n = db.execute("DELETE FROM sessions WHERE id = ? AND user_id = ?", (sid, s.user_id)).rowcount
    if not n:
        raise HTTPException(404, "No such device.")
    return {"ok": True}


@app.get("/v1/account")
def account(s: Session = Depends(session)):
    db = connect()
    try:
        u = db.execute("SELECT username, created_at FROM users WHERE id = ?", (s.user_id,)).fetchone()
        used = db.execute("SELECT COUNT(*) AS n, COALESCE(SUM(size), 0) AS bytes FROM docs WHERE user_id = ?",
                          (s.user_id,)).fetchone()
    finally:
        db.close()
    return {"username": u["username"], "created_at": u["created_at"], "device": s.device,
            "docs": used["n"], "bytes": used["bytes"], "quota": MAX_TOTAL}


def check_password(s: Session, request: Request, password):
    login_limit.hit(client_ip(request))
    db = connect()
    try:
        check_lockout(db, s.username)
        pw_hash = db.execute("SELECT pw_hash FROM users WHERE id = ?", (s.user_id,)).fetchone()["pw_hash"]
    finally:
        db.close()
    if not verify_password(pw_hash, password):
        with transaction() as db:
            record_failure(db, s.username)
        raise HTTPException(401, "Wrong password.")


@app.post("/v1/account/password")
def change_password(body: PasswordChange, request: Request, s: Session = Depends(session)):
    check_password(s, request, body.old)
    problem = password_problem(body.new, s.username)
    if problem:
        raise HTTPException(400, problem)
    pw_hash = hash_password(body.new)
    with transaction() as db:
        db.execute("UPDATE users SET pw_hash = ? WHERE id = ?", (pw_hash, s.user_id))
        # everyone else signs in again with the new password
        db.execute("DELETE FROM sessions WHERE user_id = ? AND id != ?", (s.user_id, s.id))
    return {"ok": True}


@app.post("/v1/account/delete")
def delete_account(body: Confirm, request: Request, s: Session = Depends(session)):
    check_password(s, request, body.password)
    with transaction() as db:
        db.execute("DELETE FROM users WHERE id = ?", (s.user_id,))   # sessions and docs cascade
    return {"ok": True}


# ---- documents ------------------------------------------------------------------------------

def doc_name(name):
    if not DOC_NAME.match(name):
        raise HTTPException(404, "No such document.")
    return name


@app.get("/v1/docs")
def list_docs(s: Session = Depends(session)):
    db = connect()
    try:
        rows = db.execute("SELECT name, version, updated_at, device FROM docs WHERE user_id = ?", (s.user_id,)).fetchall()
    finally:
        db.close()
    return {"docs": {r["name"]: {"version": r["version"], "updated_at": r["updated_at"], "device": r["device"]}
                     for r in rows}}


@app.get("/v1/docs/{name}")
def get_doc(name: str, s: Session = Depends(session)):
    doc_name(name)
    db = connect()
    try:
        row = db.execute("SELECT version, data FROM docs WHERE user_id = ? AND name = ?", (s.user_id, name)).fetchone()
    finally:
        db.close()
    if not row:
        raise HTTPException(404, "No such document.")
    return {"version": row["version"], "data": json.loads(row["data"])}


@app.put("/v1/docs/{name}")
def put_doc(name: str, body: DocPut, s: Session = Depends(session)):
    doc_name(name)
    data = json.dumps(body.data, separators=(",", ":"), ensure_ascii=False)
    size = len(data.encode())
    if size > MAX_DOC:
        raise HTTPException(413, "That document is too big.")
    with transaction() as db:
        row = db.execute("SELECT version, data, size FROM docs WHERE user_id = ? AND name = ?",
                         (s.user_id, name)).fetchone()
        current = row["version"] if row else 0
        if body.base != current:
            # someone else got there first: hand back theirs to merge with
            return JSONResponse({"detail": "Changed on another device.", "version": current,
                                 "data": json.loads(row["data"]) if row else None}, status_code=409)
        used = db.execute("SELECT COUNT(*) AS n, COALESCE(SUM(size), 0) AS bytes FROM docs WHERE user_id = ?",
                          (s.user_id,)).fetchone()
        if not row and used["n"] >= MAX_DOCS:
            raise HTTPException(413, "Too many documents.")
        if used["bytes"] - (row["size"] if row else 0) + size > MAX_TOTAL:
            raise HTTPException(413, "Your account is full.")
        db.execute("INSERT INTO docs (user_id, name, version, data, size, updated_at, device) VALUES (?, ?, ?, ?, ?, ?, ?) "
                   "ON CONFLICT(user_id, name) DO UPDATE SET version = excluded.version, data = excluded.data, "
                   "size = excluded.size, updated_at = excluded.updated_at, device = excluded.device",
                   (s.user_id, name, current + 1, data, size, now(), s.device))
    return {"version": current + 1}
