"""Writes Raintile's sounds (@Resources/Sounds/*.wav).

Every sound is made here from nothing: sine and FM tones, a little filtered
noise, envelopes. No recording or sample of anyone else is used, so the
sounds are Raintile's own, under its license. 16-bit mono WAV, 44.1 kHz, all
at the same peak level: Rainmeter's own volume (the Windows mixer) sets how
loud they are. Run again after changing them:

    python tools/make_sounds.py
"""
import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '@Resources', 'Sounds')
PEAK = 0.5


def silence(dur):
    return [0.0] * int(dur * RATE)


def env(i, n, attack, decay):
    """A short attack, then an exponential decay (decay: time constant, s)."""
    t = i / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    tail = min(1.0, (n - i) / (0.004 * RATE))  # never a click at the end
    return a * math.exp(-t / decay) * tail


def bell(dur, freq, amp=1.0, decay=0.25, attack=0.003, ratio=2.0, index=1.2, glide=0.0):
    """FM bell: a carrier modulated at ratio x its pitch, the modulation fading
    faster than the tone (bright start, round end). glide: pitch change, in
    semitones over the sound."""
    n = int(dur * RATE)
    out, pc, pm = [], 0.0, 0.0
    for i in range(n):
        x = i / n
        f = freq * (2 ** (glide * x / 12))
        e = env(i, n, attack, decay)
        pm += 2 * math.pi * f * ratio / RATE
        pc += 2 * math.pi * f / RATE
        mod = index * math.exp(-(i / RATE) / (decay * 0.4)) * math.sin(pm)
        out.append(amp * e * math.sin(pc + mod))
    return out


def noise(dur, lo, hi, amp=1.0, seed=1, shape='bell'):
    """Noise through a two-pole band-pass whose centre sweeps lo -> hi."""
    rnd = random.Random(seed)
    n = int(dur * RATE)
    out, y1, y2 = [], 0.0, 0.0
    for i in range(n):
        x = i / n
        fc = lo * (hi / lo) ** x
        r = 0.97
        c = 2 * r * math.cos(2 * math.pi * fc / RATE)
        y = (1 - r) * rnd.uniform(-1, 1) + c * y1 - r * r * y2
        y2, y1 = y1, y
        if shape == 'bell':
            g = math.sin(math.pi * x)
        else:  # 'hit': quick decay
            g = math.exp(-x * 8)
        out.append(amp * 12 * y * g)
    return out


def mix(*parts):
    n = max(len(p) for p in parts)
    return [sum(p[i] for p in parts if i < len(p)) for i in range(n)]


def at(t, part):
    return silence(t) + part


def write(name, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = PEAK / peak
    data = b''.join(struct.pack('<h', int(max(-1.0, min(1.0, s * scale)) * 32767)) for s in samples)
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    print('%s.wav: %d ms' % (name, len(samples) * 1000 // RATE))


C5, D5, E5, G5, A5, C6, E6 = 523.25, 587.33, 659.26, 783.99, 880.0, 1046.5, 1318.5


def main():
    os.makedirs(OUT, exist_ok=True)
    # opening: an airy rise and three notes up
    write('open', mix(noise(0.32, 400, 5000, 0.35, 1),
                      at(0.02, bell(0.4, C5, 0.5, 0.18)), at(0.09, bell(0.38, E5, 0.5, 0.18)),
                      at(0.16, bell(0.42, G5, 0.55, 0.22))))
    # the Rainside opening: from the side, two notes
    write('open_side', mix(noise(0.24, 600, 4000, 0.3, 2),
                           at(0.03, bell(0.3, E5, 0.5, 0.15)), at(0.1, bell(0.34, A5, 0.55, 0.18))))
    # closing: the opening the other way, softer
    write('close', mix(noise(0.3, 5000, 400, 0.3, 3),
                       bell(0.32, G5, 0.45, 0.14), at(0.07, bell(0.32, E5, 0.45, 0.14)),
                       at(0.14, bell(0.36, C5, 0.5, 0.18))))
    # the highlight moving: a soft, short pluck
    write('tile_move', bell(0.06, 1400, 1.0, 0.018, 0.001, 3.0, 0.8))
    # a tile started: a chord swelling up, with a shimmer
    write('launch', mix(at(0.0, bell(0.7, C5, 0.4, 0.35, 0.01)), at(0.04, bell(0.7, E5, 0.4, 0.35, 0.01)),
                        at(0.08, bell(0.7, G5, 0.4, 0.35, 0.01)), at(0.12, bell(0.65, C6, 0.45, 0.3, 0.01)),
                        at(0.16, bell(0.5, E6, 0.25, 0.2, 0.005, 3.5, 2.0)),
                        noise(0.25, 2000, 9000, 0.15, 4)))
    # another category: a page turning, and a light note
    write('change_category', mix(noise(0.22, 1200, 7000, 0.45, 5), at(0.05, bell(0.2, D5, 0.35, 0.08, 0.002, 2.0, 0.6, 5))))
    # a menu opening: a round pop
    write('context_menu', bell(0.14, A5, 1.0, 0.05, 0.001, 1.5, 1.5, -7))
    # the keys of the on-screen keyboard: a click, and a lower one to delete
    write('button_click1', mix(noise(0.03, 2500, 2500, 0.5, 6, 'hit'), bell(0.04, 2200, 0.6, 0.01, 0.0005, 2.7, 0.6)))
    write('button_click1_delete', mix(noise(0.035, 1400, 1400, 0.5, 7, 'hit'), bell(0.05, 1300, 0.6, 0.012, 0.0005, 2.7, 0.6)))
    # another click, glassier
    write('button_click2', bell(0.05, 3100, 1.0, 0.012, 0.0005, 3.5, 1.0))
    write('button_click2_delete', bell(0.06, 1900, 1.0, 0.014, 0.0005, 3.5, 1.0))
    # back: two notes down
    write('button_back', mix(bell(0.12, A5, 0.6, 0.05, 0.002, 2.0, 0.8), at(0.06, bell(0.16, E5, 0.6, 0.06, 0.002, 2.0, 0.8))))


if __name__ == '__main__':
    main()
