#!/usr/bin/env python3
"""Download OPTCG set data + card images into the local cache.

Usage: fetch_cards.py [SET_ID]   (default OP-17)

Writes $XDG_CACHE_HOME/optcg/<SET_ID>/cards.json and one image per card.
Data comes from the community API at optcgapi.com. Card art belongs to
Bandai / Eiichiro Oda -- this is a personal cache, don't redistribute it.
"""
import json
import os
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor

API = "https://optcgapi.com/api/sets/{}/"
UA = {"User-Agent": "optcg-pack-widget/1.0"}

SET_ID = sys.argv[1] if len(sys.argv) > 1 else "OP-17"
CACHE = os.path.join(
    os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "optcg", SET_ID
)


def tier_of(card):
    """Map a card to the pull tier used by the pack generator."""
    name, rarity = card["card_name"], card["rarity"]
    if "Pandaman" in name:
        return "PANDA"
    if "(SP)" in name:
        return "SP"
    if "(Manga)" in name:
        return "MANGA"
    if "Super" in name and "Alternate Art" in name:
        return "SUPER"
    if rarity == "TR" or "(TR)" in name:
        return "TR"
    if "(Alternate Art)" in name:
        return "SEC_AA" if rarity == "SEC" else "AA"
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


def main():
    os.makedirs(CACHE, exist_ok=True)
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
