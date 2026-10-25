# Phase 0 spike report: OLS and case bootstrap, GNU R vs hand-written Goose

**Date:** 24 October 2026 (updated the same day with an optimising back end and the R binding) · **Status:** preliminary, single laptop · **Verdict:** proceed.

*Measured under the project's working title, R-Goose (commit `da6cdb4`). The files and symbols were renamed for Arwad afterwards without changing the code; a re-run of the renamed build reproduced the same agreement with R (3.74e-15 single fit, 2.8e-15 bootstrap SDs).*

## Summary

| Result | Value |
|---|---|
| Agreement with GNU R | within 8.5e-15 (standalone) and 3.7e-15 (single fit called from R); bootstrap SDs within 2.8e-15 |
| 10,000-replicate bootstrap, called from R through `.Call` (gcc -O2) | **2.50 s vs 3.98 s for R's fastest loop (`.lm.fit`): 1.59× faster** |
| Memory R allocates per 100 replicates | **0.4 MB with Goose vs 18.4 MB with the R loop** |
| 10,000,000-step scalar loop | **≈ 20× faster than R** |
| Same bootstrap with the non-optimising TinyCC back end | 2.9× slower than R (§4): the optimising back end matters |

## 1. What was tested

OLS on a fixed design (n = 1,000 rows, k = 10 coefficients including the intercept) and a nonparametric case bootstrap with B = 10,000 replicates.

- **R reference** ([`phase0_reference.R`](phase0_reference.R)): `lm.fit` and `.lm.fit` (LINPACK Householder QR, compiled Fortran) inside an R loop.
- **Goose kernel** ([`ols_bootstrap.goose`](ols_bootstrap.goose)): Householder QR written by hand in Goose; per-replicate scratch arrays declared inside the loop body, so each replicate's memory is released when its iteration ends.
- **Identical inputs:** both read [`data.csv`](data.csv), written once with 17 significant digits, and both draw resampling indices from the same Park–Miller LCG. The index checksum is **5,003,108,173** in both, so the replicates are identical.

## 2. Environment

| Item | Value |
|---|---|
| CPU | Intel Core i7-7600U, 2 cores / 4 threads, 2.8 GHz (laptop) |
| RAM / OS | 15.9 GB / Windows 11 Pro (build 26100) |
| R | 4.6.0, internal reference BLAS |
| Goose | v2026.3 (runtime 4d3da949e563), `goose run` with the bundled **TinyCC** back end, inlining levels -O1 and -O2 |
| Optimising C compiler | none at first (§4 uses TinyCC); then **GCC 14.3.0 from Rtools45** (§4b, §4c) |

## 3. Numerical equivalence (gate: relative error ≤ 1e-9)

| Quantity | Max absolute error | Max relative error | Pass |
|---|---:|---:|:---:|
| OLS coefficients | 1.11e-15 | 8.46e-15 | ✅ |
| Bootstrap means | 3.77e-15 | 7.26e-15 | ✅ |
| Bootstrap standard deviations | 1.01e-16 | 3.25e-15 | ✅ |

Produced by [`compare.R`](compare.R). The Goose results agree with GNU R to about 15 significant digits.

## 4. Timing (three runs per contender; medians in bold)

| Workload | Contender | Runs (s) | Median (s) | Relative to R |
|---|---|---|---:|---|
| 10,000,000-step scalar loop (index generation) | GNU R | 5.58, 7.06, 5.48 | **5.58** | 1× |
| | Goose, TinyCC (-O1 and -O2 pooled) | 0.29, 0.35, 0.41, 0.43, 0.32, 0.31 | **0.34** | **≈ 17× faster** |
| 10,000 bootstrap refits (QR) | R loop + `lm.fit` | 4.44, 5.06, 4.06 | **4.44** | — |
| | R loop + `.lm.fit` | 3.66, 3.40, 4.02 | **3.66** | 1× |
| | Goose, TinyCC -O2 | 12.37, 10.69, 10.58 | **10.69** | **≈ 2.9× slower** |
| | Goose, TinyCC -O1 | 12.28, 11.13, 14.71 | 12.28 | ≈ 3.4× slower |

Run-to-run spread is large on this laptop (overheating has been recorded on this machine before), so medians are reported.

### 4b. Optimising back end (added after installing Rtools45, GCC 14.3.0)

`goose build -O2 --cc gcc` builds the same program with GCC at `-O2`.

| Workload | Runs (s) | Median (s) | Relative to R |
|---|---|---:|---|
| Scalar loop (index generation) | 0.277, 0.264, 0.279 | **0.28** | ≈ 20× faster than R (5.58 s) |
| 10,000 bootstrap refits | 3.39, 2.99, 3.21 | **3.21** | 1.14× faster than R's `.lm.fit` loop (3.66 s) |

Outputs: `goose_gccO2_run1..3.txt`.

### 4c. Called from R (Phase 0.4)

The kernels in [`poc/arwad_kernels.goose`](../../poc/arwad_kernels.goose) are exported with `export fn`, compiled with `goose -O2 --standalone --header`, and linked into an R-loadable DLL by `R CMD SHLIB` through a small C bridge ([`poc/shim.c`](../../poc/shim.c)). R's matrices are passed to Goose as slices pointing at R's own memory; the result matrix is allocated by R and filled in by Goose. The bridge validates every index before the call, so bad input raises an R error instead of crashing R. Script: [`poc/run_poc.R`](../../poc/run_poc.R).

| Contender (B = 10,000, n = 1,000, k = 10) | Runs (s) | Median (s) | Speed-up vs `.lm.fit` loop |
|---|---|---:|---:|
| R loop + `lm.fit` | 4.59, 3.97, 4.18 | 4.18 | 0.95× |
| R loop + `.lm.fit` | 3.57, 3.98, 4.16 | 3.98 | 1.00× |
| **Goose via one `.Call`** | 2.56, 2.50, 2.34 | **2.50** | **1.59×** |

| Check | Result |
|---|---|
| Single fit vs `lm.fit` | max relative error 3.74e-15 |
| Bootstrap coefficients vs the `lm.fit` loop | max relative error 5.78e-11 (the largest values come from coefficients near zero; absolute errors are at rounding level) |
| Bootstrap standard deviations | max relative error 2.80e-15 |
| R memory allocated per 100 replicates (`bench::mark`) | Goose 402.9 KB (almost all of it the test harness's `idx[, 1:100]` copy) vs `.lm.fit` loop 18.4 MB |

## 5. Interpretation

1. **Feasibility for correctness is established.** A statistical kernel written in Goose reproduces GNU R to about 1e-14, with identical resampling streams.
2. **Where R's interpreter dominates, Goose wins clearly.** The scalar loop ran about 17 times faster even with TinyCC, which does not optimise. This is the class of code R users write themselves (loops, simulations, custom estimators) and the primary target of Arwad.
3. **Where R already calls compiled Fortran, TinyCC-compiled Goose loses.** `.lm.fit` spends its time inside LINPACK compiled with an optimising compiler. A hand-written QR compiled by TinyCC is about three times slower. This is a comparison of C compilers, not of memory models.
4. **Strategy adjustment:** do not compete with Fortran on dense floating-point work. Call BLAS/LAPACK from Goose through `extern fn` for factorisations (as [ARCHITECTURE.md](../../docs/ARCHITECTURE.md) §4.5 already plans), and target the overheads R adds around them: per-iteration interpretation, allocation and copying (`X[ii, ]` allocates about 80 KB per replicate in R), and parallel execution through Goose's share-nothing workers.

5. **Confirmed after §4b–4c:** with an optimising compiler, the same hand-written kernel beats R's best loop, and called from R it is 1.59× faster while allocating about 46 times less memory in R. Both sides perform the same QR arithmetic, so the gain is R's per-replicate interpretation, allocation and copying, which is exactly the overhead Arwad is designed to remove.

## 6. Not yet measured

- Parallel resampling with Goose worker threads (this laptop has 2 cores / 4 threads).
- Factorisations through BLAS/LAPACK called from Goose, and faster bootstrap formulations (for example frequency-weighted cross-products instead of gathering rows).
- Whole-process peak memory with a proper harness (Windows `PeakWorkingSet64`, Linux `/usr/bin/time -v`).
- Other machines, and a Linux CI run.

## 7. Reproduce

```bash
Rscript bench/phase0/phase0_reference.R 10000
goose run -O2 bench/phase0/ols_bootstrap.goose -- bench/phase0/data.csv 10000 > bench/phase0/goose_O2_run1.txt
Rscript bench/phase0/compare.R bench/phase0/goose_O2_run1.txt
goose build -O2 --cc gcc bench/phase0/ols_bootstrap.goose -o bench/phase0/ols_bootstrap.exe
bash poc/build.sh && Rscript poc/run_poc.R 10000 3
```
