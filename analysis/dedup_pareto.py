#!/usr/bin/env python3
"""Validate normalized measurements and emit metadata-adjusted Pareto analysis.

No experiments are run. See README.md for the input contract and provenance.
"""
import argparse
import csv
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from fractions import Fraction
import hashlib
import json
from pathlib import Path

DATASETS = ("CODE", "WEB", "VMB", "DB")
ALGORITHMS = {
    "fsc": "FSC", "ae": "AE", "ram": "RAM", "mii": "MII", "pci": "PCI",
    "rabin_32": "Rabin", "buzhash_32": "Buzhash", "gear": "Gear", "seq-cdc": "SeqCDC",
}
TARGETS = (512, 1024, 2048, 4096, 8192)
METADATA_COSTS = (28, 48, 64)
REQUIRED = ("algorithm", "dataset", "target_chunk_size", "dataset_size", "chunk_count",
            "unique_chunks_size_sum", "mean_chunk_size", "run_id",
            "dataset_fingerprint", "chunk_population")
COLORS = ("blue", "red", "teal", "orange", "violet", "black", "brown", "magenta", "gray")
MARKS = ("o", "square", "triangle", "diamond", "pentagon", "x", "+", "star", "asterisk")


@dataclass(frozen=True)
class Measurement:
    algorithm: str
    dataset: str
    target_chunk_size: int
    dataset_size: int
    chunk_count: int
    unique_chunks_size_sum: int
    run_id: str
    dataset_fingerprint: str

    @property
    def mean(self):
        return Fraction(self.dataset_size, self.chunk_count)

    def savings(self, metadata_bytes):
        return 1 - Fraction(self.unique_chunks_size_sum + metadata_bytes * self.chunk_count,
                            self.dataset_size)


def positive_integer(raw, name, zero_allowed=False):
    try:
        value = int(raw)
    except (ValueError, TypeError):
        raise ValueError(f"{name} must be an integer") from None
    if value < (0 if zero_allowed else 1):
        raise ValueError(f"{name} out of range")
    return value


def load_measurements(path):
    """Require the complete paper grid and reject duplicate/mismatched populations."""
    rows, seen, identities = [], set(), {}
    with Path(path).open(newline="", encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        header = reader.fieldnames or []
        if len(set(header)) != len(header):
            raise ValueError("duplicate CSV column")
        missing = set(REQUIRED) - set(header)
        if missing:
            raise ValueError(f"missing columns: {', '.join(sorted(missing))}")
        for line, raw in enumerate(reader, 2):
            try:
                if None in raw or any(raw[name] is None for name in REQUIRED):
                    raise ValueError("malformed CSV row")
                algorithm, dataset = raw["algorithm"].strip(), raw["dataset"].strip().upper()
                if algorithm not in ALGORITHMS or dataset not in DATASETS:
                    raise ValueError("unknown algorithm or dataset (no legacy PDF/LNX aliases)")
                target = positive_integer(raw["target_chunk_size"], "target_chunk_size")
                if target not in TARGETS:
                    raise ValueError("target_chunk_size must be the configured paper target, not a MII window/prediction")
                key = (algorithm, dataset, target)
                if key in seen:
                    raise ValueError(f"duplicate configuration: {key}")
                seen.add(key)
                size = positive_integer(raw["dataset_size"], "dataset_size")
                count = positive_integer(raw["chunk_count"], "chunk_count")
                unique = positive_integer(raw["unique_chunks_size_sum"], "unique_chunks_size_sum")
                if count > size or unique > size:
                    raise ValueError("chunk count or unique bytes exceed input bytes")
                try:
                    mean = Decimal(raw["mean_chunk_size"])
                except InvalidOperation:
                    raise ValueError("mean_chunk_size must be finite and positive") from None
                if not mean.is_finite() or mean <= 0:
                    raise ValueError("mean_chunk_size must be finite and positive")
                if abs(Fraction(mean) - Fraction(size, count)) > Fraction(size, count) / 1_000_000:
                    raise ValueError("mean_chunk_size disagrees with dataset_size/chunk_count; use all emitted chunks")
                if raw["chunk_population"].strip() != "all-emitted":
                    raise ValueError("chunk_population must be all-emitted, including final partial chunks")
                run = raw["run_id"].strip()
                fingerprint = raw["dataset_fingerprint"].strip()
                if not run or not fingerprint:
                    raise ValueError("run_id and dataset_fingerprint cannot be empty")
                identity = (size, fingerprint)
                if dataset in identities and identities[dataset] != identity:
                    raise ValueError(f"inconsistent dataset bytes/fingerprint for {dataset}")
                identities[dataset] = identity
                rows.append(Measurement(algorithm, dataset, target, size, count, unique, run, fingerprint))
            except ValueError as error:
                raise ValueError(f"line {line}: {error}") from None
    expected = {(a, d, t) for a in ALGORITHMS for d in DATASETS for t in TARGETS}
    if seen != expected:
        raise ValueError(f"incomplete paper grid: missing {len(expected - seen)} of {len(expected)} configurations")
    return sorted(rows, key=lambda r: (DATASETS.index(r.dataset), list(ALGORITHMS).index(r.algorithm), r.target_chunk_size))


def nondominated(rows, metadata_bytes):
    """Maximize both achieved mean and savings; identical coordinates retain ties."""
    return {
        row for row in rows if not any(
            other.mean >= row.mean and other.savings(metadata_bytes) >= row.savings(metadata_bytes)
            and (other.mean > row.mean or other.savings(metadata_bytes) > row.savings(metadata_bytes))
            for other in rows
        )
    }


def figure_tex(rows, metadata_bytes):
    """Four panels, measured points only; ring nondominated points with no interpolation."""
    text = [r"% Generated by analysis/dedup_pareto.py; do not edit.", r"\centering"]
    for index, dataset in enumerate(DATASETS):
        group = [row for row in rows if row.dataset == dataset]
        frontier = nondominated(group, metadata_bytes)
        text.extend([
            r"\begin{minipage}{0.49\textwidth}\centering",
            r"\begin{tikzpicture}",
            r"\begin{axis}[width=\linewidth,height=4.8cm,scale only axis=false,",
            f"title={{{dataset}}},",
            r"xlabel={Achieved mean (B)},ylabel={Adjusted savings (\%)},",
            r"xmode=log,log basis x=2,scaled y ticks=false,",
            r"tick label style={font=\scriptsize},label style={font=\scriptsize},",
            r"title style={font=\small},grid=major]",
        ])
        for ai, algorithm in enumerate(ALGORITHMS):
            points = [r for r in group if r.algorithm == algorithm]
            coords = " ".join(f"({float(r.mean):.12g},{float(r.savings(metadata_bytes) * 100):.12g})" for r in points)
            text.append(f"\\addplot[only marks,color={COLORS[ai]},mark={MARKS[ai]},mark size=1.6pt] coordinates {{{coords}}};")
        coords = " ".join(f"({float(r.mean):.12g},{float(r.savings(metadata_bytes) * 100):.12g})" for r in group if r in frontier)
        text.extend([
            f"\\addplot[only marks,color=black,mark=o,mark size=3.3pt] coordinates {{{coords}}};",
            r"\end{axis}\end{tikzpicture}\end{minipage}",
            r"\hfill" if index % 2 == 0 else r"\par\medskip",
        ])
    legend = []
    for index, (algorithm, label) in enumerate(ALGORITHMS.items()):
        legend.append(f"\\tikz{{\\draw plot[only marks,mark={MARKS[index]},color={COLORS[index]},mark size=1.6pt] coordinates {{(0,0)}};}}~{label}")
    text.append(r"{\scriptsize " + r"\quad ".join(legend[:5]) + r"\par " + r"\quad ".join(legend[5:]) + r"\quad Large ring: nondominated measured configuration.}")
    return "\n".join(text) + "\n"


def write_outputs(rows, source, output):
    output.mkdir(parents=True, exist_ok=True)
    fields = [*REQUIRED, "metadata_bytes", "raw_savings", "adjusted_savings", "nondominated"]
    with (output / "dedup-adjusted.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for cost in METADATA_COSTS:
            frontiers = {d: nondominated([r for r in rows if r.dataset == d], cost) for d in DATASETS}
            for row in rows:
                writer.writerow({
                    "algorithm": row.algorithm, "dataset": row.dataset,
                    "target_chunk_size": row.target_chunk_size, "dataset_size": row.dataset_size,
                    "chunk_count": row.chunk_count, "unique_chunks_size_sum": row.unique_chunks_size_sum,
                    "mean_chunk_size": f"{float(row.mean):.12g}", "run_id": row.run_id,
                    "dataset_fingerprint": row.dataset_fingerprint, "chunk_population": "all-emitted",
                    "metadata_bytes": cost, "raw_savings": f"{float(row.savings(0)):.12g}",
                    "adjusted_savings": f"{float(row.savings(cost)):.12g}",
                    "nondominated": str(row in frontiers[row.dataset]).lower(),
                })
            (output / f"dedup-pareto-{cost}.tex").write_text(figure_tex(rows, cost), encoding="utf-8")
    manifest = {
        "input_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "rows": len(rows), "datasets": DATASETS, "algorithms": list(ALGORITHMS),
        "configured_targets_bytes": TARGETS, "metadata_bytes_per_emitted_chunk": METADATA_COSTS,
        "chunk_population": "all-emitted", "mean_relative_tolerance": 1e-6,
        "dominance": "maximize achieved mean and adjusted savings; retain exact ties",
        "provenance_note": "The supplier attests that all fields in each row describe the named run; identifiers do not independently prove this.",
    }
    (output / "dedup-provenance.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="normalized CSV with matched measurement provenance")
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    try:
        rows = load_measurements(args.input)
        write_outputs(rows, args.input, args.output_dir)
    except (ValueError, OSError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    main()
