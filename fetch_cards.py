#!/usr/bin/env python3
"""Download OPTCG set data + card images into the local cache.

Usage: fetch_cards.py [SET_ID]   (default OP-17)

Writes $XDG_CACHE_HOME/optcg/<SET_ID>/cards.json and one image per card.
Data comes from the community API at optcgapi.com. Card art belongs to
Bandai / Eiichiro Oda -- this is a personal cache, don't redistribute it.
"""
import glob
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from concurrent.futures import ThreadPoolExecutor

API = "https://optcgapi.com/api/sets/{}/"
# Bandai's official product shot of the sealed pack (e.g. .../boosters/op17/...)
PACK_URL = "https://en.onepiece-cardgame.com/products/boosters/{}/images/others/product_pack.webp"
# The official rule manual has flat scans of the card backs
RULES_PDF = "https://en.onepiece-cardgame.com/pdf/rule_manual.pdf"
UA = {"User-Agent": "Mozilla/5.0 (optcg-pack-widget/1.0)"}

SET_ID = sys.argv[1] if len(sys.argv) > 1 else "OP-17"
ROOT = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "optcg")
CACHE = os.path.join(ROOT, SET_ID)
ASSETS = os.path.join(ROOT, "assets")


def tier_of(card):
    """Map a card to the pull tier used by the pack generator."""
    name, rarity = card["card_name"], card["rarity"]
    if "Pandaman" in name:
        return "PANDA"
    if "(SP)" in name:
        return "SP"
    if "(Manga)" in name:
        return "MANGA"
    leader = card.get("card_type") == "Leader"
    if "Super" in name and "Alternate Art" in name:
        return "SUPER_L" if leader else "SUPER"
    if rarity == "TR" or "(TR)" in name:
        return "TR"
    if "(Alternate Art)" in name:
        if rarity == "SEC":
            return "SEC_AA"
        return "L_AA" if leader else "AA"
    return rarity


def fetch(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
        return r.read()


def download(card):
    # variants can share a card id, so name files after the (unique) URL
    dest = os.path.join(CACHE, os.path.basename(card["url"]))
    if not os.path.exists(dest) or os.path.getsize(dest) == 0:
        data = fetch(card["url"])
        with open(dest + ".part", "wb") as f:
            f.write(data)
        os.replace(dest + ".part", dest)
    card["image"] = dest
    del card["url"]
    return card


def magick(*args):
    subprocess.run(["magick", *args], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def image_size(path):
    out = subprocess.run(["magick", "identify", "-format", "%w %h", path],
                         check=True, capture_output=True, text=True).stdout
    return tuple(int(v) for v in out.split())


def fetch_pack_image():
    """Official sealed-pack photo, trimmed to the pack -> <set>/pack.png"""
    dest = os.path.join(CACHE, "pack.png")
    if os.path.exists(dest):
        return
    try:
        data = fetch(PACK_URL.format(SET_ID.lower().replace("-", "")))
    except Exception as e:
        print(f"no official pack image for {SET_ID} ({e}); using the drawn pack")
        return
    raw = os.path.join(CACHE, "pack.webp")
    with open(raw, "wb") as f:
        f.write(data)
    if shutil.which("magick"):
        magick(raw, "-trim", "+repage", dest)
        os.remove(raw)
    else:
        os.replace(raw, dest)  # Qt sniffs the format, untrimmed is fine
    print("pack image ->", dest)


def fetch_card_backs():
    """Blue (deck) and red (Leader) card backs from the rule manual -> assets/"""
    blue = os.path.join(ASSETS, "back.png")
    red = os.path.join(ASSETS, "back_leader.png")
    if os.path.exists(blue) and os.path.exists(red):
        return
    if not (shutil.which("pdfimages") and shutil.which("magick")):
        print("card backs need poppler (pdfimages) + imagemagick; using the drawn back")
        return
    os.makedirs(ASSETS, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        pdf = os.path.join(tmp, "rules.pdf")
        with open(pdf, "wb") as f:
            f.write(fetch(RULES_PDF))
        subprocess.run(["pdfimages", "-png", pdf, os.path.join(tmp, "i")],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        imgs = sorted(glob.glob(os.path.join(tmp, "i-*.png")))
        sizes = [image_size(p) for p in imgs]

        # blue back: the 365x510 colour image, directly followed by its soft mask
        for i, size in enumerate(sizes[:-1]):
            if size == (365, 510) and sizes[i + 1] == size:
                magick(imgs[i], imgs[i + 1], "-alpha", "off", "-compose", "CopyOpacity", "-composite", blue)
                break
        # red back: the large first-page scan; give it the same rounded corners
        for p, (w, h) in zip(imgs, sizes):
            if (w, h) == (869, 1214):
                r = round(w * 0.05)
                magick(p, "(", "-size", f"{w}x{h}", "xc:black", "-fill", "white",
                       "-draw", f"roundrectangle 0,0 {w - 1},{h - 1} {r},{r}", ")",
                       "-alpha", "off", "-compose", "CopyOpacity", "-composite",
                       "-resize", "600x", red)
                break
    for path in (blue, red):
        print(("card back -> " if os.path.exists(path) else "couldn't find card back for ") + path)


def main():
    os.makedirs(CACHE, exist_ok=True)
    fetch_pack_image()
    fetch_card_backs()
    raw = json.loads(fetch(API.format(SET_ID)))

    cards, seen = [], set()
    for c in raw:
        cid = c["card_image_id"]
        key = (cid, c["card_name"])
        if key in seen or not c.get("card_image"):
            continue
        seen.add(key)
        cards.append({
            "id": cid,
            "name": c["card_name"],
            "rarity": c["rarity"],
            "tier": tier_of(c),
            "color": c.get("card_color") or "",
            "type": c.get("card_type") or "",
            "url": c["card_image"],
        })

    print(f"{SET_ID}: {len(cards)} cards, downloading images to {CACHE}")
    with ThreadPoolExecutor(max_workers=8) as pool:
        cards = list(pool.map(download, cards))

    out = {"set": SET_ID, "set_name": raw[0]["set_name"] if raw else SET_ID, "cards": cards}
    with open(os.path.join(CACHE, "cards.json"), "w") as f:
        json.dump(out, f, indent=1)
    print("done")


if __name__ == "__main__":
    main()
