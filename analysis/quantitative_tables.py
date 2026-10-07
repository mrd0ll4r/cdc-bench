#!/usr/bin/env python3
"""Generate quantitative manuscript Tables IX and X from exact run summaries.

Standard library only. See analysis/quantitative_tables.md for the input contract.
"""
import argparse
import csv
import json
from decimal import Decimal, InvalidOperation
from pathlib import Path

ALGORITHMS = ('rabin_32', 'buzhash_32', 'gear', 'ae', 'ram', 'pci', 'mii', 'seq-cdc')
LABELS = dict(zip(ALGORITHMS, ('Rabin', 'Buzhash', 'Gear', 'AE', 'RAM', 'PCI', 'MII', 'SeqCDC')))
LABELS['fsc'] = 'FSC'
DATASETS = ('RAND', 'CODE', 'WEB', 'VMB', 'DB')
REAL = DATASETS[1:]
TARGETS = (512, 1024, 2048, 4096, 8192)
CODES = {'CODE': 'C', 'WEB': 'W', 'VMB': 'V', 'DB': 'D'}
PROVENANCE = ('run_id', 'dataset_fingerprint', 'chunk_population')
BASE = ('algorithm', 'dataset', 'target_chunk_size', *PROVENANCE)
IX_FIELDS = ('mean_chunk_size', 'sd_chunk_size')
X_FIELDS = (*IX_FIELDS, 'dataset_size', 'chunk_count', 'unique_chunks_size_sum', 'median_throughput_mib_s')
MISSING = ('', 'NA', 'N/A')
D = Decimal


def number(value, field):
    if value.strip() in MISSING:
        return None
    try:
        v = D(value)
    except InvalidOperation as exc:
        raise ValueError(f'{field}: invalid number {value!r}') from exc
    if not v.is_finite() or v < 0 or (field not in ('sd_chunk_size', 'unique_chunks_size_sum') and v == 0):
        raise ValueError(f'{field}: invalid value {value!r}')
    if field in ('dataset_size', 'chunk_count', 'unique_chunks_size_sum') and v != v.to_integral_value():
        raise ValueError(f'{field}: expected integer bytes/count')
    return v


def load_rows(path, table, include_fsc=False, allow_missing=False):
    algorithms = ALGORITHMS + (('fsc',) if include_fsc else ())
    fields = IX_FIELDS if table == 'ix' else X_FIELDS
    rows = {}
    identities = {}
    with open(path, newline='') as f:
        reader = csv.DictReader(f)
        if reader.fieldnames and len(reader.fieldnames) != len(set(reader.fieldnames)):
            raise ValueError('Duplicate CSV column names')
        if not set(BASE + fields) <= set(reader.fieldnames or ()):
            raise ValueError(f'Required columns: {", ".join(BASE + fields)}')
        for line, row in enumerate(reader, 2):
            if None in row or any(v is None for v in row.values()):
                raise ValueError(f'Line {line}: malformed CSV row')
            a, ds = row['algorithm'].strip(), row['dataset'].strip()
            try:
                target = int(row['target_chunk_size'])
            except ValueError as exc:
                raise ValueError(f'Line {line}: invalid target') from exc
            if a not in ALGORITHMS + ('fsc',) or ds not in DATASETS or target not in TARGETS:
                raise ValueError(f'Line {line}: unknown algorithm, dataset, or configured target')
            key = a, ds, target
            if key in rows:
                raise ValueError(f'Duplicate result: {key}')
            values = {field: number(row[field], field) for field in fields}
            has_values = any(v is not None for v in values.values())
            if has_values and (any(not row[p].strip() for p in PROVENANCE) or row['chunk_population'] != 'all-emitted'):
                raise ValueError(f'{key}: measured values require run/fingerprint and all-emitted population')
            mean, sd = values['mean_chunk_size'], values['sd_chunk_size']
            if table == 'x':
                size, count, unique = (values[k] for k in ('dataset_size', 'chunk_count', 'unique_chunks_size_sum'))
                if size is not None and unique is not None and unique > size:
                    raise ValueError(f'{key}: unique bytes exceed input bytes')
                if size is not None and count is not None and count > size:
                    raise ValueError(f'{key}: more chunks than bytes')
                if None not in (size, count, mean) and abs(mean - size/count) > D('0.000001') * (size/count):
                    raise ValueError(f'{key}: mean is inconsistent with all-emitted byte/count accounting')
            if has_values:
                identity = (row['dataset_fingerprint'], values.get('dataset_size'))
                old = identities.setdefault(ds, identity)
                if old[0] != identity[0] or (None not in (old[1], identity[1]) and old[1] != identity[1]):
                    raise ValueError(f'{ds}: inconsistent dataset fingerprint or byte count')
                if old[1] is None and identity[1] is not None:
                    identities[ds] = identity
            rows[key] = {**values, **{p: row[p] for p in PROVENANCE}}
    expected = [(a, ds, t) for a in algorithms for ds in (DATASETS if table == 'ix' else REAL)
                for t in (TARGETS if table == 'ix' else (2048,))]
    missing = [key for key in expected if key not in rows or any(rows[key][f] is None for f in fields)]
    if missing and not allow_missing:
        raise ValueError(f'{len(missing)} missing/incomplete required configurations; first: {missing[0]}. Use --allow-missing only for review placeholders.')
    return rows, algorithms, missing


def overview(rows, algorithms=ALGORITHMS):
    output = {}
    for a in algorithms:
        output[a] = {}
        for ds in DATASETS:
            selected = [rows.get((a, ds, t), {}) for t in TARGETS]
            errors = [abs(r['mean_chunk_size']/D(t)-1) if r.get('mean_chunk_size') is not None else None
                      for r, t in zip(selected, TARGETS)]
            cvs = [r['sd_chunk_size']/r['mean_chunk_size'] if r.get('mean_chunk_size') is not None and r.get('sd_chunk_size') is not None else None for r in selected]
            output[a][ds] = tuple(sum(v)/5 if None not in v else None for v in (errors, cvs))
    return output


def summary(rows, algorithms=ALGORITHMS):
    output = {}
    for a in algorithms:
        metrics = [[], [], [], []]
        for ds in REAL:
            r = rows.get((a, ds, 2048), {})
            mean, sd = r.get('mean_chunk_size'), r.get('sd_chunk_size')
            size, count, unique = (r.get(k) for k in ('dataset_size', 'chunk_count', 'unique_chunks_size_sum'))
            vals = (1-(unique+64*count)/size if None not in (size, count, unique) else None,
                    r.get('median_throughput_mib_s'), abs(mean/2048-1) if mean is not None else None,
                    sd/mean if None not in (sd, mean) else None)
            for column, value in zip(metrics, vals):
                column.append((ds, value))
        output[a] = []
        for i, column in enumerate(metrics):
            if any(v is None for _, v in column):
                output[a].append((None, ()))
            else:
                worst = (min if i < 2 else max)(v for _, v in column)
                output[a].append((worst, tuple(ds for ds, v in column if v == worst)))
    return output


def fmt(v, percent=False):
    return r'\textemdash{}' if v is None else f'{v * (100 if percent else 1):.2f}'


def render_ix(data, algorithms):
    lines = [r'\begingroup', r'\small\setlength{\tabcolsep}{5pt}', r'\begin{tabular}{lrrrrrrrrrr}', r'\toprule',
             r'& \multicolumn{5}{c}{Mean absolute relative target error (\%)} & \multicolumn{5}{c}{Mean coefficient of variation} \\',
             r'\cmidrule(lr){2-6}\cmidrule(lr){7-11}', 'Algorithm & ' + ' & '.join(DATASETS * 2) + r' \\', r'\midrule']
    for a in algorithms:
        lines.append(LABELS[a] + ' & ' + ' & '.join(fmt(data[a][ds][i], percent=i == 0) for i in (0, 1) for ds in DATASETS) + r' \\')
    lines.extend([r'\bottomrule', r'\end{tabular}', r'\endgroup'])
    if any(v is None for a in algorithms for pair in data[a].values() for v in pair):
        lines.append(r'\par\smallskip\footnotesize\textbf{REBUTTAL-DATA-PENDING:} Dashes denote unavailable exact aggregates, not zero. Each aggregate requires all five target settings.')
    return '\n'.join(lines) + '\n'


def render_x(data, algorithms):
    ranks = []
    for i in range(4):
        values = [data[a][i][0] for a in ALGORITHMS]
        # Do not rank a partial domain. FSC is a separate reference, never changes CDC ranking.
        ranks.append(sorted(set(values), reverse=i < 2)[:2] if None not in values else [])
    lines = [r'\begingroup', r'\scriptsize\setlength{\tabcolsep}{3pt}', r'\begin{tabular}{lrrrr}', r'\toprule',
             r'Algorithm & Min. $D_{64}$ & Min. throughput & Max. error & Max. CV \\',
             r'& (\%) $\uparrow$ & (MiB/s) $\uparrow$ & (\%) $\downarrow$ & $\downarrow$ \\', r'\midrule']
    for a in algorithms:
        cells = []
        for i, (value, datasets) in enumerate(data[a]):
            s = fmt(value, percent=i in (0, 2))
            if a in ALGORITHMS and value is not None and value in ranks[i]:
                s = ('\\textbf{' if ranks[i].index(value) == 0 else '\\underline{') + s + '}'
            if datasets:
                s += r'\textsuperscript{' + ','.join(CODES[d] for d in datasets) + '}'
            cells.append(s)
        lines.append(LABELS[a] + ' & ' + ' & '.join(cells) + r' \\')
    lines.extend([r'\bottomrule', r'\end{tabular}', r'\endgroup',
                  r'\par\smallskip\footnotesize Superscripts identify every dataset attaining the extremum: C = CODE, W = WEB, V = VMB, D = DB. Bold: best; underline: second distinct value among the eight CDC algorithms, retaining exact ties. Arrows indicate preferred direction. Ranking is withheld for any incomplete metric.'])
    if any(value is None for a in algorithms for value, _ in data[a]):
        lines.append(r'\par\smallskip\footnotesize\textbf{REBUTTAL-DATA-PENDING:} Dashes denote unavailable worst-case values, not zero. Each value requires all four realistic datasets.')
    return '\n'.join(lines) + '\n'


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input', type=Path)
    p.add_argument('--table', choices=('ix', 'x'), default='ix')
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--allow-missing', action='store_true')
    p.add_argument('--include-fsc', action='store_true')
    p.add_argument('--template', action='store_true', help='Write a full empty input CSV, without generating results')
    args = p.parse_args()
    if args.template:
        with args.output.open('w', newline='') as f:
            w = csv.DictWriter(f, fieldnames=BASE + X_FIELDS)
            w.writeheader()
            for a in ALGORITHMS + (('fsc',) if args.include_fsc else ()):
                for ds in DATASETS:
                    for t in TARGETS:
                        w.writerow(dict(algorithm=a, dataset=ds, target_chunk_size=t))
        return
    if args.input is None:
        p.error('--input is required unless --template is used')
    try:
        rows, algorithms, missing = load_rows(args.input, args.table, args.include_fsc, args.allow_missing)
    except (ValueError, OSError) as exc:
        p.error(str(exc))
    values = overview(rows, algorithms) if args.table == 'ix' else summary(rows, algorithms)
    rendered = render_ix(values, algorithms) if args.table == 'ix' else render_x(values, algorithms)
    args.output.write_text(rendered)
    audit = {'table': args.table, 'input': str(args.input.resolve()), 'missing_configurations': missing,
             'values': values, 'source_rows': [{'key': k, **v} for k, v in rows.items()]}
    args.output.with_suffix('.audit.json').write_text(json.dumps(audit, indent=2, default=str) + '\n')


if __name__ == '__main__':
    main()
