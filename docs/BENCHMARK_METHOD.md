# Benchmark method

A performance number is published only together with the method below and its raw data.

## 1. Environment, always reported

CPU model, core count, RAM, operating system; R version and BLAS (reference, OpenBLAS or MKL) with its thread count; C compiler and flags; Goose version and back end (TinyCC or clang/MSVC).

## 2. Measurements

| Quantity | Tool |
|---|---|
| Wall time of whole programs | `hyperfine`, at least 3 warm-up runs and 10 measured runs |
| Peak memory | Linux: `/usr/bin/time -v` (maximum resident set size); Windows: process `PeakWorkingSet64` |
| In-R timings and allocations | `bench::mark`, which also records memory allocated by R |
| Compile time | Reported separately from run time; never hidden inside a "warm" figure |

## 3. Baselines

1. Plain R as users write it (byte-compiled by R's default JIT).
2. The best available R implementation: vectorised code, `data.table`, or Rcpp/RcppArmadillo where a well-known implementation exists.
3. Arwad with the TinyCC back end and with the clang (or MSVC) back end.

## 4. Fairness rules

- Same BLAS and the same number of threads for every contender.
- Identical inputs, and identical resampling indices or seeds.
- No caching of results across runs.
- Numerical equivalence is checked on every benchmarked run; a fast wrong answer is a failure.

## 5. Reporting

- Median and interquartile range per contender; speed-up ratios with bootstrap confidence intervals.
- Cold (first call, including compilation) and warm figures, labelled.
- Raw CSV and the exact scripts are committed next to the report.
- Results are reported whatever they show, including cases where Arwad is slower.
