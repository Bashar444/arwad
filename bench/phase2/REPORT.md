# Phase 2, first engine: `aw_boot_ols()`, a compiled bootstrap of OLS coefficients

**Date:** 27 October 2026 · **Status:** preliminary, single laptop (the Phase 0 machine) · **Raw data:** [`ols_boot_timing.csv`](ols_boot_timing.csv) · **Script:** [`ols_boot_bench.R`](ols_boot_bench.R)

## Summary

`arwad::aw_boot_ols()` runs a case-resampling bootstrap of least-squares coefficients as native code. Each replicate draws rows with R's own `sample.int()` stream and fits them with R's own LINPACK QR (`dqrls`, the routine behind `.lm.fit()` and `lm()`), so the result is **bit-identical** to R running the same bootstrap with the same seed. For 2,000 replicates of a 200 by 5 design it took **60.5 ms**: **43.7 times faster** than the `lm()` loop most researchers write, and **1.9 times faster** than the fastest hand-optimised R loop.

## 1. What was measured

Design: n = 200 rows, k = 5 columns (intercept and four standard-normal predictors), B = 2,000 replicates. Every contender starts from `set.seed(1)`; times are medians of `bench::mark()` (3 to 10 iterations), garbage collections included. R code is byte-compiled (`compiler::cmpfun`).

| Contender | What it is | Median (ms) | `aw_boot_ols()` is |
|---|---|---|---|
| `aw_boot_ols()` | the compiled engine | 60.5 | — |
| `.lm.fit` loop | `.lm.fit(X[idx, , drop = FALSE], y[idx])$coefficients` per replicate: the fastest idiomatic R | 115.5 | 1.9× faster |
| same algorithm in R | the engine's own kernel run by GNU R | 449.9 | 7.4× faster |
| `lm()` loop | `coef(lm(y ~ ., data = d[idx, ]))` per replicate: what most users write | 2,645.0 | 43.7× faster |

Equivalence: the engine's 2,000 by 5 coefficient matrix is identical (`identical(..., num.eq = FALSE)`) to both the same algorithm in R and the `.lm.fit` loop. The first call, in a fresh cache, took 7.0 s (one-off setup plus building the unit); later calls and sessions reuse the native unit.

## 2. Validation (Phase 2 rule: at least 50 datasets)

[`r/tests/testthat/test-engines.R`](../../r/tests/testthat/test-engines.R), run in CI on Linux, macOS and Windows:

- `.lm.fit(X, y)$coefficients` and `$residuals` compiled are bit-identical to R's on 55 designs: 30 numeric data frames of R's `datasets` package (response = first numeric column, design = intercept plus the other numeric columns) and 25 seeded synthetic designs (n from 15 to 1,000, k from 2 to 6, predictor scales from 0.1 to 100).
- `aw_boot_ols()` equals the same bootstrap run in R, bit for bit, on 50 of those designs.
- A rank-deficient design is handed to GNU R, which pivots, so the result is still R's.

## 3. Interpretation

1. **Against the code researchers actually write, the gain is large.** Most of the 2.6 s of the `lm()` loop is spent building model frames and formula machinery for every replicate; the engine does only the arithmetic.
2. **Against the best hand-tuned R, the gain is modest but real.** The `.lm.fit` loop already spends its time in the same Fortran; the engine saves R's per-replicate allocation and copying of `X[idx, ]`.
3. **Same answers, by construction.** Because the engine calls R's own random-number stream and R's own QR, there is no "Arwad answer" to explain to a reviewer: it is R's answer, sooner.

## 4. Environment and next steps

Intel Core i7-7600U, Windows 11, R 4.6.0, Goose v2026.3, Rtools45 GCC 14.3. Next engines (ROADMAP Phase 2): GLM by IRLS against `glm()`, then the PLS-SEM path algorithm with bootstrap against `seminr`.
