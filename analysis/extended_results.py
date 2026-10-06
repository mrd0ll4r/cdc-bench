#!/usr/bin/env python3
"""Validate author-supplied measurements and export extended-results tables (stdlib only)."""
import argparse
import csv
import hashlib
import io
import itertools
import json
import math
from pathlib import Path
import re
import shutil
import statistics
from collections import Counter

ALGORITHMS = ('rabin_32', 'buzhash_32', 'gear', 'ae', 'ram', 'pci', 'mii', 'seq-cdc')
DATASETS = ('RAND', 'CODE', 'WEB', 'VMB', 'DB')
TARGETS = (512, 1024, 2048, 4096, 8192)
GRID = tuple(itertools.product(ALGORITHMS, DATASETS, TARGETS))
CHUNK_FIELDS = ('stream_id', 'chunk_index', 'chunk_size', 'is_final')
TIMING_FIELDS = ('repetition', 'elapsed_seconds', 'processed_bytes')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def integer(value, name, minimum=0):
    require(not isinstance(value, bool) and re.fullmatch(r'[0-9]+', str(value)) is not None,
            f'{name}: expected an integer')
    value = int(value)
    require(value >= minimum, f'{name}: must be >= {minimum}')
    return value


def nonempty(value, name):
    require(isinstance(value, str) and bool(value.strip()), f'{name}: required nonempty string')
    return value


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f'duplicate JSON key: {key}')
        result[key] = value
    return result


def read_csv(source, fields, name):
    # The production path is streamed; bytes are accepted only for small unit fixtures.
    stream = (source.open('r', encoding='utf-8-sig', newline='') if isinstance(source, Path)
              else io.StringIO(source.decode('utf-8-sig'), newline=''))
    try:
        reader = csv.DictReader(stream, strict=True)
        require(reader.fieldnames == list(fields), f'{name}: expected CSV columns {fields}')
        for row in reader:
            require(None not in row and all(v is not None and v != '' for v in row.values()),
                    f'{name}: malformed or empty CSV cell')
            yield row
    finally:
        stream.close()


def file_sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024*1024), b''):
            digest.update(block)
    return digest.hexdigest()


def quantile(sorted_values, numerator, denominator=100):
    """Inverse empirical CDF: x[ceil(n*p)-1], with exact integer rank arithmetic."""
    require(bool(sorted_values), 'quantile: empty population')
    return sorted_values[(len(sorted_values) * numerator + denominator - 1) // denominator - 1]


def chunk_statistics(raw, streams, target):
    counts = Counter()
    completed = set()
    current, index, nbytes, final = None, 0, 0, None

    def finish():
        if current is not None:
            require(nbytes == streams[current],
                    f'{current}: chunk population byte coverage mismatch (include final partial chunks)')
            require(final == '1', f'{current}: last emitted chunk must be final')
            completed.add(current)

    for row in read_csv(raw, CHUNK_FIELDS, 'chunks'):
        stream = row['stream_id']
        require(stream in streams, f'chunks: unknown stream {stream}')
        if stream != current:
            finish()
            require(stream not in completed, f'{stream}: records must be grouped by stream')
            current, index, nbytes, final = stream, 0, 0, None
        require(integer(row['chunk_index'], 'chunk_index') == index,
                f'{stream}: duplicate, unordered, or noncontiguous chunk indices')
        require(final != '1', f'{stream}: only the last emitted chunk may be final')
        size = integer(row['chunk_size'], 'chunk_size', 1)
        require(row['is_final'] in ('0', '1'), 'is_final must be 0 or 1')
        final = row['is_final']
        index += 1
        nbytes += size
        counts[size] += 1
    finish()
    require(all(size == 0 or stream in completed for stream, size in streams.items()),
            'chunks: missing nonempty stream (population mismatch)')
    count = sum(counts.values())
    require(count > 0, 'chunks: empty population')
    total = sum(size * n for size, n in counts.items())
    squares = sum(size * size * n for size, n in counts.items())
    # Integer numerator avoids cancellation in the sample variance for large datasets.
    sd = math.sqrt((count*squares-total*total)/(count*(count-1))) if count > 1 else None
    ranks = [(count*p + q-1)//q for p, q in ((25,100), (50,100), (75,100), (99,100), (999,1000))]
    values, cumulative, rank_index = [], 0, 0
    for size in sorted(counts):
        cumulative += counts[size]
        while rank_index < len(ranks) and cumulative >= ranks[rank_index]:
            values.append(size)
            rank_index += 1
    q1, median, q3, p99, p999 = values
    return dict(chunk_count=count, mean_chunk_size=total/count, sd_chunk_size=sd,
                q1_chunk_size=q1, median_chunk_size=median, q3_chunk_size=q3,
                p99_chunk_size=p99, p999_chunk_size=p999, max_chunk_size=max(counts),
                byte_fraction_above_4target=sum(v*n for v, n in counts.items() if v > 4*target)/total)


def timing_quantile(values, p):
    """R quantile(type=7): linear interpolation at zero-based index (n-1)*p."""
    index = (len(values)-1)*p
    lower = math.floor(index)
    fraction = index-lower
    return values[lower] + fraction*(values[min(lower+1, len(values)-1)]-values[lower])


def timing_statistics(raw, size, count):
    rows = list(read_csv(raw, TIMING_FIELDS, 'timings'))
    require(len(rows) == count, 'timings: repetition count mismatch')
    repetitions = []
    normalized = []
    for row in rows:
        repetition = integer(row['repetition'], 'repetition')
        require(repetition not in repetitions, 'timings: duplicate repetition')
        repetitions.append(repetition)
        elapsed = float(row['elapsed_seconds'])
        require(math.isfinite(elapsed) and elapsed > 0, 'timings: elapsed_seconds must be finite and positive')
        require(integer(row['processed_bytes'], 'processed_bytes', 1) == size,
                'timings: processed_bytes disagrees with dataset_size')
        require(math.isfinite(size/elapsed/2**20), 'timings: nonfinite throughput')
        normalized.append(dict(repetition=repetition, elapsed_seconds=elapsed,
                               processed_bytes=size, throughput_mib_s=size/elapsed/2**20))
    require(sorted(repetitions) == list(range(count)), 'timings: repetitions must be 0 through count-1')
    values = sorted(row['throughput_mib_s'] for row in normalized)
    q1, q3 = timing_quantile(values, .25), timing_quantile(values, .75)
    return dict(timing_repetitions=count, median_throughput_mib_s=statistics.median(values),
                q1_throughput_mib_s=q1, q3_throughput_mib_s=q3, iqr_throughput_mib_s=q3-q1), normalized


def analyze(manifest_path, allow_missing=False):
    manifest_raw = manifest_path.read_bytes()
    manifest = json.loads(manifest_raw, object_pairs_hook=unique_object,
                          parse_constant=lambda v: require(False, f'nonfinite JSON number: {v}'))
    require(isinstance(manifest, dict), 'manifest must be an object')
    require(type(manifest.get('schema_version')) is int and manifest['schema_version'] == 1, 'schema_version must be 1')
    require(manifest.get('chunk_population') == 'all-emitted', 'chunk_population must be all-emitted')
    require(manifest.get('timing_measure') in ('cpu-task-clock', 'wall-clock'),
            'timing_measure must be cpu-task-clock or wall-clock')
    require(isinstance(manifest.get('datasets'), dict), 'datasets must be an object')
    require(set(manifest['datasets']) <= set(DATASETS), 'unknown dataset identifier')
    datasets = {}
    for name, dataset in manifest['datasets'].items():
        require(isinstance(dataset, dict), f'{name}: metadata must be an object')
        size = integer(dataset.get('dataset_size'), f'{name}.dataset_size', 1)
        fingerprint = dataset.get('dataset_fingerprint', '')
        require(isinstance(fingerprint, str) and re.fullmatch(r'sha256:[0-9a-f]{64}', fingerprint),
                f'{name}: dataset_fingerprint must be sha256:<64 lowercase hex digits>')
        nonempty(dataset.get('provenance'), f'{name}.provenance')
        streams = dataset.get('stream_sizes')
        require(isinstance(streams, dict) and bool(streams), f'{name}: stream_sizes required')
        for stream, nbytes in streams.items():
            nonempty(stream, 'stream_id')
            integer(nbytes, f'{stream}.stream_size')
        streams = {k: int(v) for k, v in streams.items()}
        require(sum(streams.values()) == size, f'{name}: stream_sizes disagree with dataset_size')
        datasets[name] = (size, fingerprint, streams)
    require(isinstance(manifest.get('runs'), list), 'runs must be a list')
    summaries, timings, raw_files, seen, run_ids = [], [], {}, set(), set()
    for run in manifest['runs']:
        require(isinstance(run, dict), 'run metadata must be an object')
        algorithm = nonempty(run.get('algorithm'), 'algorithm')
        dataset = nonempty(run.get('dataset'), 'dataset')
        target = integer(run.get('target_chunk_size'), 'target_chunk_size', 1)
        key = algorithm, dataset, target
        require(key in GRID, f'unknown grid setting: {key}')
        require(key not in seen, f'duplicate grid setting: {key}; select one documented run per setting')
        seen.add(key)
        run_id = nonempty(run.get('run_id'), 'run_id')
        require(re.fullmatch(r'[A-Za-z0-9_.-]+', run_id), 'run_id must contain only letters, digits, _, ., -')
        require(run_id not in run_ids, f'duplicate run_id: {run_id}')
        run_ids.add(run_id)
        require(run.get('chunk_population') == 'all-emitted', f'{run_id}: chunk population mismatch')
        require(dataset in datasets, f'{run_id}: missing dataset metadata')
        size, fingerprint, streams = datasets[dataset]
        require(run.get('dataset_fingerprint') == fingerprint, f'{run_id}: dataset fingerprint mismatch')
        for field in ('environment_id', 'source_revision', 'command'):
            nonempty(run.get(field), f'{run_id}.{field}')
        require(isinstance(run.get('parameters'), dict) and bool(run['parameters']), f'{run_id}: exact parameters required')
        expected_chunks = integer(run.get('chunk_count'), 'chunk_count', 1)
        count = integer(run.get('timing_repetitions'), 'timing_repetitions', 2)
        raw = {}
        for kind in ('chunks', 'timings'):
            path = Path(nonempty(run.get(kind + '_csv'), kind + '_csv'))
            require(not path.is_absolute() and '..' not in path.parts, 'CSV paths must be relative without ..')
            source = (manifest_path.parent / path).resolve()
            require(source.is_relative_to(manifest_path.parent.resolve()), 'CSV must reside under manifest directory')
            raw[kind] = source
            raw_files[f'{run_id}.{kind}.csv'] = raw[kind]
        summary = dict(algorithm=algorithm, dataset=dataset, target_chunk_size=target,
                       dataset_size=size, run_id=run_id, dataset_fingerprint=fingerprint,
                       chunk_population='all-emitted', timing_measure=manifest['timing_measure'],
                       environment_id=run['environment_id'], source_revision=run['source_revision'],
                       parameters_json=json.dumps(run['parameters'], sort_keys=True, separators=(',', ':')))
        summary.update(chunk_statistics(raw['chunks'], streams, target))
        require(summary['chunk_count'] == expected_chunks, f'{run_id}: chunk_count mismatch')
        timing_summary, repetitions = timing_statistics(raw['timings'], size, count)
        summary.update(timing_summary)
        summaries.append(summary)
        timings.extend(dict(algorithm=algorithm, dataset=dataset, target_chunk_size=target,
                            run_id=run_id, dataset_fingerprint=fingerprint, **r) for r in repetitions)
    missing = [dict(algorithm=a, dataset=d, target_chunk_size=t) for a, d, t in GRID if (a, d, t) not in seen]
    require(allow_missing or not missing,
            f'{len(missing)} of {len(GRID)} expected settings missing; supply the complete grid or explicitly use --allow-missing for review placeholders')
    # DB/RAND comparison requires the same environment and implementation revision.
    lookup = {(s['algorithm'], s['dataset'], s['target_chunk_size']): s for s in summaries}
    comparisons = []
    for algorithm in ALGORITHMS:
        pair = [lookup.get((algorithm, d, 2048)) for d in ('RAND', 'DB')]
        if all(pair):
            rand, db = pair
            require((rand['environment_id'], rand['source_revision'], rand['parameters_json']) == (db['environment_id'], db['source_revision'], db['parameters_json']),
                    f'{algorithm}: DB/RAND timing comparison has incompatible provenance')
            comparisons.append(dict(algorithm=algorithm, target_chunk_size=2048,
                                    rand_run_id=rand['run_id'], db_run_id=db['run_id'],
                                    db_vs_rand_percent_change=100*(db['median_throughput_mib_s']/rand['median_throughput_mib_s']-1)))
    return manifest_raw, summaries, timings, missing, comparisons, raw_files


def tex(value):
    return ''.join({'_': r'\_', '%': r'\%', '&': r'\&', '#': r'\#', '$': r'\$',
                    '{': r'\{', '}': r'\}', '\\': r'\textbackslash{}', '~': r'\textasciitilde{}',
                    '^': r'\textasciicircum{}'}.get(c, c) for c in str(value))


def number(value):
    if isinstance(value, int):
        return str(value)
    return '--' if value is None else f'{value:.4g}'


def table(caption, header, rows, wide=True):
    environment = 'table*' if wide else 'table'
    return '\n'.join([r'\begin{' + environment + '}[!ht]', r'\centering\scriptsize', r'\caption{' + caption + '}',
                      r'\begin{tabular}{' + 'l' + 'r'*(len(header)-1) + '}', r'\toprule',
                      ' & '.join(header) + r' \\', r'\midrule',
                      *[' & '.join(row) + r' \\' for row in rows], r'\bottomrule',
                      r'\end{tabular}', r'\end{' + environment + '}', ''])


def render_tables(summaries, missing):
    chunk_tex, timing_tex = [], []
    if missing:
        warning = r'\par\noindent\textbf{RESULTS PENDING / AUTHOR INPUT REQUIRED.} Missing settings are listed in the coverage table; no measurement is imputed.\par'
        chunk_tex.append(warning)
        timing_tex.append(warning)
    for target in TARGETS:
        for dataset in DATASETS:
            rows = [s for s in summaries if s['target_chunk_size'] == target and s['dataset'] == dataset]
            if not rows:
                continue
            chunk_tex.append(table(f'{dataset}: chunk sizes in bytes, configured target {target} bytes. The last column is the fraction of input bytes in chunks strictly larger than four times the configured target.',
                                   ['Algorithm', '$n$', '$Q_1$', 'Median', '$Q_3$', 'P99', 'P99.9', 'Max.', 'Byte fraction'],
                                   [[tex(s['algorithm']), str(s['chunk_count'])] + [number(s[f]) for f in ('q1_chunk_size', 'median_chunk_size', 'q3_chunk_size', 'p99_chunk_size', 'p999_chunk_size', 'max_chunk_size', 'byte_fraction_above_4target')] for s in rows]))
            timing_tex.append(table(f'{dataset}: throughput in MiB/s, configured target {target} bytes; $r$ repetitions. IQR is $Q_3-Q_1$.',
                                    ['Algorithm', '$r$', '$Q_1$', 'Median', '$Q_3$', 'IQR'],
                                    [[tex(s['algorithm']), str(s['timing_repetitions'])] + [number(s[f]) for f in ('q1_throughput_mib_s', 'median_throughput_mib_s', 'q3_throughput_mib_s', 'iqr_throughput_mib_s')] for s in rows]))
    overview = []
    lookup = {(s['algorithm'], s['dataset'], s['target_chunk_size']): s for s in summaries}
    for algorithm in ALGORITHMS:
        row = [tex(algorithm)]
        for dataset in ('RAND', 'DB'):
            s = lookup.get((algorithm, dataset, 2048))
            row.extend([number(s['median_throughput_mib_s']), number(s['iqr_throughput_mib_s'])] if s else ['Pending', 'Pending'])
        overview.append(row)
    comparison = table('DB versus RAND at the configured 2048-byte target. Median throughput and IQR in MiB/s; pending cells require author-supplied repetitions.',
                       ['Algorithm', 'RAND median', 'RAND IQR', 'DB median', 'DB IQR'], overview, wide=False)
    coverage = table('Author-input coverage: validated settings / eight expected algorithms. Every setting requires chunks, timings, and provenance.',
                     ['Dataset'] + [str(t) + ' B' for t in TARGETS],
                     [[d] + [str(sum(s['dataset'] == d and s['target_chunk_size'] == t for s in summaries)) + '/8' for t in TARGETS] for d in DATASETS], wide=False)
    return {'extended-chunks.tex': '\n'.join(chunk_tex), 'extended-timings.tex': '\n'.join(timing_tex),
            'extended-db-rand.tex': comparison, 'extended-coverage.tex': coverage}


def write_csv(path, rows, fields):
    with path.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def export(manifest_path, output, allow_missing=False):
    manifest_raw, summaries, timings, missing, comparisons, raw_files = analyze(manifest_path, allow_missing)
    require(not output.exists() or not any(output.iterdir()), 'output directory must be empty (preserve prior exports)')
    output.mkdir(parents=True, exist_ok=True)
    (output / 'raw').mkdir()
    (output / 'raw' / 'original-manifest.json').write_bytes(manifest_raw)
    # Raw chunks remain in place: duplicating a complete grid can require terabytes.
    # Snapshot small timing inputs and retain content hashes/paths for every source.
    for name, raw in raw_files.items():
        if name.endswith('.timings.csv'):
            shutil.copyfile(raw, output / 'raw' / name)
    for name, rows in [('summary.csv', summaries), ('timing-repetitions.csv', timings), ('db-rand-comparison.csv', comparisons), ('missing-settings.csv', missing)]:
        empty_fields = {
            'summary.csv': ['algorithm', 'dataset', 'target_chunk_size', 'dataset_size', 'run_id',
                            'dataset_fingerprint', 'chunk_population', 'timing_measure', 'environment_id',
                            'source_revision', 'parameters_json', 'chunk_count', 'mean_chunk_size',
                            'sd_chunk_size', 'q1_chunk_size', 'median_chunk_size', 'q3_chunk_size',
                            'p99_chunk_size', 'p999_chunk_size', 'max_chunk_size', 'byte_fraction_above_4target',
                            'timing_repetitions', 'median_throughput_mib_s', 'q1_throughput_mib_s',
                            'q3_throughput_mib_s', 'iqr_throughput_mib_s'],
            'timing-repetitions.csv': ['algorithm', 'dataset', 'target_chunk_size', 'run_id',
                                       'dataset_fingerprint', 'repetition', 'elapsed_seconds',
                                       'processed_bytes', 'throughput_mib_s'],
            'db-rand-comparison.csv': ['algorithm', 'target_chunk_size', 'rand_run_id', 'db_run_id',
                                       'db_vs_rand_percent_change'],
            'missing-settings.csv': ['algorithm', 'dataset', 'target_chunk_size'],
        }
        write_csv(output / name, rows, empty_fields[name])
    for name, content in render_tables(summaries, missing).items():
        (output / name).write_text(content.rstrip() + '\n')
    provenance = dict(status='RESULTS PENDING / AUTHOR INPUT REQUIRED' if missing else 'complete',
                      expected_settings=len(GRID), validated_settings=len(summaries), missing_settings=missing,
                      chunk_quantile_convention='inverse ECDF / nearest rank: x[ceil(n*p)-1]',
                      timing_quantile_convention='median averages central pair for even n; Q1/Q3 use R type 7 linear interpolation',
                      sd_convention='sample (n-1); null/blank for n=1', chunk_population='all-emitted',
                      target_convention='configured target, including MII',
                      byte_fraction='sum(size for size > 4*configured_target) / sum(all emitted sizes)',
                      manifest_sha256=hashlib.sha256(manifest_raw).hexdigest(),
                      analysis_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                      raw_files={name: dict(source_path=str(path), sha256=file_sha256(path)) for name, path in raw_files.items()},
                      summary=summaries, db_rand_comparisons=comparisons)
    (output / 'provenance.json').write_text(json.dumps(provenance, indent=2, allow_nan=False) + '\n')
    return provenance


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--allow-missing', action='store_true', help='explicit review export with missing-setting placeholders')
    args = parser.parse_args()
    try:
        provenance = export(args.manifest, args.output, args.allow_missing)
    except (ValueError, OSError, TypeError, KeyError, OverflowError, csv.Error) as error:
        parser.exit(2, f'error: {error}\n')
    print(f"{provenance['status']}: {provenance['validated_settings']}/{provenance['expected_settings']} settings")


if __name__ == '__main__':
    main()
