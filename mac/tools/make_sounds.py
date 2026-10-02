#!/usr/bin/env python3
"""Generates Sparrow's own UI sounds (original, synthesized — no third-party audio).
Usage: python3 make_sounds.py <output-folder>"""
import sys, os, wave
import numpy as np

SR = 48000
out = sys.argv[1] if len(sys.argv) > 1 else "."
os.makedirs(out, exist_ok=True)


def env(n, a=0.005, r=0.08):
    t = np.arange(n) / SR
    e = np.minimum(1, t / max(a, 1e-4))
    tail = np.clip((n / SR - t) / max(r, 1e-4), 0, 1)
    return e * tail


def tone(f0, f1, dur, shape="sine", a=0.005, r=None, vib=0.0):
    n = int(SR * dur)
    t = np.arange(n) / SR
    f = np.geomspace(f0, f1, n) if f0 != f1 else np.full(n, f0)
    if vib:
        f = f * (1 + vib * np.sin(2 * np.pi * 28 * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    if shape == "tri":
        w = 2 / np.pi * np.arcsin(np.sin(ph))
    else:
        w = np.sin(ph) + 0.18 * np.sin(2 * ph) + 0.06 * np.sin(3 * ph)
    return w * env(n, a, r if r is not None else dur * 0.7)


def bell(f, dur):
    n = int(SR * dur)
    t = np.arange(n) / SR
    w = sum(amp * np.sin(2 * np.pi * f * k * t) * np.exp(-t * (3 + 2.5 * k))
            for k, amp in [(1, 1), (2.01, 0.45), (3.02, 0.22), (4.2, 0.1)])
    return w * env(n, 0.002, dur * 0.5)


def gap(d):
    return np.zeros(int(SR * d))


def seq(*parts):
    return np.concatenate(parts)


def chirp(f0, f1, d=0.06):  # short bird chirp
    return tone(f0, f1, d, a=0.003, r=d * 0.6, vib=0.01)


def save(name, x):
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.9
    st = np.stack([x, x], axis=1)
    data = (st * 32767).astype("<i2").tobytes()
    with wave.open(os.path.join(out, name + ".wav"), "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data)


S = {
    "chime":    seq(bell(880, 0.5)[: int(SR * 0.18)], bell(1318.5, 0.9)),           # reminder alert
    "greet":    seq(chirp(1800, 2600), gap(0.04), chirp(2000, 3000), gap(0.05), chirp(2400, 1900, 0.09)),
    "finish":   seq(tone(784, 784, 0.08), tone(1046.5, 1046.5, 0.22)),
    "approve":  chirp(1500, 2400, 0.07),
    "approval": seq(tone(660, 660, 0.09), gap(0.03), tone(880, 880, 0.12)),
    "question": tone(700, 1100, 0.18, shape="tri"),
    "error":    seq(tone(392, 370, 0.12, shape="tri"), tone(311, 294, 0.2, shape="tri")),
    "open":     tone(900, 1500, 0.1),
    "close":    tone(1400, 800, 0.1),
    "peek":     chirp(2200, 2800, 0.05),
    "hover":    tone(1800, 1800, 0.025, a=0.002, r=0.02),
    "blip":     tone(1300, 1300, 0.04, a=0.002, r=0.03),
    "tick":     tone(2600, 2600, 0.015, a=0.001, r=0.012),
    "pop":      tone(500, 1400, 0.05, a=0.001),
    "send":     tone(800, 2200, 0.13),
    "attach":   seq(tone(1000, 1000, 0.04), tone(1500, 1500, 0.06)),
    "search":   seq(tone(900, 1200, 0.07), tone(1200, 1600, 0.09)),
    "think":    seq(tone(600, 600, 0.06, shape="tri"), gap(0.05), tone(700, 700, 0.06, shape="tri")),
    "work":     seq(chirp(1600, 1900, 0.04), gap(0.03), chirp(1600, 1900, 0.04)),
    "slap":     tone(300, 160, 0.07, shape="tri", a=0.001),
    "annoyed":  tone(520, 380, 0.25, shape="tri", vib=0.03),
    "dizzy":    tone(900, 500, 0.4, vib=0.08),
    "gulp":     seq(tone(400, 250, 0.07), tone(350, 200, 0.08)),
    "love":     seq(tone(988, 988, 0.1), tone(1318.5, 1318.5, 0.25, vib=0.01)),
    "proud":    seq(tone(659, 659, 0.08), tone(784, 784, 0.08), tone(1046.5, 1046.5, 0.25)),
    "wink":     seq(chirp(2000, 2600, 0.04), gap(0.06), chirp(2600, 2000, 0.06)),
    "yawn":     tone(700, 350, 0.55, shape="tri", vib=0.02),
    "rate":     seq(tone(1046.5, 1046.5, 0.05), tone(1318.5, 1318.5, 0.08)),
    "sleep":    seq(tone(500, 420, 0.35, shape="tri"), gap(0.1), tone(450, 380, 0.4, shape="tri")),
}
for name, x in S.items():
    save(name, x)
print("wrote", len(S), "sounds to", out)
