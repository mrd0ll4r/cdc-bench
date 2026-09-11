"""Calculate the empirical MII mean-size approximation; no simulation is run.

w counts bytes in an increasing window, i.e. w-1 adjacent comparisons.
The 1.14 multiplier is an empirical calibration constant, not a theorem.
Historical filename and two-column output are retained for compatibility.
"""
import math

def mu(w):
    binom = math.comb(256, w)
    result = 1.14 / (binom * (256 ** -w)) + w
    return result

if __name__ == "__main__":
    for w in range(20):
        print(w, round(mu(w)))
