#!/usr/bin/env python3
"""Download OPTCG set data + card images into the local cache.

Usage: fetch_cards.py [SET_ID]   one set (default OP-17), e.g. OP-05, EB-01, PRB-02
       fetch_cards.py all        every set in app/sets.json (~40 MB each)
       fetch_cards.py list       the known sets and whether they're downloaded
       fetch_cards.py previews   just the pack/box photos of every set (for the set picker)
       fetch_cards.py background [PLAYMATS_JSON]
                                 everything still missing, quietly: card backs, pack photos,
                                 the playmats ([[id, tcgplayer id, page], ...]), then every
                                 set newest first (English, then Japanese). The desktop
                                 companion runs this, so picking a set is instant.

Writes $XDG_CACHE_HOME/optcg/<SET_ID>/cards.json, one image per card, and the
set's pack/box photos; the card backs (shared by all sets) go in assets/.
Card data comes from the community API at optcgapi.com, product and DON!!
photos from Bandai / TCGplayer. Japanese sets (sets.json "lang": "jp") come
from Bandai's Japanese card list, through the punk-records scrape of it or,
failing that, the official page itself; English names and rarities come from
the matching English set where it has the card. Card art belongs to Bandai / Eiichiro Oda --
this is a personal cache, don't redistribute it.
"""
import fcntl
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

API = "https://optcgapi.com/api/sets/{}/"
# Bandai's own product shots, where a set's product page has them
OFFICIAL_URL = "https://en.onepiece-cardgame.com/products/boosters/{}/images/others/{}.webp"
# The official rule manual has flat scans of the card backs
RULES_PDF = "https://en.onepiece-cardgame.com/pdf/rule_manual.pdf"
# TCGplayer product photos: sealed packs/boxes and DON!! cards (ids in app/sets.json)
TCGPLAYER_IMG = "https://tcgplayer-cdn.tcgplayer.com/product/{}_in_1000x1000.jpg"
# Japanese card lists: the punk-records scrape (JSON), else Bandai's own page;
# a set's "series" id in sets.json picks it (550101 = OP-01)
JP_DATA = "https://raw.githubusercontent.com/buhbbl/punk-records/HEAD/japanese/data/{}.json"
JP_CARDLIST = "https://www.onepiece-cardgame.com/cardlist/?series={}"
JP_SITE = "https://www.onepiece-cardgame.com/cardlist/"
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


# punk-records rarity names, and the official list's short ones
JP_RARITY = {"Leader": "L", "Common": "C", "Uncommon": "UC", "Rare": "R", "SuperRare": "SR",
             "SecretRare": "SEC", "TreasureRare": "TR", "Special": "SP", "Promo": "R",
             "L": "L", "C": "C", "UC": "UC", "R": "R", "SR": "SR", "SEC": "SEC", "TR": "TR",
             "SPカード": "SP", "SP": "SP", "P": "R"}
JP_COLOR = {"赤": "Red", "緑": "Green", "青": "Blue", "紫": "Purple", "黒": "Black", "黄": "Yellow"}
# the tag an English name gets for a tier (Tiers.displayName strips it again)
TIER_TAG = {"AA": "Parallel", "L_AA": "Parallel", "SEC_AA": "Parallel", "MANGA": "Manga",
            "SUPER": "Super Alternate Art", "SUPER_L": "Super Alternate Art", "SP": "SP", "TR": "TR"}


def jp_tier(card_id, rarity, premium=False):
    """Pull tier of a Japanese printing from its rarity and its parallel number
    (OP01-120_p2): the first parallel is the alternate art, later ones of an
    SR / SEC the rarer treatments (manga, super parallel). Premium boosters
    are reprints that are nearly all parallels, so there an SR's is just one."""
    m = re.search(r"_p(\d+)$", card_id)
    if rarity in ("SP", "TR") or not m:
        return rarity
    if rarity == "L":
        return "L_AA"
    if rarity == "SEC":
        return "SEC_AA" if m.group(1) == "1" else "MANGA"
    if rarity == "SR" and m.group(1) != "1" and not premium:
        return "SUPER"
    return "AA"


def jp_card_list(series):
    """[{id, rarity, type, color, name, url}] of a Japanese set, from the
    punk-records JSON, else parsed off Bandai's card list page."""
    try:
        raw = json.loads(fetch(JP_DATA.format(series)))
        out = [{"id": c["id"], "rarity": JP_RARITY.get(c.get("rarity"), "C"),
                "type": c.get("category") or "", "color": " ".join(c.get("colors") or []),
                "name": c.get("name") or c["id"],
                "url": (c.get("img_full_url") or "").split("?")[0]} for c in raw]
        if out:
            return out
    except Exception as e:
        print(f"punk-records has no {series} ({e}); reading Bandai's card list", flush=True)
    return parse_jp_cardlist(fetch(JP_CARDLIST.format(series)).decode("utf-8", "replace"))


def parse_jp_cardlist(html):
    out = []
    for block in re.findall(r'<dl class="modalCol" id="([^"]+)">(.*?)</dl>', html, re.S):
        card_id, body = block
        info = re.search(r'<div class="infoCol">\s*<span>([^<]*)</span>\s*\|\s*<span>([^<]*)</span>\s*\|\s*<span>([^<]*)</span>', body)
        img = re.search(r'data-src="([^"]+)"', body)
        name = re.search(r'<div class="cardName">([^<]*)</div>', body)
        color = re.search(r'<div class="color"><h3>[^<]*</h3>([^<]*)</div>', body)
        if not (info and img):
            continue
        out.append({"id": card_id, "rarity": JP_RARITY.get(info.group(2).strip(), "C"),
                    "type": info.group(3).strip().title(),
                    "color": " ".join(JP_COLOR.get(c, c) for c in (color.group(1) if color else "").strip().split("/") if c),
                    "name": name.group(1).strip() if name else card_id,
                    "url": urllib.parse.urljoin(JP_SITE, img.group(1)).split("?")[0]})
    return out


def english_cards(en_sets):
    """The English printings, for names and tiers: {image id: card}. The
    set's English counterparts (sets.json "en") come from the local download
    if there is one, else optcgapi; any other English set you've downloaded
    helps too (the SPs reprint older sets' cards)."""
    out = {}
    local = [s for s, i in SETS.items() if i.get("lang") != "jp" and s not in en_sets
             and os.path.exists(os.path.join(ROOT, s, "cards.json"))]
    for en in list(en_sets) + local:
        try:
            with open(os.path.join(ROOT, en, "cards.json")) as f:
                cards = json.load(f)["cards"]
        except Exception:
            if en in local:
                continue
            try:
                cards = [{"id": c["card_image_id"], "name": c["card_name"], "tier": tier_of(c)}
                         for c in json.loads(fetch(API.format(en)))]
            except Exception as e:
                print(f"no English names from {en} ({e})", flush=True)
                continue
        for c in cards:
            if c.get("tier") and c.get("type") != "DON!!":
                out.setdefault(c["id"], c)
    return out


def jp_cards(set_id, info):
    """A Japanese set's cards (still to download) in the cards.json format."""
    en = english_cards(info.get("en", []))
    base_names = {}
    for cid, c in en.items():
        if "_p" not in cid:
            base_names.setdefault(cid, re.sub(r"\s*\([^)]*\)", "", c["name"]).strip())
    cards, seen = [], set()
    for c in jp_card_list(info["series"]):
        if c["id"] in seen or not c["url"]:
            continue
        seen.add(c["id"])
        match = en.get(c["id"])
        tier = match["tier"] if match else jp_tier(c["id"], c["rarity"], info.get("family") == "premium")
        base = base_names.get(c["id"].split("_")[0])
        name = match["name"] if match else \
            (base + (f" ({TIER_TAG[tier]})" if tier in TIER_TAG and "_p" in c["id"] else "")) if base else c["name"]
        cards.append({"id": c["id"], "name": name, "nameJp": c["name"], "rarity": c["rarity"], "tier": tier,
                      "color": c["color"], "type": c["type"],
                      "url": c["url"]})
    return cards


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


# bump when cut_out changes: product photos cut out by an older one are redone
CUT_OUT = "cut2"


def cut_out(src, out):
    """A product photo on white -> the product alone: flood the background away from the
    corners, twice. A loose flood clears the JPEG noise around the product but runs into
    a white product (OP-05's pack and box) and eats holes in it; a tight one (pure white
    only) keeps those but leaves a speckled fringe. Keep what either keeps, the tight
    one opened first so its thin fringe goes and only solid product is left."""
    with tempfile.TemporaryDirectory() as tmp:
        loose, tight, keep = (os.path.join(tmp, n + ".png") for n in ("loose", "tight", "keep"))
        for fuzz, mask in (("6%", loose), ("1%", tight)):
            magick(src, "-bordercolor", "white", "-border", "1", "-fuzz", fuzz, "-fill", "none",
                   "-floodfill", "+0+0", "white", "-shave", "1x1", "-alpha", "extract", mask)
        magick(tight, "-morphology", "Open", "Disk:6", loose, "-compose", "lighten", "-composite", keep)
        magick(src, keep, "-alpha", "off", "-compose", "CopyOpacity", "-composite", "-trim", "+repage", out)


def fetch_product_images(set_id, info, cache):
    """Sealed pack and box photos -> <set>/pack.png, <set>/box.png. A photo URL in sets.json
    (packPhoto / boxPhoto: the Japanese products) beats Bandai's English shots, which beat
    TCGplayer's; <name>.src remembers which one is on disk, so a new one replaces it."""
    for name, official, tcg in (("pack", "product_pack", info.get("pack")), ("box", "product_booster", info.get("box"))):
        dest = os.path.join(cache, name + ".png")
        photo = info.get(name + "Photo")
        if photo:
            url = photo
        elif "official" in info:
            url = OFFICIAL_URL.format(info["official"], official)
        elif tcg:
            url = TCGPLAYER_IMG.format(tcg)
        else:
            continue
        # Bandai's own shots are cut out already; the rest are photos on white
        studio = url.startswith(("https://en.onepiece-cardgame.com/", "https://www.onepiece-cardgame.com/"))
        made = url if studio else url + " " + CUT_OUT
        src_file = os.path.join(cache, name + ".src")
        had = open(src_file).read().strip() if os.path.exists(src_file) else None
        if os.path.exists(dest) and (had == made or (studio and had is None and not photo)):
            continue
        try:
            data = fetch(url)
        except Exception as e:
            print(f"no {name} image for {set_id} ({e}); using the drawn one")
            continue
        # this process's own temp files (the set picker and the background download
        # can both be at it), swapped in whole
        raw = os.path.join(cache, f"{name}.{os.getpid()}.src")
        out = os.path.join(cache, f"{name}.{os.getpid()}.png")
        with open(raw, "wb") as f:
            f.write(data)
        if not shutil.which("magick"):
            os.replace(raw, out)   # Qt sniffs the format; untrimmed is fine
        elif studio:
            magick(raw, "-trim", "+repage", out)
        else:
            cut_out(raw, out)
        if os.path.exists(raw):
            os.remove(raw)
        os.replace(out, dest)
        with open(src_file, "w") as f:
            f.write(made + "\n")
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


def lock(path, wait_message=None):
    """An exclusive lock on path (held until the process exits or the file is
    closed); waits for whoever holds it, saying so. None if wait_message is
    None and it's taken."""
    f = open(path, "w")
    try:
        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        if wait_message is None:
            f.close()
            return None
        print(wait_message, flush=True)
        fcntl.flock(f, fcntl.LOCK_EX)
    return f


def fetch_set(set_id):
    if set_id not in SETS:
        sys.exit(f"unknown set {set_id}; known: {', '.join(SETS)}")
    info = SETS[set_id]
    cache = os.path.join(ROOT, set_id)
    os.makedirs(cache, exist_ok=True)
    # one download of a set at a time: the pack opener's waits for the background one
    held = lock(os.path.join(cache, ".lock"), f"{set_id} is downloading in the background, nearly there...")
    try:
        fetch_set_locked(set_id, info, cache)
    finally:
        held.close()


def fetch_set_locked(set_id, info, cache):
    fetch_product_images(set_id, info, cache)
    fetch_card_backs()
    out_path = os.path.join(cache, "cards.json")
    if info.get("lang") == "jp":
        cards = jp_cards(set_id, info)
        if not cards:
            sys.exit(f"no cards found for {set_id}")
        return save_set(set_id, info, cache, cards)
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
    save_set(set_id, info, cache, cards)


def save_set(set_id, info, cache, cards):
    """Download the cards' images and write <set>/cards.json."""
    out_path = os.path.join(cache, "cards.json")
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


def official_image(page):
    """The product picture on an official product page: an <img> or og:image
    whose name mentions the page's product (e.g. playmat005), else og:image."""
    html = fetch(page).decode("utf-8", "replace")
    product = os.path.splitext(os.path.basename(page))[0]
    urls = re.findall(r'<img[^>]+src="([^"]+)"', html) + \
        re.findall(r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"', html)
    urls = [urllib.parse.urljoin(page, u) for u in urls]
    named = [u for u in urls if product in u and re.search(r"\.(jpe?g|png|webp)(\?|$)", u)]
    og = re.findall(r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"', html)
    if named:
        return named[0]
    if og:
        return urllib.parse.urljoin(page, og[0])
    raise ValueError("no product image on " + page)


def fetch_playmat(mat_id, tcg, page):
    """A playmat's picture (a cosmetic backdrop) -> playmats/<id>.img; tcg: TCGplayer
    product id ("" if none), page: official product page ("" if none)"""
    if not re.fullmatch(r"[a-z0-9-]{1,40}", mat_id):
        sys.exit("bad playmat id")
    folder = os.path.join(ROOT, "playmats")
    os.makedirs(folder, exist_ok=True)
    dest = os.path.join(folder, mat_id + ".img")   # jpg or webp: Qt tells by the content
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        print("have", dest)
        return
    sources = []
    if tcg:
        sources.append(TCGPLAYER_IMG.format(int(tcg)))
    if page.startswith("https://en.onepiece-cardgame.com/"):
        sources.append(page)
    for src in sources:
        try:
            data = fetch(official_image(src) if src == page else src)
        except Exception as e:
            print(f"{mat_id}: {src} failed ({e})", flush=True)
            continue
        part = f"{dest}.{os.getpid()}.part"   # the pack opener may be fetching it too
        with open(part, "wb") as f:
            f.write(data)
        os.replace(part, dest)
        print("playmat ->", dest)
        return
    print(f"{mat_id}: no picture found")


def background(playmats):
    """Download whatever's missing, gently, newest sets first; skips (exits)
    if another background run is going."""
    os.makedirs(ROOT, exist_ok=True)
    held = lock(os.path.join(ROOT, ".background.lock"))
    if not held:
        print("another background download is running")
        return
    try:
        os.nice(10)
    except OSError:
        pass
    try:
        fetch_card_backs()
    except Exception as e:
        print(f"card backs: {e}", flush=True)
    for set_id, info in SETS.items():
        cache = os.path.join(ROOT, set_id)
        os.makedirs(cache, exist_ok=True)
        try:
            fetch_product_images(set_id, info, cache)
        except Exception as e:
            print(f"{set_id} photos: {e}", flush=True)
    for mat in playmats:
        try:
            fetch_playmat(*[str(x or "") for x in mat[:3]])
        except (Exception, SystemExit) as e:
            print(f"playmat {mat}: {e}", flush=True)
    en = [s for s, i in SETS.items() if i.get("lang") != "jp"]
    jp = [s for s, i in SETS.items() if i.get("lang") == "jp"]
    for set_id in en[::-1] + jp[::-1]:
        if os.path.exists(os.path.join(ROOT, set_id, "cards.json")):
            continue
        try:
            fetch_set(set_id)
        except (Exception, SystemExit) as e:   # one set failing shouldn't stop the rest
            print(f"{set_id}: {e}", flush=True)
    print("background downloads done", flush=True)


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else "OP-17"
    if arg == "background":
        background(json.loads(sys.argv[2]) if len(sys.argv) > 2 else [])
        return
    if arg == "--playmat":   # --playmat <id> <tcgplayer id or ""> <official page or "">
        fetch_playmat(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "", sys.argv[4] if len(sys.argv) > 4 else "")
        return
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
