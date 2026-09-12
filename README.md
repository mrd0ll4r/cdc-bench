# CDCBench

Rust Binary to Benchmark Various CDC Algorithms.

Accompanying code repository to the paper **"A Thorough Investigation of Content-Defined Chunking Algorithms for Data Deduplication"**.
Please cite our work if you use this code or binary:
```bibtex
@misc{gregoriadis2024thorough,
      title={A Thorough Investigation of Content-Defined Chunking Algorithms for Data Deduplication}, 
      author={Marcel Gregoriadis and Leonhard Balduf and Björn Scheuermann and Johan Pouwelse},
      year={2024},
      eprint={2409.06066},
      archivePrefix={arXiv},
      primaryClass={cs.DC},
      url={https://arxiv.org/abs/2409.06066}, 
}
```

#### Structure

This repo consists of multiple parts:
- The code, build instructions, and documentation about the `cdc-algorithm-tester` binary which is used to evaluate CDC algorithms.
    That's **this README file**.
- Scripts to replicate the experiments from the paper, in the [scripts/](scripts) directory.
- Evaluation code in R to produce the figures, tables, and numbers from the paper, in the [plotting/](plotting) directory.
- The accompanying website to our paper (**TODO LINK**), in the [website/](website) directory.

# CDC Algorithm Tester Binary

```
A program that invokes a selectable chunking algorithm with given configuration on a provided file.

Usage: cdc-algorithm-tester [OPTIONS] --input-file <FILE> <COMMAND>

Commands:
  nop      Chunks the input using a no-op chunker, which produces one huge chunk
  fsc      Chunks the input file using a fixed-size chunker (FSC)
  rabin    Chunks the input file using Rabin
  ae       Chunks the input file using AE
  ram      Chunks the input file using RAM
  seq      Chunks the input file using SeqCDC
  bfbc     Subcommands relating to BFBC chunking
  mii      Chunks the input file using MII
  pci      Chunks the input file using PCI
  gear     Chunks the input file using Gear
  nc-gear  Chunks the input file using Gear with normalized chunking modifications
  gear64   Chunks the input file using 64-bit Gear
  adler32  Chunks the input file using 32-bit Adler
  buzhash  Chunks the input file using Buzhash
  help     Print this message or the help of the given subcommand(s)

Options:
  -q, --quiet
          Whether to only perform chunking, not fingerprinting

  -i, --input-file <FILE>
          The file to operate on

      --max-chunk-size <BYTES>
          A max chunk size to optionally enforce

      --quickcdc-min-chunk-size <BYTES>
          Enable the QuickCDC wrapper around the selected algorithm using the given minimum chunk size.

          Note that the minimum chunk size will be skipped and not processed by the inner CDC algorithm. From the perspective of the inner algorithm, chunks are `min_chunk_size` smaller than they actually are. You need to adjust the parameters of the inner algorithm accordingly.

          Setting this to zero will enable only the caching functionality of the QuickCDC wrapper, and not skip any bytes for unique chunks.

          Chunks that are smaller than the sum of both feature vector lengths (e.g., 3+3=6 by default) will not be cached.

      --quickcdc-front-feature-vector-length <BYTES>
          The number of bytes to use for the front feature vector of the QuickCDC wrapper.

          Only implemented for 1,2,3, or 4 bytes. Note that a large value may cause large consumptions of memory.

          [default: 3]

      --quickcdc-end-feature-vector-length <BYTES>
          The number of bytes to use for the end feature vector of the QuickCDC wrapper.

          Only implemented for 1,2,3, or 4 bytes. Note that a large value may cause large consumptions of memory.

          [default: 3]

      --quickcdc-use-hashmap
          Use the hashmap-based implementation of the QuickCDC wrapper

      --hash-value-output-file <HASH_VALUE_OUTPUT_FILE>
          Output file to write intermediary hash values to. This will write the rolling hash before it is discriminated to the output file, one value per line. Note that this only prints values to be discriminated, which will generally skip the window size of input bytes.

          Only implemented for Adler, Buzhash, Gear64, and Rabin.

  -h, --help
          Print help (see a summary with '-h')

  -V, --version
          Print version
```

## Usage

Specify an input file with `-i <FILE>`, then run one of the subcommands on it, to chunk it using the specified algorithm.
The output is a list of chunks as `<digest>,<size in bytes>`, like:

```
6264013dd6158754a260e8ef56f866502d0cd5c3,586
e1fb30e629e75152a72e6d1e55eae3a8ca5683c6,1248
75b4613cea811551651bb70cf6764c8e553b580d,1947
53c98786b2bc574c87bd4fc3131c4ae90448185d,924
385b9cf93889b6890711ee06513dbbd362695cfd,713
8da320a0bcd286028b773ec9a0265ac7f03eb310,590
...
```

It is trivial to validate that the blocks add up to the original file:

```bash
$ cdc-algorithm-tester <invocation> | awk -F',' '{print $2}' | paste -sd+ | bc
<sum of all chunk sizes>
```

The various algorithms have different parameters to configure.
Use `help <command>` to get a list for each of them, for example:

```bash
$ cdc-algorithm-tester help ae
Chunks the input file using AE

Usage: cdc-algorithm-tester --input-file <FILE> ae <TARGET_CHUNK_SIZE>

Arguments:
  <TARGET_CHUNK_SIZE>  The target chunk size

Options:
  -h, --help     Print help
  -V, --version  Print version
```

## Building

MSRV: `nightly`, because we use `#![feature(generic_const_exprs)]`.
See the tracking issue for that [here](https://github.com/rust-lang/rust/issues/76560).

The current `release` profile specifies thin link-time optimization (`lto="thin"`) and `codegen-units=1`. The Docker builder uses `nightly-2026-06-01`, while `rust-toolchain.toml` and the host command below select a moving nightly. These current settings do not establish the compiler version used for the published measurements; see [reproducibility and the historical run checklist](REPRODUCIBILITY.md).
This will take a while to build, but should produce fast code.
Furthermore, binaries used for testing are produced with `RUSTFLAGS="-C target-cpu=native"`.

Preferably and most easily: build id docker using the [build-in-docker.sh](./build-in-docker.sh) script.
The binary will be placed in `out/`.
The same can be achieved using
```bash
make build
```
which also sets up correct permissions for the `scripts/` directory, in case they get lost in transit.

Alternatively, on a host with an up-to-date __nightly__ Rust installed:
```bash
RUSTFLAGS="-C target-cpu=native" cargo +nightly build --release --locked
```

This will produce a binary in `target/release/`

If performance is not a consideration, build without `--release`.
This will build much faster and enable some assertions used to check correctness of the algorithms.
The binary will be placed in `target/debug/` in this case.

## Implemented Algorithms

We implement various state-of-the-art rolling has functions our fork of the `cdchunking-rs` crate [here](https://github.com/mrd0ll4r/cdchunking-rs).
These are original implementations derived from their respective publications:

- Fixed-size chunking (FSC)
- Gearhash (Gear)
- Gearhash with normalized chunking (NC-Gear).
- Asymmetric Extremum (AE)
- Rapid Asymmetric Extremum (RAM), with optional optimizations made to the implementation
- Byte Frequency-Based Chunking (BFBC), including functionality to derive byte frequencies from an input file.
  We extend the invocation of this algorithm with functionality to specify the indices to use, including skipping most-frequent byte pairs.
  Our implementation stores the list of most-frequent byte pairs as a bitmap of 8KiB on the stack, which makes it run
  in constant time regardless of the number of byte pairs.
- Minimal Incremental Interval (MII)
- Parity Check of Interval (PCI), implemented in a way that calculates a running popcount, instead of re-calculating the popcount of the window for each byte.

Additionally, we adapt a range of pre-existing rolling hash functions to interoperate with our testing framework.
These implementations are not original, but rather translated from other languages, or existing implementations in Rust.
They are contained in this repository (see [src/](src)).
Currently, we include:

- Rabin fingerprinting, following popular implementations in [C](https://github.com/fd0/rabin-cdc), [Rust](https://github.com/rustic-rs/rustic/tree/main/src/cdc) (adapted from [Rust](https://github.com/green-coder/cdc)), [C++](https://github.com/lemire/rollinghashcpp).
  This uses some optimizations in pre-computing two tables of constants.
- 64-bit Gear (Gear64), with optional SIMD implementation.
  This uses the [gearhash](https://crates.io/crates/gearhash) crate, licensed MIT.
  In contrast to the algorithm described in the DDelta paper, this version uses a 64-bit internal hash (and 64-bit table entries).
  This implementation is SIMD-accelerated on CPUs supporting SSE4.2 or AVX2.
- 64-bit Gear (Gear64) without manual vectorization.
  This is an implementation of Gearhash using 64-bit state and table entries.
  We use the same table as the `gearhash` crate.
- Adler32, using the [adler32 crate](https://crates.io/crates/adler32).
  This is a port of the [original implementation in zlib](https://github.com/madler/zlib/blob/2fa463bacfff79181df1a5270fb67cc679a53e71/adler32.c).
  The original zlib license applies, and is included in [src/adler.rs](src/adler.rs).
- Buzhash, adapted from an implementation in the [bitar crate](https://crates.io/crates/bitar), licensed MIT.
- A no-op chunker (NOP) that produces one huge chunk.

### QuickCDC

QuickCDC is implemented as a generic caching and jumping wrapper around any inner CDC algorithm.
To replicate the configuration presented in the paper, use the normalized-chunking Gearhash implementation as the inner algorithm.

The cache stores 32-bit unsigned integers as chunk sizes to skip.
This limits chunk sizes to `2^32`, which is probably fine in practice, while saving a considerable amount of memory.

There are two implementations:

1. Using `HashMap<[u8;N], u32>`s for the front and end indices.
   These start out small and get filled gradually.
   Benchmarking has shown that this can be slow in some cases, especially when producing many small chunks, which leads to frequent accesses of the hashmap.
2. Using preallocated arrays of `[u32; 256.pow(N)]`.
   This is faster, at least for cases where the cache is accessed frequently.
   The arrays are heap-allocated, and the downside of preallocating them completely is their size:
   For `N=3`, as suggested in the paper, the tables are `256^3 * 4 (bytes per entry) = 64M` _per table_.
   As such, for `N=M=3`, the tables (which are frequently accessed) potentially evict up to 128M of cache, which is probably all of it.
   A choice of `N=M=2` reduces the combined size of the tables to 512K, which is much more manageable.
   This, of course, comes at the expense of more frequent collisions.
   A possible performance optimization here would be to limit chunk sizes to `2^16=64K`, which would reduce the size of the tables by half.
   This might not be acceptable in all situations.

## Performance Considerations

We use the [cdchunking](https://crates.io/crates/cdchunking) crate as a framework to implement and use chunking algorithms.
Specifically, we iterate over the file in buffered blocks, which avoids frequent `read()` operations and does not allocate.
The CDC algorithms are fed these blocks and update their internal state accordingly.
They produce cut-point indices.

On a higher level, we iterate over the file using _the same_ buffered blocks, re-sliced according to the chunk boundaries produced by the chosen algorithm.
This allows us to then compute fingerprints and collect metadata about chunks without allocating.
On an even higher level, it is then possible to load the file into a RAMDisk before chunking, to isolate from disk performance.

The algorithms are, whenever applicable, implemented as described or shown in the respective publications.
It was sometimes necessary to modify the implementations for correctness, which we have always done.
In some cases we have taken the liberty of implementing obvious performance improvements, which can be enabled with respective flags.

In general, we chose to operate on a single file, which in practice means that we concatenate all files in our datasets and chunk the resulting dataset file.
Keep in mind that there is considerable overhead implied with launching a process, which could affect results when chunking many (small) files.

By default, we produce SHA1 fingerprints for the chunks.
The `--quiet` flag can be provided to skip the computation of the fingerprint and omit output to std, to isolate the performance of the CDC algorithms.
We use [std::hints::black_box](https://doc.rust-lang.org/std/hint/fn.black_box.html) to ensure that the compiler still assumes chunk data to be used in either case.

We use compile-time constants whenever applicable with reasonable effort.
In particular, we use constants for:

- the feature vector sizes of QuickCDC
- the size of the window for Rabin, Buzhash, Adler32, and PCI. These are implemented using stack-allocated arrays.

## License

MIT, see [LICENSE](LICENSE).
