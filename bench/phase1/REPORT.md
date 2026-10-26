# Phase 1, compiler slice 1: `aw_compile()` against GNU R

**Date:** 26 October 2026 · **Status:** preliminary, single laptop (the Phase 0 machine) · **Raw data:** [`slice1_timing.csv`](slice1_timing.csv) · **Script:** [`slice1_bench.R`](slice1_bench.R)

## Summary

For six functions written in ordinary R, `arwad::aw_compile()` produced native code whose results are **bit-identical** to GNU R's (`identical(..., num.eq = FALSE)`), with no call handed back to R. Against R's own byte-compiled closures, the compiled loops ran **11 to 33 times faster** in the latest run (11 to 40 times across three runs); a loop dominated by `exp()` ran **2.4 times** faster; and a single call of a tiny function took **2.2 times** as long as in R, because each call pays about 4.5 µs of dispatch. The first call for each argument signature builds a native library in **about 1 s**, after a one-off setup of 8 s per machine.

## 1. What was measured

Each function was run as `compiler::cmpfun(f)` (R's byte code, which R's JIT applies to loops anyway, so this is the fair baseline) and as `aw_compile(f)` after its first call. Times are medians from `bench::mark()` (at least 5 iterations, at most 2,000), garbage collections included. The table is the latest run, of the code as committed ([`slice1_timing.csv`](slice1_timing.csv)): direct build path and C-side signature check (§1b).

| Case | Work | Identical to R | Native, no bailout | First call (s) | R median (ms) | arwad median (ms) | Speed-up |
|---|---|---|---|---|---|---|---|
| `sum_sq` | `s + x[i]^2` over 10^6 doubles | yes | yes | 1.03 | 51.13 | 4.698 | **10.9×** |
| `cumsum_loop` | running sum into `out[i]`, 10^6 | yes | yes | 1.01 | 94.65 | 8.488 | **11.2×** |
| `prime_count` | trial division up to 200,000 (integer `%%`, `while`, `break`) | yes | yes | 1.08 | 1,791 | 93.68 | **19.1×** |
| `nested_loops` | `s + 1 / (i * j)`, 2,001,000 iterations | yes | yes | 1.04 | 92.63 | 2.837 | **32.7×** |
| `trapezoid` | trapezoid rule for `exp(-x^2)`, 10^6 points | yes | yes | 1.08 | 174.4 | 73.13 | **2.4×** |
| `clamp_one_call` | one call of a three-way `if` on scalars | yes | yes | 1.00 | 0.0039 | 0.0084 | **0.46×** (2.2× slower) |

Memory allocated by R per call (`bench::mark`): 0 B for R's byte code and 2.86 KB for arwad in the scalar cases (the argument list and the result); 7.63 MB for both in `cumsum_loop` (the result vector).

**Run-to-run variation.** Two earlier runs on the same laptop (before the changes in §1b, which do not touch the generated loops) gave speed-ups of 24.5×, 21.3×, 20.2×, 40.1×, 2.9× and then 13.7×, 16.2×, 23.6×, 35.4×, 2.6× for the five loop cases. The R baseline moved by up to a factor of three between runs (`sum_sq`: 175, 58 and 51 ms) while the compiled times moved by less (7.1, 4.2 and 4.7 ms), so these figures show the order of magnitude, not precise ratios; a controlled multi-machine benchmark is still to come.

## 1b. Build path and dispatch (26 October 2026, later the same day)

The first version built each unit with `R CMD SHLIB` and a standalone Goose unit that carries the whole 160 KB runtime: 3.8–5.3 s per signature, of which Goose took 0.08 s and GCC on the runtime 2.2 s, the rest being `R CMD SHLIB`'s process overhead. The current version learns R's exact compile and link commands once from a dry run of `R CMD SHLIB` (cached on disk), compiles the Goose runtime once per toolchain, and then builds each unit with one compile and one link call; `R CMD SHLIB` remains the fallback.

| | Before | Now |
|---|---|---|
| First call per signature | 3.8–5.3 s | 1.00–1.08 s |
| One-off setup per machine (fresh cache) | none | 8.3 s |
| Test suite (about 50 units) | 7 min 18 s | 1 min 36 s |
| Dispatch cost per call (`clamp_one_call`, arwad minus R) | about 33 µs | about 4.5 µs |

The dispatch now calls the native unit of the previous call first; its C shim checks the argument types and attributes itself and returns a mismatch code when they do not fit, and only then does R work out the signature. A same-session A/B with garbage collections filtered out found no cost of the separate runtime object in the generated loops: `sum_sq` 3.82 ms standalone against 3.89 ms direct, `cumsum_loop` 5.74 against 5.49 ms.

## 2. Environment

Intel Core i7-7600U (2 cores, 4 threads), Windows 11 x64 (build 26100); R 4.6.0 (ucrt); Goose v2026.3 (runtime 4d3da949e563); Rtools45 GCC 14.3.0 with R's own compile flags (`-O2 -mfpmath=sse -msse2 -mstackrealign`, read from `R CMD SHLIB`) plus `-ffp-contract=off`.

## 3. Interpretation

1. **Where R interprets every iteration, compiled code wins by an order of magnitude.** Even byte-compiled, R dispatches each `+`, `[` and `^` through its evaluator and boxes intermediate values; the generated Goose does none of this. This is the class of code Arwad targets (loops, simulations, custom estimators).
2. **Where the work is inside a library function, the gain shrinks.** In `trapezoid` most of the time is spent in the C library's `exp()`, which both sides call; only the loop around it gets faster. The same will hold for code that is already vectorised in R, which slice 1 does not compile.
3. **Small functions called once are slower.** Each call still passes through R (building the argument list, `.Call`, unpacking the result), about 4.5 µs, so compiling a function as small as `clamp` on its own does not pay. It pays once the function does a few microseconds of work per call.
4. **The first call costs about a second.** That is one Goose run, one compile and one link (§1b); the on-disk cache removes it for later calls and sessions. TinyCC for interactive use remains planned (ROADMAP 1.4).
5. **Equivalence needed one correction.** The first CI run found one difference on Linux: in `s + x[i]^2`, when the running sum was `NA` and the new term `NaN`, the compiled code returned `NaN` and R `NA`. GCC had swapped the operands of the commutative `+`, and IEEE arithmetic returns the NaN of whichever operand comes first. R's `?NA` states that this outcome is platform-dependent; in practice R keeps the first operand's on all three CI platforms, so compiled `+` and `*` now do so explicitly ([spec/subset-v0.md](../../spec/subset-v0.md), implementation status). The corpus, now 39 functions in [`r/inst/corpus/slice1.R`](../../r/inst/corpus/slice1.R) with inputs that include `NA`, `NaN`, `±Inf`, `-0` and empty vectors, runs natively and bit-identically; `R CMD check` passes with the corpus compiled.

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
