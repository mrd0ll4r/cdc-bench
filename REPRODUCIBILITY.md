# Reproducibility and run provenance

This document addresses R1.W3b and R1.D5. It separates facts recoverable from the current artifact from missing historical run records. It supplies a reconstruction procedure, not a claim that re-running network downloads or VM workloads yields the same bytes. No new experiments were performed for this documentation change.

## Build and measurement configuration

| Source | Configuration visible in the current artifact |
| --- | --- |
| `Cargo.toml` | Release profile: thin LTO, one code-generation unit. No explicit `opt-level` override. |
| `Dockerfile.builder` | Ubuntu Focal base tag; Rust `nightly-2026-06-01`; final build uses `RUSTFLAGS="-C target-cpu=native"` and `cargo ... build --release --locked`. Package installation and the base tag are not immutable image pins. |
| `rust-toolchain.toml` | Moving `nightly` channel; host builds can use a different compiler than Docker. |
| `scripts/speed.sh` | RAND copied to `fast_data`; one warm-up per algorithm at the first target; ten sequential `perf stat` invocations per target unless `ITER` overrides this; quiet chunking with no fingerprint computation. `DATASETS` does not change this script's RAND-only input. |
| `scripts/utils.sh` | Default targets 512, 1024, 2048, 4096, 8192 B; paths `data`, `fast_data`, and `out/cdc-algorithm-tester`. |

The paper records Intel Xeon Gold 6154 at 3.00 GHz and Debian 12. This identifies the reported platform; it does not establish fixed operating frequency, turbo state, total installed memory, core pinning, or NUMA placement. The timing script does not enforce those settings and does not mount the RAMdisk. `target-cpu=native` depends on CPU features visible during compilation, including inside Docker, so capture both build and run host details.

The script collects task-clock, context switches, page faults, cycles, instructions, branches, branch misses, L1 data-cache loads/misses, and cache references/misses. Preserve the raw CSV and the actual analysis command with each run, rather than substituting current script defaults for historical settings. The paper reports throughput as median/IQR and microarchitectural counters as means.

## DB construction

Sources: `scripts/get-db.sh` and `scripts/db.rc.local`.

1. Download Debian 12 nocloud amd64 image `20250210-2019`. Create a 100 GiB QCOW2 overlay and inject the startup script using `virt-customize`.
2. Boot QEMU with KVM, 4 GiB guest RAM, a QCOW2 drive, and a virtio network device. No explicit vCPU count is supplied; recover the effective historical count from records rather than asserting it.
3. On first boot, install the MySQL 8.0 package series via the MySQL APT configuration package `0.8.29-1`, clone and compile `Percona-Lab/tpcc-mysql`, and load 15 warehouses. The database name `tpcc1000` does not indicate the number of warehouses. Shut down after loading.
4. Copy `root.qcow2` to `1.qcow2`. For each of 24 subsequent boots, execute `tpcc_start` with 15 warehouses, 500 clients, 10 seconds ramp-up, and 1800 seconds run duration, then shut down and copy to the next numbered image, through `25.qcow2`.

These are copies after shutdown, not live crash-consistent snapshots. The script copies QCOW2 containers retaining backing references, then deletes the backing/base image and working overlay. The numbered files therefore do not provide self-contained bootable disks. Record whether the historical benchmark consumed these container bytes or another conversion/export, and record the precise ordering when building the input stream. Do not substitute logical disk capacity (100 GiB) for database size, file size, or changed-byte volume.

The script does not pin the MySQL patch release, package dependencies, or `tpcc-mysql` commit. It does not explicitly set InnoDB page size, log configuration, buffer-pool size, or workload transaction-mix options. Run duration and client count alone cannot recover executed transaction counts or changed bytes. These facts must come from the original records below.

## WEB retrieval

Source: `scripts/get-web.sh`.

The implemented selection is January 2024, one requested URL for each of its 31 calendar days:

```text
https://web.archive.org/web/202401DDid_/https://nytimes.com
```

`wget -E -H -k -p -r -l1 -q --timeout=30 --tries=2` retrieves page requisites and follows links recursively to depth one, permits other hosts, converts links, and adjusts extensions. Requests run concurrently into date-named directories. After all requests finish, each directory is archived with `tar -cf` and removed.

A date selector does not record the exact capture returned. The script tolerates request failures, uses quiet output, and saves no response/capture manifest. Page resources can have different capture times or be unavailable. Archive availability, failed downloads, redirects, wget behavior, and non-normalized TAR metadata can prevent byte-identical reconstruction. The existing script is documented unchanged apart from correcting its misleading date-range comment; adding manifests to future runs would not recover historical provenance.

## Author-input checklist

Replace each `AUTHOR INPUT REQUIRED` field with the value **and its source** (original log, configuration dump, archived manifest, or author confirmation). If unavailable, explicitly state that the historical value is unavailable; do not fill it with a current default. Preserve original logs alongside any new runs. Redact credentials from configuration records.

| Required record | Status |
| --- | --- |
| Original framework/dependency commits and lockfile checksum; binary checksum | AUTHOR INPUT REQUIRED |
| Original `rustc -Vv`, cargo version, effective optimization flags and target features; build host/container image identity | AUTHOR INPUT REQUIRED |
| Benchmark host memory capacity; CPU topology and microcode; kernel and perf versions | AUTHOR INPUT REQUIRED |
| Frequency governor, fixed-frequency/turbo policy, SMT state, CPU affinity, NUMA allocation and placement | AUTHOR INPUT REQUIRED |
| RAMdisk mount options/capacity; free memory, competing load, original commands and overrides | AUTHOR INPUT REQUIRED |
| Raw repetition/counter records, discarded/failed runs, analysis revision, dataset checksums | AUTHOR INPUT REQUIRED |
| DB generator revision; QEMU/libguestfs versions and effective vCPU count | AUTHOR INPUT REQUIRED |
| MySQL exact version, installed package record, `tpcc-mysql` commit and workload options | AUTHOR INPUT REQUIRED |
| InnoDB page size, log configuration, buffer-pool settings, and database size after load | AUTHOR INPUT REQUIRED |
| Per-interval transaction counts and transaction mix; update/churn volume with measurement definition | AUTHOR INPUT REQUIRED |
| DB input representation (QCOW2/raw/export), backing-file handling, stream assembly order and checksums | AUTHOR INPUT REQUIRED |
| WEB retrieval date, wget/tar versions, requested/resolved capture URLs and timestamps | AUTHOR INPUT REQUIRED |
| WEB response/failure/resource manifests, archive and concatenated-stream checksums, assembly order | AUTHOR INPUT REQUIRED |

For future runs, preserve these records before changing the environment, with the exact invocation and checksums for all inputs and outputs. Capturing new records is not a replacement for missing historical records. This checklist does not require executing a benchmark or regenerating datasets to review the accompanying manuscript changes.
