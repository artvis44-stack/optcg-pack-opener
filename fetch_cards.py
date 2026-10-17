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
# Bandai's official product shots of the sealed pack and the display box
PRODUCT_URL = "https://en.onepiece-cardgame.com/products/boosters/{}/images/others/{}.webp"
# The official rule manual has flat scans of the card backs
RULES_PDF = "https://en.onepiece-cardgame.com/pdf/rule_manual.pdf"
# DON!! cards aren't in optcgapi; these are TCGplayer's scans of the booster
# DON!! (the Double Pack Set ones don't come in boosters, so they're left out)
TCGPLAYER_IMG = "https://tcgplayer-cdn.tcgplayer.com/product/{}_in_1000x1000.jpg"
DON_CARDS = {
    "OP-17": [
        (712747, "DON!! Card", "DON"),
        (712749, "DON!! Card (Rocks)", "DON"),
        (712750, "DON!! Card (The Four Emperors)", "DON"),
        (712748, "DON!! Card (Luffy and Loki)", "DON"),
        (710859, "DON!! Card (Gold)", "DON_GOLD"),
        (710860, "DON!! Card (Luffy and Loki) (Gold)", "DON_GOLD"),
        (711421, "DON!! Card (The Four Emperors) (Gold)", "DON_GOLD"),
        (711420, "DON!! Card (Rocks) (Special Foil)", "DON_SP"),
    ],
}
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


def fetch_product_image(product, name):
    """Official product photo, trimmed -> <set>/<name>.png"""
    dest = os.path.join(CACHE, name + ".png")
    if os.path.exists(dest):
        return
    try:
        data = fetch(PRODUCT_URL.format(SET_ID.lower().replace("-", ""), product))
    except Exception as e:
        print(f"no official {name} image for {SET_ID} ({e}); using the drawn one")
        return
    raw = os.path.join(CACHE, name + ".webp")
    with open(raw, "wb") as f:
        f.write(data)
    if shutil.which("magick"):
        magick(raw, "-trim", "+repage", dest)
        os.remove(raw)
    else:
        os.replace(raw, dest)  # Qt sniffs the format, untrimmed is fine
    print(name, "image ->", dest)


def mean_brightness(path):
    out = subprocess.run(["magick", path, "-format", "%[fx:mean]", "info:"],
                         check=True, capture_output=True, text=True).stdout
    return float(out)


def fetch_don_cards():
    """DON!! scans for the set, trimmed to the card and sized like the others."""
    cards = []
    for n, (product, name, tier) in enumerate(DON_CARDS.get(SET_ID, []), 1):
        dest = os.path.join(CACHE, f"don_{product}.png")
        if not os.path.exists(dest):
            raw = dest + ".jpg"
            try:
                with open(raw, "wb") as f:
                    f.write(fetch(TCGPLAYER_IMG.format(product)))
            except Exception as e:
                print(f"couldn't download {name} ({e})")
                continue
            if shutil.which("magick"):
                # product photos have a light margin around the card
                magick(raw, "-fuzz", "12%", "-trim", "+repage", "-resize", "600x838!", dest)
                os.remove(raw)
            else:
                os.replace(raw, dest)
        cards.append({"id": f"{SET_ID.replace('-', '')}-DON-{n}", "name": name, "rarity": "DON",
                      "tier": tier, "color": "", "type": "DON!!", "image": dest})
    return cards


def fetch_card_backs():
    """Blue (deck), red (Leader) and DON!! card backs from the rule manual -> assets/"""
    blue = os.path.join(ASSETS, "back.png")
    red = os.path.join(ASSETS, "back_leader.png")
    don = os.path.join(ASSETS, "back_don.png")
    if all(os.path.exists(p) for p in (blue, red, don)):
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
        # DON!! back: the white/green one among the 301x421 image + mask pairs
        pairs = [i for i, size in enumerate(sizes[:-1]) if size == (301, 421) and sizes[i + 1] == size]
        if pairs:
            i = max(pairs, key=lambda i: mean_brightness(imgs[i]))
            magick(imgs[i], imgs[i + 1], "-alpha", "off", "-compose", "CopyOpacity", "-composite", don)
    for path in (blue, red, don):
        print(("card back -> " if os.path.exists(path) else "couldn't find card back for ") + path)


def main():
    os.makedirs(CACHE, exist_ok=True)
    fetch_product_image("product_pack", "pack")
    fetch_product_image("product_booster", "box")
    fetch_card_backs()
    out_path = os.path.join(CACHE, "cards.json")
    try:
        raw = json.loads(fetch(API.format(SET_ID)))
    except Exception as e:
        if not os.path.exists(out_path):
            raise
        # API down: keep the cached card list, just refresh the DON!! cards
        print(f"optcgapi unreachable ({e}); reusing cached card list")
        with open(out_path) as f:
            out = json.load(f)
        out["cards"] = [c for c in out["cards"] if c["type"] != "DON!!"] + fetch_don_cards()
        with open(out_path, "w") as f:
            json.dump(out, f, indent=1)
        print("done")
        return

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
    cards += fetch_don_cards()

    out = {"set": SET_ID, "set_name": raw[0]["set_name"] if raw else SET_ID, "cards": cards}
    with open(out_path, "w") as f:
        json.dump(out, f, indent=1)
    print("done")


if __name__ == "__main__":
    main()
