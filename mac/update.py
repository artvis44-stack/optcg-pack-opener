#!/usr/bin/env python3
"""OPTCG auto-updater for macOS (run every few hours by a LaunchAgent, see install.sh).

Checks the latest GitHub release; if it's newer than this copy, downloads the
release's optcg.bundle, fast-forwards the repo to it, refreshes the Python
packages, restarts the desktop showcase on the new code and shows a
notification. A pack opener that's open is left alone (the next launch runs
the new version). The patch notes of what was installed (every release since
the last one, newest first) go in patch-notes.json, which the pack opener
shows the next time it opens.

usage: update.py            check and update if there's a newer release
       update.py --force    reinstall the latest release even if it's not newer
       update.py --check    just say what's installed and what's out, as a line of
                            JSON ({"have", "latest", "newer"} or {"error"}); the pack
                            opener's update button asks this

The repo may be private: then it needs a GitHub token, read from
$OPTCG_GITHUB_TOKEN, ~/Library/Application Support/optcg/github-token, or `gh`.
Log: ~/Library/Logs/optcg-update.log
"""
import fcntl
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO = "artvis44-stack/optcg-pack-opener"
API = f"https://api.github.com/repos/{REPO}/releases/latest"
HERE = Path(__file__).resolve().parent          # .../optcg/mac
ROOT = HERE.parent                               # the git checkout
VENV_PY = HERE / ".venv" / "bin" / "python"
DATA = Path.home() / "Library" / "Application Support" / "optcg"
LOG = Path.home() / "Library" / "Logs" / "optcg-update.log"
INSTALLED = DATA / "installed-version"   # what this updater last put in place
PATCH_NOTES = DATA / "patch-notes.json"   # what's new: the pack opener shows it once


def log(msg):
    line = time.strftime("%Y-%m-%d %H:%M:%S ") + msg
    print(line)
    try:
        LOG.parent.mkdir(parents=True, exist_ok=True)
        with open(LOG, "a") as f:
            f.write(line + "\n")
    except OSError:
        pass


def notify(text):
    if sys.platform == "darwin":
        esc = text.replace("\\", "\\\\").replace('"', '\\"')   # the tag name comes from GitHub
        script = f'display notification "{esc}" with title "OPTCG"'
        subprocess.run(["osascript", "-e", script], check=False)


def token():
    if os.environ.get("OPTCG_GITHUB_TOKEN"):
        return os.environ["OPTCG_GITHUB_TOKEN"].strip()
    f = DATA / "github-token"
    if f.exists():
        return f.read_text().strip()
    try:
        out = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True, timeout=10)
        if out.returncode == 0:
            return out.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        pass
    return ""


def api_get(url, tok, accept="application/vnd.github+json"):
    req = urllib.request.Request(url, headers={"Accept": accept, "User-Agent": "optcg-updater"})
    if tok:
        req.add_header("Authorization", f"Bearer {tok}")
    return urllib.request.urlopen(req, timeout=60)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def download_asset(asset, tok, dest):
    """Release assets of a private repo come from the API, which redirects to
    storage that must NOT get the token -- so follow that redirect by hand."""
    if not tok:
        urllib.request.urlretrieve(asset["browser_download_url"], dest)
        return
    req = urllib.request.Request(asset["url"], headers={
        "Accept": "application/octet-stream", "User-Agent": "optcg-updater",
        "Authorization": f"Bearer {tok}"})
    opener = urllib.request.build_opener(NoRedirect)
    try:
        resp = opener.open(req, timeout=60)
        data = resp.read()
    except urllib.error.HTTPError as e:
        if e.code not in (301, 302, 303, 307, 308):
            raise
        location = e.headers["Location"]
        data = urllib.request.urlopen(urllib.request.Request(location, headers={"User-Agent": "optcg-updater"}),
                                      timeout=120).read()
    Path(dest).write_bytes(data)


def version(tag):
    return tuple(int(n) for n in re.findall(r"\d+", tag)[:3]) or (0,)


def git(*args, check=True):
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True, check=check)


def current_tag():
    # the newest of: the nearest tag in git, and what we last installed (bundles
    # up to v1.2.1 were made before their own tag, so git alone can lag behind)
    out = git("describe", "--tags", "--abbrev=0", check=False)
    tags = [out.stdout.strip() if out.returncode == 0 else "v0.0.0"]
    if INSTALLED.exists():
        tags.append(INSTALLED.read_text().strip())
    return max(tags, key=version)


def restart_showcase():
    """(Re)start the desktop companion on the new code -- it's always meant to be running."""
    out = subprocess.run(["pgrep", "-f", f"{HERE}/optcg.py --showcase"], capture_output=True, text=True)
    for pid in out.stdout.split():
        if pid.strip() and int(pid) != os.getpid():
            subprocess.run(["kill", pid], check=False)
    time.sleep(1)
    subprocess.Popen([str(VENV_PY), str(HERE / "optcg.py"), "--showcase"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    log("started the desktop companion")


def save_patch_notes(have, latest, release, tok):
    """What's new since `have`: every release after it up to `latest`, newest first. The
    pack opener shows it next time it opens (and marks it seen)."""
    notes = []
    try:
        for r in json.load(api_get(f"https://api.github.com/repos/{REPO}/releases?per_page=30", tok)):
            if not r.get("draft") and version(have) < version(r["tag_name"]) <= version(latest):
                notes.append({"version": r["tag_name"], "date": (r.get("published_at") or "")[:10], "notes": (r.get("body") or "").strip()})
    except (OSError, ValueError, KeyError) as e:
        log(f"couldn't list the releases for the patch notes: {e}")
    if not any(n["version"] == latest for n in notes):
        notes.append({"version": latest, "date": (release.get("published_at") or "")[:10], "notes": (release.get("body") or "").strip()})
    notes.sort(key=lambda n: version(n["version"]), reverse=True)
    try:
        PATCH_NOTES.write_text(json.dumps({"from": have, "to": latest, "at": int(time.time()), "seen": False, "releases": notes}, indent=1))
    except OSError as e:
        log(f"couldn't save the patch notes: {e}")


def check(release):
    """--check: one line of JSON for the pack opener"""
    if isinstance(release, str):
        print(json.dumps({"error": release}), flush=True)
        return 1
    latest, have = release["tag_name"], current_tag()
    print(json.dumps({"have": have, "latest": latest, "newer": version(latest) > version(have)}), flush=True)
    return 0


def main():
    force = "--force" in sys.argv
    tok = token()
    try:
        release = json.load(api_get(API, tok))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            release = ("can't see the releases: the repo is private and there's no token "
                       f"(put one in {DATA / 'github-token'})")
        else:
            release = f"GitHub API error {e.code}"
    except OSError as e:
        release = f"offline? {e}"
    if "--check" in sys.argv:
        return check(release)
    if isinstance(release, str):
        log(release)
        return 1

    latest, have = release["tag_name"], current_tag()
    if version(latest) <= version(have) and not force:
        log(f"up to date ({have})")
        return 0
    asset = next((a for a in release.get("assets", []) if a["name"] == "optcg.bundle"), None)
    if not asset:
        log(f"{latest} has no optcg.bundle asset")
        return 1

    # the update button and the LaunchAgent could both be at it
    DATA.mkdir(parents=True, exist_ok=True)
    lock = open(DATA / ".update.lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        log("another update is running")
        return 1
    log(f"updating {have} -> {latest}")
    before_reqs = (HERE / "requirements.txt").read_text()
    with tempfile.TemporaryDirectory() as tmp:
        bundle = os.path.join(tmp, "optcg.bundle")
        download_asset(asset, tok, bundle)
        git("bundle", "verify", bundle)
        git("fetch", "--tags", "--force", bundle, "main")
        if git("merge", "--ff-only", "FETCH_HEAD", check=False).returncode != 0:
            # local edits in the way: keep them on a branch, then take the release
            backup = time.strftime("backup-%Y%m%d-%H%M%S")
            git("branch", backup)
            git("reset", "--hard", "FETCH_HEAD")
            log(f"local changes kept on branch {backup}")

    if (HERE / "requirements.txt").read_text() != before_reqs or force:
        log("updating Python packages")
        subprocess.run([str(VENV_PY), "-m", "pip", "install", "-q", "-r", str(HERE / "requirements.txt")], check=False)
    subprocess.run(["bash", str(HERE / "install.sh"), "--agents-only"], check=False)
    restart_showcase()
    DATA.mkdir(parents=True, exist_ok=True)
    INSTALLED.write_text(latest)
    save_patch_notes(have, latest, release, tok)
    log(f"updated to {latest}")
    notify(f"Updated to {latest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
