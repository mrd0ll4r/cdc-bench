"""Searches PCI parameters (w, theta) for the five publication targets.

This current seeded search does not establish the historical calibration seed
or guarantee the exact published pairs; scripts/utils.sh preserves those pairs.

PCI cuts when the popcount of a w-byte window reaches theta bits; the window
resets w bytes past a boundary. No closed form for (w, theta) -> mean chunk
size is known, so each pair is measured on seeded uniformly random data.

Search:  w in [30, 65] bytes, theta in [4w, 8w] bits (bisected, since the mean
         is monotone in theta); minimise |mean/target - 1|; ties to smaller w,
         then smaller theta.
"""
import numpy as np

SEED = 20250901
TARGETS = [512, 1024, 2048, 4096, 8192]
W_RANGE = range(30, 66)
POP = np.unpackbits(np.arange(256, dtype=np.uint8)[:, None], axis=1).sum(1)


def mean_chunk_size(w, theta, target, min_chunks=20_000):
    """Mean PCI chunk size over seeded random blocks, or inf if no boundary."""
    rng = np.random.default_rng((SEED * 1_000_003 + w * 8191 + theta) % 2**32)
    nbytes = int(min(max(1 << 18, min_chunks * target * 2), 1 << 26))
    total = chunks = 0
    for _ in range(32):
        pops = np.cumsum(POP[rng.integers(0, 256, nbytes, dtype=np.uint8)], dtype=np.int32)
        matches = np.flatnonzero(pops[w:] - pops[:-w] >= theta)
        end, count = 0, 0
        while (i := int(np.searchsorted(matches, end))) < matches.size:
            end, count = int(matches[i]) + w, count + 1
        if count == 0:
            return float("inf")
        total, chunks = total + end, chunks + count
        if chunks >= min_chunks:
            break
    return total / chunks


def best_theta(w, target):
    """Theta whose mean is closest to target, by bisection over [4w, 8w]."""
    memo = {}
    mean = lambda t: memo.setdefault(t, mean_chunk_size(w, t, target))
    lo, hi = 4 * w, 8 * w
    while lo < hi:
        mid = (lo + hi) // 2
        lo, hi = (mid + 1, hi) if mean(mid) < target else (lo, mid)
    theta = min((t for t in (lo - 1, lo, lo + 1) if 4 * w <= t <= 8 * w),
                key=lambda t: (abs(mean(t) - target), t))
    return theta, mean(theta)


print(f"{'mu':>5} {'w bytes':>8} {'8w bits':>8} {'theta':>6} {'theta/8w':>9} {'mean':>8}")
for target in TARGETS:
    cands = [(w,) + best_theta(w, target) for w in W_RANGE if w < target]
    w, theta, mean = min(cands, key=lambda c: (abs(c[2] / target - 1), c[0], c[1]))
    print(f"{target:5d} {w:8d} {8*w:8d} {theta:6d} {theta/(8*w):9.3f} {mean:8.0f}")
