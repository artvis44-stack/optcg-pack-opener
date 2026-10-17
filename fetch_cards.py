#!/usr/bin/env python3
"""Download OPTCG set data + card images into the local cache.

Usage: fetch_cards.py [SET_ID]   one set (default OP-17), e.g. OP-05, EB-01, PRB-02
       fetch_cards.py all        every set in app/sets.json (~40 MB each)
       fetch_cards.py list       the known sets and whether they're downloaded
       fetch_cards.py previews   just the pack/box photos of every set (for the set picker)

Writes $XDG_CACHE_HOME/optcg/<SET_ID>/cards.json, one image per card, and the
set's pack/box photos; the card backs (shared by all sets) go in assets/.
Card data comes from the community API at optcgapi.com, product and DON!!
photos from Bandai / TCGplayer. Card art belongs to Bandai / Eiichiro Oda --
this is a personal cache, don't redistribute it.
"""
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from concurrent.futures import ThreadPoolExecutor

API = "https://optcgapi.com/api/sets/{}/"
# Bandai's own product shots, where a set's product page has them
OFFICIAL_URL = "https://en.onepiece-cardgame.com/products/boosters/{}/images/others/{}.webp"
# The official rule manual has flat scans of the card backs
RULES_PDF = "https://en.onepiece-cardgame.com/pdf/rule_manual.pdf"
# TCGplayer product photos: sealed packs/boxes and DON!! cards (ids in app/sets.json)
TCGPLAYER_IMG = "https://tcgplayer-cdn.tcgplayer.com/product/{}_in_1000x1000.jpg"
UA = {"User-Agent": "Mozilla/5.0 (optcg-pack-widget/1.0)"}

HERE = os.path.dirname(os.path.realpath(__file__))
with open(os.path.join(HERE, "app", "sets.json")) as f:
    SETS = json.load(f)
ROOT = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "optcg")
ASSETS = os.path.join(ROOT, "assets")


def tier_of(card):
    """Map a card to the pull tier used by the pack generator (None = not in boosters).

    Variant naming changed over the years: "(Parallel)" / "(Alternate Art)",
    "(SP)" / "(Wanted Poster)" / "(SPR)", premium-booster foil treatments, ...
    """
    name, rarity = card["card_name"], card["rarity"]
    tags = set(re.findall(r"\(([^)]*)\)", name))
    leader = card.get("card_type") == "Leader"
    if "Dash Pack" in tags:
        return None
    if "Box Topper" in tags:
        return "TOPPER"
    if "Pandaman Art" in tags:
        return "PANDA"
    if "Gold-Stamped Signature" in tags:
        return "SIGNED"
    if "SP" in tags and tags & {"Gold", "Silver"}:
        return "SP_GOLD"
    if any("Super" in t and "Alternate Art" in t for t in tags):
        return "SUPER_L" if leader else "SUPER"
    if "Manga" in tags:
        return "MANGA"
    if tags & {"SP", "Wanted Poster", "SPR"}:
        return "SP"
    if rarity == "TR" or "TR" in tags:
        return "TR"
    if tags & {"Jolly Roger Foil", "Pirate Foil"}:
        return "FOIL"
    if "Textured Foil" in tags:
        return "TEX"
    if tags & {"Alternate Art", "Parallel", "Full Art"}:
        if rarity == "SEC":
            return "SEC_AA"
        return "L_AA" if leader else "AA"
    if rarity == "PR":
        return "R"   # promo reprints in the premium boosters
    return rarity


def fetch(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
        return r.read()


def magick(*args):
    subprocess.run(["magick", *args], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def image_size(path):
    out = subprocess.run(["magick", "identify", "-format", "%w %h", path],
                         check=True, capture_output=True, text=True).stdout
    return tuple(int(v) for v in out.split())


def mean_brightness(path):
    out = subprocess.run(["magick", path, "-format", "%[fx:mean]", "info:"],
                         check=True, capture_output=True, text=True).stdout
    return float(out)


def download(card, cache):
    # variants can share a card id, so name files after the (unique) URL
    dest = os.path.join(cache, os.path.basename(card["url"]))
    if not os.path.exists(dest) or os.path.getsize(dest) == 0:
        data = fetch(card["url"])
        with open(dest + ".part", "wb") as f:
            f.write(data)
        os.replace(dest + ".part", dest)
    card["image"] = dest
    del card["url"]
    return card


def fetch_product_images(set_id, info, cache):
    """Sealed pack and box photos -> <set>/pack.png, <set>/box.png"""
    for name, official, tcg in (("pack", "product_pack", info["pack"]), ("box", "product_booster", info["box"])):
        dest = os.path.join(cache, name + ".png")
        if os.path.exists(dest):
            continue
        try:
            if "official" in info:
                data, studio = fetch(OFFICIAL_URL.format(info["official"], official)), True
            else:
                data, studio = fetch(TCGPLAYER_IMG.format(tcg)), False
        except Exception as e:
            print(f"no {name} image for {set_id} ({e}); using the drawn one")
            continue
        raw = os.path.join(cache, name + ".src")
        with open(raw, "wb") as f:
            f.write(data)
        if not shutil.which("magick"):
            os.replace(raw, dest)   # Qt sniffs the format; untrimmed is fine
        elif studio:
            magick(raw, "-trim", "+repage", dest)
        else:
            # product photo on white: flood the background away from the corners
            magick(raw, "-bordercolor", "white", "-border", "1", "-fuzz", "6%", "-fill", "none",
                   "-floodfill", "+0+0", "white", "-shave", "1x1", "-trim", "+repage", dest)
        if os.path.exists(raw):
            os.remove(raw)
        print(name, "image ->", dest)


def fetch_don_cards(set_id, info, cache):
    """DON!! scans for the set, trimmed to the card and sized like the others."""
    cards = []

    def one(item):
        n, (product, name, tier) = item
        dest = os.path.join(cache, f"don_{product}.png")
        if not os.path.exists(dest):
            raw = dest + ".jpg"
            try:
                with open(raw, "wb") as f:
                    f.write(fetch(TCGPLAYER_IMG.format(product)))
            except Exception as e:
                print(f"couldn't download {name} ({e})")
                return None
            if shutil.which("magick"):
                # product photos have a light margin around the card
                magick(raw, "-fuzz", "12%", "-trim", "+repage", "-resize", "600x838!", dest)
                os.remove(raw)
            else:
                os.replace(raw, dest)
        return {"id": f"{set_id.replace('-', '')}-DON-{n}", "name": name, "rarity": "DON",
                "tier": tier, "color": "", "type": "DON!!", "image": dest}

    with ThreadPoolExecutor(max_workers=8) as pool:
        cards = [c for c in pool.map(one, enumerate(info.get("dons", []), 1)) if c]
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


def fetch_set(set_id):
    if set_id not in SETS:
        sys.exit(f"unknown set {set_id}; known: {', '.join(SETS)}")
    info = SETS[set_id]
    cache = os.path.join(ROOT, set_id)
    os.makedirs(cache, exist_ok=True)
    fetch_product_images(set_id, info, cache)
    fetch_card_backs()
    out_path = os.path.join(cache, "cards.json")
    try:
        raw = json.loads(fetch(API.format(set_id)))
    except Exception as e:
        if not os.path.exists(out_path):
            raise
        # API down: keep the cached card list, just refresh the DON!! cards
        print(f"optcgapi unreachable ({e}); reusing cached card list")
        with open(out_path) as f:
            out = json.load(f)
        out["cards"] = [c for c in out["cards"] if c["type"] != "DON!!"] + fetch_don_cards(set_id, info, cache)
        with open(out_path, "w") as f:
            json.dump(out, f, indent=1)
        print("done")
        return

    cards, seen = [], set()
    for c in raw:
        cid = c["card_image_id"]
        key = (cid, c["card_name"])
        tier = tier_of(c)
        if key in seen or not c.get("card_image") or tier is None:
            continue
        seen.add(key)
        cards.append({
            "id": cid,
            "name": c["card_name"],
            "rarity": c["rarity"],
            "tier": tier,
            "color": c.get("card_color") or "",
            "type": c.get("card_type") or "",
            "url": c["card_image"],
        })

    print(f"{set_id}: {len(cards)} cards, downloading images to {cache}", flush=True)
    with ThreadPoolExecutor(max_workers=8) as pool:
        done = []
        for card in pool.map(lambda c: download(c, cache), cards):
            done.append(card)
            if len(done) % 10 == 0 or len(done) == len(cards):
                print(f"{len(done)} / {len(cards)} card images", flush=True)
        cards = done
    print("DON!! cards...", flush=True)
    cards += fetch_don_cards(set_id, info, cache)

    out = {"set": set_id, "set_name": info["name"], "cards": cards}
    with open(out_path, "w") as f:
        json.dump(out, f, indent=1)
    print("done")


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else "OP-17"
    if arg == "list":
        for set_id, info in SETS.items():
            have = os.path.exists(os.path.join(ROOT, set_id, "cards.json"))
            print(f"{set_id:10} {'downloaded' if have else '-':11} {info['name']}")
    elif arg == "previews":
        for set_id, info in SETS.items():
            cache = os.path.join(ROOT, set_id)
            os.makedirs(cache, exist_ok=True)
            fetch_product_images(set_id, info, cache)
    elif arg == "all":
        for set_id in SETS:
            fetch_set(set_id)
    else:
        fetch_set(arg)


if __name__ == "__main__":
    main()
