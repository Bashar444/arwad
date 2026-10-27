# Phase 2 engines: compiled bootstraps of OLS and GLM coefficients

**Date:** 27 October 2026 · **Status:** preliminary, single laptop (the Phase 0 machine) · **Raw data:** [`ols_boot_timing.csv`](ols_boot_timing.csv), [`glm_boot_timing.csv`](glm_boot_timing.csv) · **Scripts:** [`ols_boot_bench.R`](ols_boot_bench.R), [`glm_boot_bench.R`](glm_boot_bench.R)

## Summary

`arwad::aw_boot_ols()` runs a case-resampling bootstrap of least-squares coefficients as native code. Each replicate draws rows with R's own `sample.int()` stream and fits them with R's own LINPACK QR (`dqrls`, the routine behind `.lm.fit()` and `lm()`), so the result is **bit-identical** to R running the same bootstrap with the same seed. For 2,000 replicates of a 200 by 5 design it took **60.5 ms**: **43.7 times faster** than the `lm()` loop most researchers write, and **1.9 times faster** than the fastest hand-optimised R loop.

`arwad::aw_glm_fit()` and `arwad::aw_boot_glm()` do the same for generalised linear models: iteratively reweighted least squares for binomial (logit), Poisson (log) and Gaussian (identity) models. For 1,000 replicates of a logistic regression on a 200 by 5 design, `aw_boot_glm()` took **382.4 ms**: **10.8 times faster** than a `glm()` loop and **3.25 times faster** than a `glm.fit()` loop, with **identical coefficients** to both.

## 1. OLS bootstrap: what was measured

Design: n = 200 rows, k = 5 columns (intercept and four standard-normal predictors), B = 2,000 replicates. Every contender starts from `set.seed(1)`; times are medians of `bench::mark()` (3 to 10 iterations), garbage collections included. R code is byte-compiled (`compiler::cmpfun`).

| Contender | What it is | Median (ms) | `aw_boot_ols()` is |
|---|---|---|---|
| `aw_boot_ols()` | the compiled engine | 60.5 | — |
| `.lm.fit` loop | `.lm.fit(X[idx, , drop = FALSE], y[idx])$coefficients` per replicate: the fastest idiomatic R | 115.5 | 1.9× faster |
| same algorithm in R | the engine's own kernel run by GNU R | 449.9 | 7.4× faster |
| `lm()` loop | `coef(lm(y ~ ., data = d[idx, ]))` per replicate: what most users write | 2,645.0 | 43.7× faster |

Equivalence: the engine's 2,000 by 5 coefficient matrix is identical (`identical(..., num.eq = FALSE)`) to both the same algorithm in R and the `.lm.fit` loop. The first call, in a fresh cache, took 7.0 s (one-off setup plus building the unit); later calls and sessions reuse the native unit.

## 2. GLM bootstrap: what was measured

Design: n = 200 rows, k = 5 columns (intercept and four standard-normal predictors), a 0/1 outcome drawn from a logistic model (coefficients −0.3, 0.8, −0.5, 0.4, 0.2), B = 1,000 replicates. Same protocol as §1.

| Contender | What it is | Median (ms) | `aw_boot_glm()` is |
|---|---|---|---|
| `aw_boot_glm()` | the compiled engine | 382.4 | — |
| `glm.fit` loop | `glm.fit(X[idx, , drop = FALSE], y[idx], family = binomial())$coefficients` per replicate: the fastest idiomatic R | 1,241.0 | 3.25× faster |
| `glm()` loop | `coef(glm(y ~ ., data = d[idx, ], family = binomial))` per replicate: what most users write | 4,123.0 | 10.8× faster |
| same algorithm in R | the engine's own kernel run by GNU R | 4,695.0 | 12.3× faster |

Equivalence: the engine's 1,000 by 5 coefficient matrix is identical to all three R contenders; no replicate produced a warning. The first call, in a fresh cache, took 12.9 s.

## 3. Validation (Phase 2 rule: at least 50 datasets)

[`r/tests/testthat/test-engines.R`](../../r/tests/testthat/test-engines.R), run in CI on Linux, macOS and Windows. The designs are 30 numeric data frames of R's `datasets` package (response = first numeric column, design = intercept plus the other numeric columns) and 25 seeded synthetic designs (n from 15 to 1,000, k from 2 to 6, predictor scales from 0.1 to 100).

- `.lm.fit()` compiled is bit-identical to R's on all 55 designs. Rank-deficient designs run natively and are pivoted exactly as R pivots them.
- `aw_boot_ols()` equals the same bootstrap run in R, bit for bit, on 50 designs.
- `aw_glm_fit()` equals `glm.fit()` on 55 designs for each family (binomial: the response plus seeded noise, split at the median; Poisson: the response shifted and rounded to counts; Gaussian: as is): the same coefficients, deviance, iteration count and warnings, bit for bit. In the local run, 163 of the 165 fits ran natively; the other two are fits for which `glm.fit()` warns, and they are handed to `glm.fit()` itself.
- `aw_boot_glm()` equals the same `glm.fit()` loop in R on 50 designs, with the same warnings and the same final random-number state. Replicates for which `glm.fit()` warns are refitted by `glm.fit()` from the same resample.

## 4. Interpretation

1. **Against the code researchers actually write, the gain is large.** Most of the time of the `lm()` and `glm()` loops is spent building model frames and formula machinery for every replicate; the engines do only the arithmetic.
2. **Against the best hand-tuned R, the gain is modest but real:** 1.9 times for OLS and 3.25 times for GLM. Those loops already spend much of their time in the same Fortran QR; the engines save R's per-iteration allocation and copying.
3. **Same answers, by construction.** The engines call R's own random-number stream and R's own QR, and the GLM algorithm was matched to `glm.fit()` by black-box tests, so there is no "Arwad answer" to explain to a reviewer: it is R's answer, sooner.
4. **The GLM engine has room to grow.** About 0.38 ms per logistic fit is well above what the arithmetic needs; profiling the kernel (allocation per iteration, repeated `exp()` calls) is the next optimisation.

## 5. Found on the way

Matching `glm.fit()` bit for bit exposed two rounding differences in the compiler, fixed for every compiled function: `x ^ 2` is now computed as `x * x`, as R's arithmetic computes it (R's C function `R_pow()` can round squares differently on 64-bit Windows), and `sqrt()` is always the processor's correctly rounded square root (units are built with `-fno-math-errno`; otherwise GCC may call the C library's `sqrt()`, which on Windows rounds some results to the neighbouring double).

## 6. Environment and next steps

Intel Core i7-7600U, Windows 11, R 4.6.0, Goose v2026.3, Rtools45 GCC 14.3. Next engine (ROADMAP Phase 2): the PLS-SEM path algorithm with bootstrap, against `seminr`.
