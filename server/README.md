# Sync server

Keeps your collection, berries, streak and wanted posters the same on every
computer: each one signs in to an account here (Y in the pack opener), and
the desktop companion syncs every few seconds. Changes made on two computers
at once are merged, not overwritten (see `app/sync.js`).

One small Python program (`optcg_sync.py`) with a SQLite database, run behind
Caddy for HTTPS. What it does for security:

- passwords hashed with **Argon2id**; never stored or logged in the clear
- each computer gets its own **random sign-in token**; the database only keeps
  its SHA-256, tokens expire after 180 days unused, and you can remove a
  computer, sign out, or change the password (which signs out the others)
- **rate limits** per IP and an **exponential lockout** after 5 wrong
  passwords for a username (the same for names that don't exist, and wrong
  usernames take as long as wrong passwords, so it doesn't reveal who has an
  account)
- optional **invite code** or closed registration
- size limits (4 MB per save, 64 MB per account), strict validation of
  usernames and save names, parameterised SQL only
- listens on localhost only; Caddy provides HTTPS (the app refuses to send a
  password over plain http to anything but localhost)
- the systemd unit runs it as its own user with a read-only system, the
  database readable by that user only

## Install on the VPS (Debian / Ubuntu)

You need a DNS name pointing at the VPS (e.g. `sync.example.com`) and ports
80 and 443 open.

```sh
# Caddy (HTTPS)
sudo apt install -y caddy python3-venv

# the server, as its own user
sudo useradd --system --home /var/lib/optcg-sync --shell /usr/sbin/nologin optcg-sync
sudo mkdir -p /opt/optcg-sync
sudo cp optcg_sync.py requirements.txt /opt/optcg-sync/
sudo python3 -m venv /opt/optcg-sync/venv
sudo /opt/optcg-sync/venv/bin/pip install -r /opt/optcg-sync/requirements.txt

# start it (edit the unit first if you want an invite code)
sudo cp optcg-sync.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now optcg-sync

# HTTPS: put your name in the Caddyfile, then
sudo cp Caddyfile /etc/caddy/Caddyfile
sudo systemctl reload caddy

curl https://sync.example.com/v1/health    # {"ok":true,...}
```

Only you? Create your account, then set `OPTCG_SYNC_REGISTRATION=closed` in
the unit (`sudo systemctl edit --full optcg-sync`) so nobody else can. Or set
`OPTCG_SYNC_INVITE=<a long random code>` and give it to the people you want.

## Use it

In the pack opener press **Y**: enter `https://sync.example.com`, a username,
a password (10+ characters) and a name for the computer, then **Create
account**. On your other computers press Y and **Sign in**; if both already
have saves you choose between using the account's (this computer's are kept
in `~/.local/share/optcg/sync/backup-*`) or combining both.

## Updating, backups

- Update: copy the new `optcg_sync.py` to `/opt/optcg-sync/` and
  `sudo systemctl restart optcg-sync`.
- Back up: `sudo sqlite3 /var/lib/optcg-sync/optcg-sync.db ".backup /root/optcg-sync-$(date +%F).db"`
  (safe while it runs).
- Logs: `journalctl -u optcg-sync`.

## Tests

```sh
pip install -r requirements.txt pytest httpx
python -m pytest tests
```
