"""Generate the impact sounds. Standard library only:

    python3 tools/make_sounds.py          # write audio/*.wav
    python3 tools/make_sounds.py --check  # fail if the committed files differ

Each sound is a handful of exponentially decaying sine partials (modal
synthesis, the textbook way to fake a struck object) plus a short burst of
low-passed noise for the contact click. The noise comes from a seeded RNG, so
the output is byte-for-byte reproducible and the sounds are a diff like the
paddle mesh, rather than opaque binaries of unknown origin. See ASSETS.md for
why that matters here.

Tuning notes, in the order the ear reads them:

- paddle: short and mid-high, a hollow "pock". The event the player causes,
  so it is the brightest and the most present.
- wall: lower and longer, a hard "clack" with more noise in the attack. The
  front wall scores, so it should read as solid and far away.
- floor: a dull low thud with a little downward pitch glide and almost no
  click. It happens constantly and must sit back behind the other two.

Pitch and level are varied per hit at runtime (scripts/ball.gd); these are
the base timbres only.
"""

import argparse
import io
import math
import random
import struct
import sys
import wave
from pathlib import Path

RATE = 44100
# Leave headroom rather than normalizing to full scale: the runtime adds up
# to a few dB on hard hits, and polyphonic layering sums voices.
PEAK = 0.89  # about -1 dBFS
AUDIO = Path(__file__).resolve().parent.parent / "audio"

# name: (length s, [(freq Hz, decay s, amplitude)], noise amp, noise decay s,
#        noise low-pass Hz, pitch glide (fractional drop over the decay), seed)
SOUNDS = {
    "paddle": (
        0.10,
        [(640.0, 0.030, 1.0), (1510.0, 0.016, 0.45), (2870.0, 0.007, 0.25)],
        0.55,
        0.0025,
        6000.0,
        0.04,
        1,
    ),
    "wall": (
        0.18,
        [(235.0, 0.060, 1.0), (548.0, 0.038, 0.6), (1260.0, 0.018, 0.35)],
        0.5,
        0.0050,
        2500.0,
        0.02,
        2,
    ),
    "floor": (
        0.14,
        [(105.0, 0.055, 1.0), (182.0, 0.030, 0.5), (410.0, 0.012, 0.15)],
        0.35,
        0.0080,
        900.0,
        0.12,
        3,
    ),
}


def synthesize(length, partials, noise_amp, noise_decay, noise_lp, glide, seed):
    rng = random.Random(seed)
    n = int(length * RATE)
    # One-pole low-pass coefficient for the noise burst.
    alpha = 1.0 - math.exp(-2.0 * math.pi * noise_lp / RATE)
    phases = [0.0] * len(partials)
    lp = 0.0
    out = []
    for i in range(n):
        t = i / RATE
        bend = 1.0 + glide * math.exp(-t / 0.02)
        s = 0.0
        for k, (freq, decay, amp) in enumerate(partials):
            phases[k] += 2.0 * math.pi * freq * bend / RATE
            s += amp * math.exp(-t / decay) * math.sin(phases[k])
        lp += alpha * (rng.uniform(-1.0, 1.0) - lp)
        s += noise_amp * math.exp(-t / noise_decay) * lp
        out.append(s)

    # A 1 ms fade-in keeps the first sample from being a click of its own,
    # and a 10 ms fade-out lands the tail on exact silence.
    fade_in = int(0.001 * RATE)
    fade_out = int(0.010 * RATE)
    for i in range(fade_in):
        out[i] *= i / fade_in
    for i in range(fade_out):
        out[n - 1 - i] *= i / fade_out

    scale = PEAK / max(abs(s) for s in out)
    return b"".join(struct.pack("<h", round(s * scale * 32767)) for s in out)


def encode(frames):
    """A canonical 16-bit mono PCM wav, built in memory so --check can compare."""
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)
    return buf.getvalue()


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--check", action="store_true", help="compare against audio/ instead of writing"
    )
    args = parser.parse_args()

    stale = []
    for name, params in SOUNDS.items():
        data = encode(synthesize(*params))
        path = AUDIO / f"{name}.wav"
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                stale.append(path.name)
        else:
            path.write_bytes(data)
            print(f"wrote {path.relative_to(AUDIO.parent)} ({len(data)} bytes)")

    if stale:
        print(f"out of date with tools/make_sounds.py: {', '.join(stale)}")
        print("run `just sounds` and commit the result")
        return 1
    if args.check:
        print("audio/ matches tools/make_sounds.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
