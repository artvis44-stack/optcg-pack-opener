#!/usr/bin/env python3
"""Synthesizes the pack opener's sound effects into app/sounds/*.wav.

Everything is made from oscillators and noise here (no samples, nothing to
license), so tweak a recipe and run it again: python3 tools/make_sounds.py
"""

import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "app", "sounds")
rnd = random.Random(7)   # the same sounds every run


def silence(seconds):
    return [0.0] * int(seconds * RATE)


def mix(base, layer, at=0.0, gain=1.0):
    start = int(at * RATE)
    if len(base) < start + len(layer):
        base.extend([0.0] * (start + len(layer) - len(base)))
    for i, v in enumerate(layer):
        base[start + i] += v * gain
    return base


def env(n, attack, decay_rate, i):
    """quick attack, exponential decay"""
    t = i / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    return a * math.exp(-decay_rate * t)


def tone(freq, seconds, decay=4.0, attack=0.005, harmonics=(1.0,), vibrato=0.0, glide_to=None):
    n = int(seconds * RATE)
    out, phase = [], 0.0
    for i in range(n):
        f = freq if glide_to is None else freq * (glide_to / freq) ** (i / n)
        if vibrato:
            f *= 1 + vibrato * math.sin(2 * math.pi * 5.5 * i / RATE)
        phase += 2 * math.pi * f / RATE
        s = sum(h * math.sin((k + 1) * phase) for k, h in enumerate(harmonics))
        out.append(s * env(n, attack, decay, i))
    return out


def bell(freq, seconds, decay=3.0):
    # inharmonic partials: bright and glassy
    out = silence(seconds)
    for ratio, amp, d in ((1.0, 1.0, 1.0), (2.76, 0.45, 1.6), (5.4, 0.25, 2.4), (8.93, 0.12, 3.5)):
        mix(out, tone(freq * ratio, seconds, decay * d, 0.002), 0, amp)
    return out


def brass(freq, seconds, attack=0.04, decay=1.2):
    # sawtooth-ish, its brightness swelling in with the attack
    harm = [1 / k for k in range(1, 9)]
    return tone(freq, seconds, decay, attack, harm, vibrato=0.004)


def noise(seconds, decay=8.0, attack=0.002, cutoff_from=8000, cutoff_to=None, crackle=0.0):
    n = int(seconds * RATE)
    out, lp, hp_prev, hp = [], 0.0, 0.0, 0.0
    for i in range(n):
        c = cutoff_from if cutoff_to is None else cutoff_from * (cutoff_to / cutoff_from) ** (i / n)
        a = 1 - math.exp(-2 * math.pi * c / RATE)
        x = rnd.uniform(-1, 1)
        if crackle and rnd.random() < crackle:
            x *= 4
        lp += a * (x - lp)
        hp = 0.97 * (hp + lp - hp_prev)   # take the rumble out
        hp_prev = lp
        out.append(hp * env(n, attack, decay, i))
    return out


def thump(freq=70, seconds=0.5, decay=9.0):
    return tone(freq * 2, seconds, decay, 0.001, (1.0, 0.3), glide_to=freq)


def finish(samples, peak=0.85):
    m = max(1e-9, max(abs(s) for s in samples))
    fade = int(0.01 * RATE)
    out = [s / m * peak for s in samples]
    for i in range(min(fade, len(out))):
        out[-1 - i] *= i / fade
    return out


def save(name, samples):
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in finish(samples)))


NOTE = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}


def hz(name):
    """'E5', 'F#4', 'Bb3' -> Hz"""
    letter, rest = name[0], name[1:]
    shift = 0
    if rest.startswith("#"):
        shift, rest = 1, rest[1:]
    elif rest.startswith("b"):
        shift, rest = -1, rest[1:]
    return 440 * 2 ** ((NOTE[letter] + shift + 12 * (int(rest) - 4)) / 12)


# ---- the sounds ----------------------------------------------------------------------

def tear():   # foil ripping open: a soft, papery rip, not a hiss
    s = noise(0.5, decay=6, attack=0.01, cutoff_from=2500, cutoff_to=900, crackle=0.01)
    mix(s, noise(0.3, decay=10, cutoff_from=1600, crackle=0.02), 0.06, 0.5)
    mix(s, thump(110, 0.2, 18), 0, 0.35)
    return s


def flip():   # a card sliding off the stack: short, low and quiet (it plays on every card)
    s = noise(0.12, decay=30, attack=0.008, cutoff_from=1800, cutoff_to=700)
    mix(s, tone(220, 0.08, 45, 0.002, (1.0, 0.25), glide_to=150), 0, 0.6)
    return s


def charge():   # suspense before a big card (as long as the charge, 1.1 s)
    n = int(1.1 * RATE)
    out, phase = [], 0.0
    for i in range(n):
        t = i / n
        f = 180 * 4 ** t
        phase += 2 * math.pi * f / RATE
        trem = 0.6 + 0.4 * math.sin(2 * math.pi * (6 + 22 * t) * i / RATE)
        s = math.sin(phase) + 0.35 * math.sin(2 * phase) + 0.2 * math.sin(3 * phase)
        out.append(s * trem * (0.15 + 0.85 * t ** 1.5))
    mix(out, noise(1.1, decay=0.2, attack=0.9, cutoff_from=800, cutoff_to=7000), 0, 0.35)
    return out


def rare():   # Super Rare and up: a two-note chime
    s = bell(hz("E6"), 0.9, 4)
    mix(s, bell(hz("B6"), 0.8, 4), 0.09, 0.8)
    return s


def epic():   # alt arts, SECs, SPs: a rising arpeggio with shimmer
    s = silence(1.6)
    for k, n in enumerate(("C5", "E5", "G5", "C6", "E6")):
        mix(s, bell(hz(n), 1.4 - k * 0.1, 2.5), k * 0.07, 0.8)
    mix(s, noise(1.2, decay=3, attack=0.2, cutoff_from=9000), 0.15, 0.12)
    mix(s, thump(90, 0.4), 0, 0.5)
    return s


def legendary():   # TR, Manga, Super Alt Art...: a fanfare
    s = silence(2.8)
    mix(s, thump(55, 0.9, 5), 0, 0.9)
    for n in ("G3", "D4", "G4"):
        mix(s, brass(hz(n), 0.35, 0.02, 6), 0.0, 0.35)
    for n in ("C4", "E4", "G4", "C5"):
        mix(s, brass(hz(n), 2.3, 0.05, 1.3), 0.3, 0.3)
    for k, n in enumerate(("C6", "E6", "G6", "C7")):
        mix(s, bell(hz(n), 1.6, 2), 0.3 + k * 0.08, 0.35)
    mix(s, noise(2.2, decay=1.5, attack=0.3, cutoff_from=10000), 0.3, 0.1)
    return s


def god():   # a god pack: boom, a choir-like swell, sparkles
    s = silence(4.2)
    mix(s, thump(45, 1.4, 3), 0, 1.0)
    mix(s, noise(0.8, decay=4, cutoff_from=3000, cutoff_to=300), 0, 0.5)
    for n in ("C3", "G3", "C4", "E4", "G4", "C5"):
        for detune in (0.997, 1.0, 1.003):   # several voices, slightly apart
            mix(s, tone(hz(n) * detune, 3.8, 0.5, 0.6, (1.0, 0.5, 0.33, 0.25, 0.2), vibrato=0.003), 0.2, 0.12)
    for k in range(14):
        n = rnd.choice(("C7", "E7", "G7", "C8", "E6", "G6"))
        mix(s, bell(hz(n), 0.7, 5), 0.5 + k * 0.17 + rnd.uniform(0, 0.08), 0.18)
    return s


def coin():   # berries changing hands
    s = tone(hz("B5"), 0.09, 25, 0.001, (1.0, 0.0, 0.3))
    mix(s, tone(hz("E6"), 0.35, 9, 0.001, (1.0, 0.0, 0.3)), 0.07)
    return s


def poster():   # a wanted poster: drum hit, then a brass stinger
    s = silence(1.8)
    mix(s, thump(60, 0.6, 7), 0, 1.0)
    mix(s, noise(0.3, decay=14, cutoff_from=4000), 0, 0.4)
    for n in ("A3", "C4", "E4"):
        mix(s, brass(hz(n), 0.3, 0.015, 8), 0.05, 0.3)
    for n in ("D4", "F#4", "A4", "D5"):
        mix(s, brass(hz(n), 1.4, 0.03, 1.8), 0.32, 0.28)
    return s


def chime():   # bounty done, streak, free pack
    s = bell(hz("G5"), 0.8, 4)
    mix(s, bell(hz("D6"), 0.8, 4), 0.08, 0.7)
    mix(s, bell(hz("G6"), 0.8, 4), 0.16, 0.5)
    return s


def box():   # opening a booster box: cardboard and a thud
    s = thump(80, 0.4, 10)
    mix(s, noise(0.45, decay=7, cutoff_from=1200, cutoff_to=600, crackle=0.02), 0.02, 0.8)
    return s


if __name__ == "__main__":
    for fn in (tear, flip, charge, rare, epic, legendary, god, coin, poster, chime, box):
        rnd.seed(fn.__name__)   # each sound its own noise, so changing one leaves the others alone
        save(fn.__name__, fn())
        print("app/sounds/" + fn.__name__ + ".wav")
