# Phase 1, compiler slice 1: `aw_compile()` against GNU R

**Date:** 26 October 2026 · **Status:** preliminary, single laptop (the Phase 0 machine) · **Raw data:** [`slice1_timing.csv`](slice1_timing.csv) · **Script:** [`slice1_bench.R`](slice1_bench.R)

## Summary

For six functions written in ordinary R, `arwad::aw_compile()` produced native code whose results are **bit-identical** to GNU R's (`identical(..., num.eq = FALSE)`), with no call handed back to R. Against R's own byte-compiled closures, the compiled loops ran **20 to 40 times faster**; a loop dominated by `exp()` ran **2.9 times** faster; and a single call of a tiny function ran **11 times slower**, because each call pays about 34 µs of R-level dispatch. The first call for each argument signature builds a native library, which took **3.8 to 5.3 s**.

## 1. What was measured

Each function was run as `compiler::cmpfun(f)` (R's byte code, which R's JIT applies to loops anyway, so this is the fair baseline) and as `aw_compile(f)` after its first call. Times are medians from `bench::mark()` (at least 5 iterations, at most 2,000), garbage collections included.

| Case | Work | Identical to R | Native, no bailout | First call (s) | R median (ms) | arwad median (ms) | Speed-up |
|---|---|---|---|---|---|---|---|
| `sum_sq` | `s + x[i]^2` over 10^6 doubles | yes | yes | 4.16 | 175.4 | 7.148 | **24.5×** |
| `cumsum_loop` | running sum into `out[i]`, 10^6 | yes | yes | 5.28 | 142.6 | 6.692 | **21.3×** |
| `prime_count` | trial division up to 200,000 (integer `%%`, `while`, `break`) | yes | yes | 4.77 | 2,103 | 103.9 | **20.2×** |
| `nested_loops` | `s + 1 / (i * j)`, 2,001,000 iterations | yes | yes | 4.10 | 114.2 | 2.850 | **40.1×** |
| `trapezoid` | trapezoid rule for `exp(-x^2)`, 10^6 points | yes | yes | 3.83 | 213.3 | 72.74 | **2.9×** |
| `clamp_one_call` | one call of a three-way `if` on scalars | yes | yes | 4.25 | 0.0033 | 0.0371 | **0.09×** (11× slower) |

Memory allocated by R per call (`bench::mark`): 0 B for R's byte code and 2.86 KB for arwad in the scalar cases (the argument list and the result); 7.63 MB for both in `cumsum_loop` (the result vector).

## 2. Environment

Intel Core i7-7600U (2 cores, 4 threads), Windows 11 x64 (build 26100); R 4.6.0 (ucrt); Goose v2026.3 (runtime 4d3da949e563); Rtools45 GCC 14.3.0 through `R CMD SHLIB` with R's flags (`-O2 -mfpmath=sse -msse2 -mstackrealign`) plus `-ffp-contract=off`.

## 3. Interpretation

1. **Where R interprets every iteration, compiled code wins by an order of magnitude.** Even byte-compiled, R dispatches each `+`, `[` and `^` through its evaluator and boxes intermediate values; the generated Goose does none of this. This is the class of code Arwad targets (loops, simulations, custom estimators).
2. **Where the work is inside a library function, the gain shrinks.** In `trapezoid` most of the time is spent in the C library's `exp()`, which both sides call; only the loop around it gets faster. The same will hold for code that is already vectorised in R, which slice 1 does not compile.
3. **Small functions called once are slower.** The dispatcher is written in R: it reads the argument types, finds the native unit and unpacks the result, about 34 µs per call. Compiling `clamp` on its own is therefore a loss. Moving the dispatch into C is planned.
4. **The first call is expensive.** Building one signature takes 4–5 s, most of it in `R CMD SHLIB` process overhead and in compiling the 160 KB Goose runtime that every unit carries (Goose itself takes 0.08 s; GCC on the generated code alone, 0.25 s). The cache removes the cost for later calls and sessions; a direct compiler call with the runtime compiled once, and TinyCC for interactive use, are planned (ROADMAP 1.4).
5. **Equivalence held without exceptions.** Besides these six cases, the 38-function corpus in [`r/inst/corpus/slice1.R`](../../r/inst/corpus/slice1.R) runs natively and bit-identically, with inputs that include `NA`, `NaN`, `±Inf`, `-0` and empty vectors; `R CMD check` passes with the corpus compiled.

## 4. Not yet measured

- Linux and macOS (the CI workflow runs the corpus there; timings will follow).
- Other machines and compilers (clang, MSVC); TinyCC.
- Whole-process peak memory.
- Functions with matrices and vectorised arithmetic, which slice 1 does not compile.

## 5. Reproduce

```bash
R CMD INSTALL r
ARWAD_GOOSE=/path/to/goose Rscript bench/phase1/slice1_bench.R
```
