"""Writes the default sounds of Raintile (@Resources/Sounds/*.wav).

They are synthesised here (sine tones, a little filtered noise), so they are
Raintile's own: no samples of anyone else. Short, all at the same level: Rainmeter's
own volume (the Windows mixer) sets how loud. Run again after changing them:

    python tools/make_sounds.py
"""
import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '@Resources', 'Sounds')


def env(i, n, attack=0.004, release=None):
    """Quick attack, exponential decay to silence at the end."""
    t = i / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    rest = 1.0 - i / n
    return a * (rest ** (release or 2.0))


def tone(dur, f0, f1=None, amp=0.3, harm=(1.0,), release=2.0, attack=0.004):
    n = int(dur * RATE)
    f1 = f0 if f1 is None else f1
    out, phase = [], 0.0
    for i in range(n):
        f = f0 + (f1 - f0) * (i / n)
        phase += 2 * math.pi * f / RATE
        s = sum(h * math.sin(phase * (k + 1)) for k, h in enumerate(harm)) / sum(harm)
        out.append(amp * env(i, n, attack, release) * s)
    return out


def swoosh(dur, lo, hi, amp=0.2, seed=1):
    """Noise through a one-pole low-pass whose cut-off sweeps lo -> hi."""
    rnd = random.Random(seed)
    n = int(dur * RATE)
    out, y = [], 0.0
    for i in range(n):
        x = i / n
        fc = lo + (hi - lo) * x
        k = 1 - math.exp(-2 * math.pi * fc / RATE)
        y += k * (rnd.uniform(-1, 1) - y)
        bell = math.sin(math.pi * x)  # in and out
        out.append(amp * 3 * y * bell)
    return out


def mix(*parts):
    n = max(len(p) for p in parts)
    return [sum(p[i] for p in parts if i < len(p)) for i in range(n)]


def after(gap, part):
    return [0.0] * int(gap * RATE) + part


def write(name, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = 0.4 / peak  # every sound as loud, well below full scale
    data = b''.join(struct.pack('<h', int(max(-1, min(1, s * scale)) * 32767)) for s in samples)
    path = os.path.join(OUT, name + '.wav')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    print('%s: %d ms' % (path, len(samples) * 1000 // RATE))


def main():
    os.makedirs(OUT, exist_ok=True)
    # the launcher (or the Rainside) coming in / going away
    write('open', mix(swoosh(0.34, 250, 5000, 0.5, 1), tone(0.34, 392, 784, 0.45, (1, 0.35, 0.1), 1.4, 0.04)))
    write('close', mix(swoosh(0.30, 5000, 250, 0.45, 2), tone(0.30, 784, 392, 0.4, (1, 0.35, 0.1), 1.4, 0.03)))
    # the highlight to another tile, part or entry: a soft wooden tick
    write('move', tone(0.07, 1320, 1180, 0.8, (1, 0.5, 0.2), 1.8, 0.002))
    # a tile started: two notes up
    write('launch', mix(tone(0.45, 659.3, None, 0.6, (1, 0.4, 0.15), 1.6), after(0.09, tone(0.55, 987.8, None, 0.6, (1, 0.4, 0.15), 1.6))))
    # another category: a short swoosh with a note
    write('category', mix(swoosh(0.22, 600, 6000, 0.45, 3), tone(0.2, 880, 1175, 0.35, (1, 0.3), 1.5, 0.01)))
    # a menu opened: a pop
    write('menu', tone(0.13, 1046.5, 700, 0.8, (1, 0.35, 0.1), 1.8, 0.002))
    # a key of the on-screen keyboard: a click
    write('key', tone(0.06, 1568, 1300, 0.8, (1, 0.4), 2.0, 0.001))
    # back: something closed, lower
    write('back', tone(0.14, 587, 330, 0.8, (1, 0.35, 0.1), 1.8, 0.002))


if __name__ == '__main__':
    main()
