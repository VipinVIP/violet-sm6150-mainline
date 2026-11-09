#!/usr/bin/env python3
"""Generate a short pleasant test tune (stereo 48 kHz s16) for jack verification."""
import math, struct, wave, random

SR = 48000
DUR = 30.0
N = int(SR * DUR)
buf = [0.0] * N

# A minor pentatonic scale (Hz)
A3, C4, D4, E4, G4, A4, C5, D5, E5 = 220.0, 261.63, 293.66, 329.63, 392.0, 440.0, 523.25, 587.33, 659.25


def add_tone(start, dur, freq, amp, pan=0.0, decay=2.4):
    p0 = int(start * SR)
    n = int(dur * SR)
    ph = 0.0
    for i in range(n):
        t = i / SR
        env = min(1.0, t / 0.012) * math.exp(-decay * t / dur)
        ph += 2 * math.pi * freq * (1.0 + 0.003 * math.sin(2 * math.pi * 5.0 * t)) / SR
        v = amp * env * (math.sin(ph) + 0.25 * math.sin(2 * ph) + 0.08 * math.sin(3 * ph))
        idx = p0 + i
        if 0 <= idx < N:
            buf[idx] += v * (1.0 - max(0.0, pan)) * 0.5
            if idx < N:
                pass
        # right channel handled by writing stereo later from a parallel pass
        idx2 = p0 + i
        if 0 <= idx2 < N:
            pass


melody = [
    (0.0, 0.6, A4), (0.6, 0.6, C5), (1.2, 0.6, D5), (1.8, 0.9, C5),
    (2.9, 0.6, A4), (3.5, 0.6, G4), (4.1, 0.6, A4), (4.7, 1.1, E4),
    (6.0, 0.6, C5), (6.6, 0.6, D5), (7.2, 0.6, E5), (7.8, 0.9, D5),
    (9.0, 0.6, C5), (9.6, 0.6, A4), (10.2, 0.6, G4), (10.8, 1.1, A4),
]
for rep in range(2):
    off = rep * 12.2
    for st, du, f in melody:
        add_tone(off + st, du, f, 0.28, decay=2.0)
    # bass
    for st, f in [(0.0, A3), (1.8, E4 / 2), (3.5, A3), (4.7, G4 / 2),
                  (6.0, C4), (7.8, G4 / 2), (9.0, A3), (10.8, E4 / 2)]:
        add_tone(off + st, 1.2, f, 0.22, decay=1.2)
    # soft pad
    for st, f in [(0.0, A3), (3.5, G4 / 2), (6.0, C4), (9.0, A3)]:
        add_tone(off + st, 3.0, f * 2, 0.05, decay=0.8)

# tiny stereo widening + light noise floor
frames = bytearray()
peak = max(1e-9, max(abs(v) for v in buf))
g = 0.6 / peak
random.seed(7)
for i, v in enumerate(buf):
    t = i / SR
    l = g * v * (0.92 + 0.08 * math.sin(2 * math.pi * 0.11 * t))
    r = g * v * (0.92 - 0.08 * math.sin(2 * math.pi * 0.11 * t))
    frames += struct.pack('<hh', int(max(-1, min(1, l)) * 32767), int(max(-1, min(1, r)) * 32767))

w = wave.open('/tmp/test-music.wav', 'wb')
w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
w.writeframes(bytes(frames)); w.close()
print('wrote /tmp/test-music.wav', len(frames), 'bytes')
