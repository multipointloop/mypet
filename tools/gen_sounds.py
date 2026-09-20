"""MyPet asset pipeline - step 3: synthesise placeholder sound effects.

Pure stdlib (wave + math + random) so it runs even before pip deps land.
Every file is 16-bit mono 44.1kHz WAV written to mypet/assets/sounds/.
Replace any file with a real mp3/wav of the same name later - the app
skips missing/broken audio files silently.
"""
from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "mypet" / "assets" / "sounds"


def env(i: int, n: int, attack: float = 0.01, release: float = 0.6) -> float:
    """Attack/release envelope, attack+release are fractions of length."""
    t = i / n
    if t < attack:
        return t / attack
    if t > 1 - release:
        return max(0.0, (1 - t) / release)
    return 1.0


def render(name: str, samples: list[float]) -> None:
    peak = max(1e-6, max(abs(s) for s in samples))
    norm = 0.5 / peak  # -6 dBFS
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{name}.wav"
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s * norm)) * 32767))
            for s in samples
        ))
    print(f"[sounds] {path.name:<18} {len(samples)/SR*1000:5.0f} ms")


def sine_sweep(dur, f0, f1, curve=1.0, vib_hz=0.0, vib_amt=0.0):
    n = int(SR * dur)
    out, phase = [], 0.0
    for i in range(n):
        t = i / n
        f = f0 + (f1 - f0) * (t ** curve)
        if vib_hz:
            f *= 1 + vib_amt * math.sin(2 * math.pi * vib_hz * i / SR)
        phase += 2 * math.pi * f / SR
        out.append(math.sin(phase))
    return out


def noise(n):
    return [random.uniform(-1, 1) for _ in range(n)]


def main() -> int:
    random.seed(20260913)

    # head pat: bouncy cartoon "bwip"
    body = sine_sweep(0.16, 520, 880, curve=0.6) + sine_sweep(0.10, 880, 520, curve=1.4)
    render("click_head", [s * env(i, len(body), .01, .5) for i, s in enumerate(body)])

    # body pat: soft low pop
    body = sine_sweep(0.14, 300, 170, curve=1.2)
    body = [s + 0.25 * math.sin(2 * math.pi * 2 * i / SR) for i, s in enumerate(body)]
    render("click_body", [s * env(i, len(body), .02, .7) for i, s in enumerate(body)])

    # tail: quick airy swish (noise tinged by a sweeping sine)
    n = int(SR * 0.20)
    hiss = noise(n)
    swish = []
    for i in range(n):
        t = i / n
        f = 900 + 700 * math.sin(2 * math.pi * 3 * t)
        swish.append(0.55 * hiss[i] * math.sin(2 * math.pi * f * i / SR))
    render("click_tail", [s * env(i, n, .05, .55) for i, s in enumerate(swish)])

    # landing thud
    body = sine_sweep(0.22, 110, 55, curve=1.0)
    body = [s + 0.08 * noise(len(body))[i] for i, s in enumerate(body)]
    render("land", [s * env(i, len(body), .005, .8) for i, s in enumerate(body)])

    # surprise: two ascending notes
    n1 = sine_sweep(0.09, 660, 660)
    n2 = sine_sweep(0.14, 990, 990)
    body = n1 + n2
    render("surprise", [s * env(i, len(body), .02, .45) for i, s in enumerate(body)])

    # bongo keyboard tap: tiny percussive tick
    n = int(SR * 0.06)
    tick = [0.8 * math.sin(2 * math.pi * 1100 * i / SR) for i in range(n)]
    atk = noise(int(SR * 0.004))
    for j, s in enumerate(atk):
        tick[j] += 0.7 * s
    render("key", [s * env(i, n, .002, .85) for i, s in enumerate(tick)])

    # mew: pitch-glide with two harmonics and vibrato
    body = sine_sweep(0.34, 780, 420, curve=0.9, vib_hz=11, vib_amt=0.03)
    body = [s + 0.35 * math.sin(2 * math.pi * 2.02 * 700 * i / SR) * (1 - i / len(body))
            for i, s in enumerate(body)]
    render("mew", [s * env(i, len(body), .12, .5) for i, s in enumerate(body)])
    return 0


if __name__ == "__main__":
    main()
