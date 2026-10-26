# Roadmap

Durations are estimates for a solo project lead working with AI agent teams ([AGENT_TEAM.md](AGENT_TEAM.md)). They will be re-estimated once Phase 0 produces real measurements.

## Phase 0: Foundations (2–4 weeks)

| # | Task | Output | Status (24 Oct 2026) |
|---|---|---|---|
| 0.1 | Install Goose v2026.3 (Windows x64 locally, Linux x64 in CI); compile and run the bundled samples; record versions | `bench/phase0/REPORT.md` §2 | ✅ Windows, TinyCC back end |
| 0.2 | Hand-write a Goose OLS kernel: Householder QR without pivoting for full-rank designs | `bench/phase0/ols_bootstrap.goose` | ✅ spike |
| 0.3 | Hand-write a nonparametric case bootstrap: B = 10,000, n = 1,000, k = 10, with resampling indices identical to R's | `bench/phase0/ols_bootstrap.goose` | ✅ spike (shared LCG; R's own RNG in Phase 1) |
| 0.4 | Bind both to R through a minimal C shim and `.Call`; confirm inputs are read without copying | [`poc/`](../poc/) | ✅ 1.59× faster than R's best loop; 46× less R memory |
| 0.5 | Equivalence harness; report maximum absolute and relative error | `bench/phase0/compare.R`, `poc/run_poc.R` | ✅ max relative error 8.5e-15 |
| 0.6 | Benchmark harness ([BENCHMARK_METHOD.md](BENCHMARK_METHOD.md)): wall time and peak memory, including an optimising back end | `bench/phase0/` | ◐ TinyCC and GCC -O2 timed; R-side memory measured; parallel and whole-process memory pending |
| 0.7 | Report with raw data, whatever the result | [`bench/phase0/REPORT.md`](../bench/phase0/REPORT.md) | ✅ preliminary |

**Exit:** the report exists; equivalence is within 1e-9 relative error; a decision memo says *proceed*, *adjust* or *change back end*. **Met (24 Oct 2026):** the report's verdict is *proceed*, with the strategy adjustment in its §5 (call BLAS/LAPACK for dense work; target R's per-iteration overheads). Still open from 0.6: parallel workers and whole-process memory, now tracked under Phase 3 and Phase 1 respectively.

## Phase 1: Compiler vertical slice (2–4 months)

| # | Task | Status (26 Oct 2026) |
|---|---|---|
| 1.1 | `arwad` R package skeleton ([`r/`](../r/)) that passes `R CMD check` on Windows, Linux and macOS | ✅ Status OK on Linux, macOS (arm64) and Windows in CI, with Goose installed and the corpus compiled ([`.github/workflows/r-check.yml`](../.github/workflows/r-check.yml)) |
| 1.2 | Front end, type inference and Goose emitter; content-hash cache | ◐ slice 1: scalars and vectors, one type per variable, guarded native execution ([ADR-0005](adr/0005-guarded-native-execution.md)); typed IR and memory planner pending |
| 1.3 | `aw_compile(f)` for [spec/subset-v0.md](../spec/subset-v0.md), with fallback and a recorded reason | ◐ slice 1 of the subset (see the status column in the spec) |
| 1.4 | Build paths: an optimising C compiler through `R CMD SHLIB` (fallback); a direct-compiler path with the Goose runtime compiled once; dispatch checked in C; TinyCC for interactive use | ◐ direct path and C-side dispatch done: first call about 1 s per signature (was 3.8–5.3 s), 4.5 µs per call (was 33 µs); loops 11–33× faster than R's byte code ([bench/phase1/REPORT.md](../bench/phase1/REPORT.md)); TinyCC pending |
| 1.5 | Bit-exact R random-number generation in the static tier (Mersenne-Twister, inversion normals, rejection `sample()`) | planned |
| 1.6 | Test corpus of 200 functions (hand-written, agent-generated, and mined from CRAN where licences allow), each with an equivalence test | ◐ 59 functions ([`r/inst/corpus/`](../r/inst/corpus/)), all native and bit-identical to GNU R |
| 1.7 | Slice 2: vectorised arithmetic with recycling, `mean`/`min`/`max`, `c()`, masks and index vectors (2a); matrices and `m[i, j]`, `%*%`, `t`, `crossprod`, `solve` through LAPACK (2b) | ◐ 2a done (26 Oct 2026); 2b next |

**Exit:** every corpus function either compiles or falls back correctly; all compiled functions match GNU R within 1e-9; no memory errors under AddressSanitizer.

## Phase 2: Statistical engines (4–8 months)

Each engine is validated against its reference package on 50 datasets.

| Engine | Reference |
|---|---|
| OLS, WLS, GLM (IRLS) | `stats::lm`, `stats::glm` |
| PLS-SEM path algorithm with 10,000-replicate bootstrap and bias-corrected percentile intervals | `seminr` |
| DEA (CCR and BCC; input and output orientation) | `Benchmarking` |
| Panel fixed and random effects; Hausman test | `plm` |
| ARIMA likelihood; GARCH(1,1) family | `stats::arima`, `rugarch` |
| Meta-analysis: fixed effect and random effects (REML) | `metafor` |

Data frames enter the static tier as column sets of known types.

**Exit:** every engine passes equivalence; benchmark report published internally; preprint drafted.

## Phase 3: Parallel and WebAssembly (2–4 months)

- Share-nothing parallel resampling through Goose worker programs.
- WebAssembly build of the static tier (Goose → C → wasm) and a browser demo: load a CSV and run a 5,000-replicate bootstrap locally.
- Methods paper submitted (*Journal of Statistical Software* or *The R Journal*).
- First public release, subject to the project lead's decision in [ADR-0003](adr/0003-mit-licence-dco-clean-room.md).

**Exit:** demo live; paper submitted; v0.1.0 tagged with a Zenodo DOI.

## Phase 4: Standalone runtime (12–24 months)

- ADR choosing the implementation language of the dynamic tier.
- Evaluator for full R semantics; base and recommended packages; package loader; R C-API layer prioritised by the symbol census ([COMPATIBILITY.md](COMPATIBILITY.md)).
- Nightly CRAN dashboard.

**Exit:** at least 50% of CRAN packages pass natively (L1 + L2).

## Phase 5: Full ecosystem (24 months and beyond)

- S4 and `methods` completeness, Rcpp coverage, graphics devices, Fortran toolchain integration, tcltk, and the long tail.

**Exit:** at least 95%, then 99%, of CRAN passes natively, and Arwad runs without GNU R installed.

## Decided now, decided later

| Decided now | Decided later (by ADR) |
|---|---|
| Two-tier architecture ([ADR-0001](adr/0001-two-tier-runtime.md)) | Implementation language of the dynamic tier (start of Phase 4) |
| Goose as the first native back end ([ADR-0002](adr/0002-goose-native-backend.md)) | |
| MIT, DCO, clean room, no patent, the name Arwad ([ADR-0003](adr/0003-mit-licence-dco-clean-room.md)) | |
| Numerical-equivalence gate ([ADR-0004](adr/0004-numerical-equivalence-gate.md)) | |
| Guarded native execution with GNU R as the fallback ([ADR-0005](adr/0005-guarded-native-execution.md)) | |
