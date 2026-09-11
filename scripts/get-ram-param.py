#!/usr/bin/env python3
"""RAM horizons: historical reproduction by default, corrected theory on request.

The exact model uses h IID uniform bytes and includes the first subsequent byte
at least as large as their maximum in the chunk (length h + waiting time).
It is a theoretical calibration, not a replacement for measured run settings.
"""

import argparse
import math


def exact_mean(h):
    """Expected length, averaging geometric waiting times over the maximum."""
    if not math.isfinite(h) or h < 1:
        raise ValueError("horizon must be finite and at least 1")
    return h + math.fsum(
        256 / (256 - m) * (((m + 1) / 256) ** h - (m / 256) ** h)
        for m in range(256)
    )


def legacy_equation(h, mu):
    # Keep the original arithmetic and fsolve initialization for reproduction.
    sum_term = sum(m * (((m + 1) / 256) ** h - (m / 256) ** h) for m in range(256))
    return mu - (h + (1 - (1 / 256) * sum_term) ** -1)


def legacy_horizon(target):
    from scipy.optimize import fsolve

    return round(fsolve(legacy_equation, 1, args=(target))[0])


def exact_horizon(target):
    """Nearest achievable integer-horizon mean; smaller horizon wins ties.

    The mean is strictly increasing: both h and its maximum's expected waiting
    time increase with h. Binary search therefore brackets the global optimum.
    """
    if not math.isfinite(target) or target < exact_mean(1):
        raise ValueError(f"exact target must be finite and at least {exact_mean(1):.12g} bytes")
    lo, hi = 1, math.ceil(target)
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if exact_mean(mid) < target:
            lo = mid
        else:
            hi = mid
    return min((lo, hi), key=lambda h: (abs(exact_mean(h) - target), h))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", type=float, help="desired mean chunk size in bytes")
    parser.add_argument(
        "--mode", choices=("legacy", "exact"), default="legacy",
        help="legacy reproduces published settings (default); exact uses corrected theory",
    )
    args = parser.parse_args()
    if not math.isfinite(args.target) or args.target <= 0:
        parser.error("target must be finite and positive")
    try:
        horizon = legacy_horizon(args.target) if args.mode == "legacy" else exact_horizon(args.target)
    except ValueError as exc:
        parser.error(str(exc))
    print(horizon)


if __name__ == "__main__":
    main()
