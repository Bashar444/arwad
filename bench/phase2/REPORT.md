# Phase 2 engines: compiled bootstraps of OLS, GLM and PLS-SEM models

**Date:** 27 October 2026 · **Status:** preliminary, single laptop (the Phase 0 machine) · **Raw data:** [`ols_boot_timing.csv`](ols_boot_timing.csv), [`glm_boot_timing.csv`](glm_boot_timing.csv), [`pls_boot_timing.csv`](pls_boot_timing.csv) · **Scripts:** [`ols_boot_bench.R`](ols_boot_bench.R), [`glm_boot_bench.R`](glm_boot_bench.R), [`pls_boot_bench.R`](pls_boot_bench.R)

## Summary

`arwad::aw_boot_ols()` runs a case-resampling bootstrap of least-squares coefficients as native code. Each replicate draws rows with R's own `sample.int()` stream and fits them with R's own LINPACK QR (`dqrls`, the routine behind `.lm.fit()` and `lm()`), so the result is **bit-identical** to R running the same bootstrap with the same seed. For 2,000 replicates of a 200 by 5 design it took **60.5 ms**: **43.7 times faster** than the `lm()` loop most researchers write, and **1.9 times faster** than the fastest hand-optimised R loop.

`arwad::aw_glm_fit()` and `arwad::aw_boot_glm()` do the same for generalised linear models: iteratively reweighted least squares for binomial (logit), Poisson (log) and Gaussian (identity) models. For 1,000 replicates of a logistic regression on a 200 by 5 design, `aw_boot_glm()` took **382.4 ms**: **10.8 times faster** than a `glm()` loop and **3.25 times faster** than a `glm.fit()` loop, with **identical coefficients** to both.

`arwad::aw_boot_pls()` is a compiled replacement for `seminr::bootstrap_model()`, the reference implementation of the PLS-SEM bootstrap in R. It re-estimates a model on case resamples with the PLS path algorithm (Mode A composites, path weighting scheme) and returns the same `boot_seminr_model` object, so `summary()` works on it unchanged. Path coefficients, total effects, loadings and weights are **bit-identical** to seminr's; HTMT ratios agree to within two units in the last place. For 1,000 resamples of the seven-construct ECSI model it took **4.58 s** on one core: **6.8 times faster** than seminr running on all four logical cores of the laptop and **9.6 times faster** than seminr on one core. For **10,000 resamples**, the number the Primer recommends, it took **41.3 s** against **211.9 s** (**5.1 times faster**).

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

## 3. PLS-SEM bootstrap: what was measured

Design: the European Customer Satisfaction Index model (Tenenhaus et al., 2005) on seminr's `mobi` data: 7 constructs, 24 indicators, 12 paths, n = 250; path weighting scheme, Mode A composites, seminr's defaults (`maxIt` = 300, stop criterion 1e-7); seed 123. Times are medians of `bench::mark()` (3 runs); the 10,000-resample rows are single runs. seminr distributes resamples over a cluster of R processes, one per logical core by default (4 on this laptop); the engine runs in one process on one core.

| Contender | Resamples | Median (ms) | `aw_boot_pls()` is |
|---|---|---|---|
| `aw_boot_pls()` | 1,000 | 4,584 | — |
| `bootstrap_model()`, all cores | 1,000 | 30,990 | 6.76× faster |
| `bootstrap_model(cores = 1)` | 1,000 | 43,890 | 9.57× faster |
| same algorithm in R | 1,000 | 49,080 | 10.71× faster |
| `aw_boot_pls()` | 10,000 | 41,250 | — |
| `bootstrap_model()`, all cores | 10,000 | 211,910 | 5.14× faster |

Equivalence: the arrays of path coefficients, total effects, loadings and weights are identical (`identical(..., num.eq = FALSE)`) to seminr's with all cores and with one core, at 1,000 and at 10,000 resamples. Of the HTMT values, 75.1% are identical and the largest relative difference is 4.4e-16. The first call, in a fresh cache, took 22.7 s (one-off setup, building the engine, and the 1,000 resamples).

Variation: an earlier run of the same script, with the engine not yet compiling (see §6), timed seminr at 23,340 ms on all cores, 46,540 ms on one core and 220,560 ms for 10,000 resamples; against those, the engine is 5.1, 10.2 and 5.3 times faster. Read the speed-up as about 5 to 10 times, not as a precise ratio.

## 4. Validation (Phase 2 rule: at least 50 datasets)

[`r/tests/testthat/test-engines.R`](../../r/tests/testthat/test-engines.R), run in CI on Linux, macOS and Windows. The designs are 30 numeric data frames of R's `datasets` package (response = first numeric column, design = intercept plus the other numeric columns) and 25 seeded synthetic designs (n from 15 to 1,000, k from 2 to 6, predictor scales from 0.1 to 100).

- `.lm.fit()` compiled is bit-identical to R's on all 55 designs. Rank-deficient designs run natively and are pivoted exactly as R pivots them.
- `aw_boot_ols()` equals the same bootstrap run in R, bit for bit, on 50 designs.
- `aw_glm_fit()` equals `glm.fit()` on 55 designs for each family (binomial: the response plus seeded noise, split at the median; Poisson: the response shifted and rounded to counts; Gaussian: as is): the same coefficients, deviance, iteration count and warnings, bit for bit. In the local run, 163 of the 165 fits ran natively; the other two are fits for which `glm.fit()` warns, and they are handed to `glm.fit()` itself.
- `aw_boot_glm()` equals the same `glm.fit()` loop in R on 50 designs, with the same warnings and the same final random-number state. Replicates for which `glm.fit()` warns are refitted by `glm.fit()` from the same resample.
- `colMeans()`, `cov()` and `cor()`, compiled for the PLS-SEM engine, equal R's on 300 random cases per run, including data offset by 1e8.
- PLS-SEM: 54 models: 8 on seminr's own datasets (the ECSI model in four variants, among them `maxIt` = 3,000 as the Primer recommends; the corporate reputation models of the Primer, simple and extended; a second corporate reputation sample; the influencer model) and 46 seeded synthetic models (2 to 7 constructs, 1 to 6 indicators, n from 40 to 800, Likert-type and rescaled data, shuffled construct and path orders). On the 53 models in the native subset, the compiled estimate equals `estimate_pls()`: weights, the full loading matrix (signed zeros included), path coefficients, iteration count and final weight change. `aw_boot_pls()` equals `bootstrap_model()` on all 54: the bootstrap arrays and their descriptive tables bit for bit, HTMT within four units in the last place; the one model with `reflective()` constructs, which seminr estimates by consistent PLS, is handed to seminr, as designed. `summary()` gives identical tables of paths, weights, loadings and total effects, and the caller's random-number state is left as seminr leaves it. The test also checks that every call ran as native code (no fallback to GNU R).

## 5. Interpretation

1. **Against the code researchers actually write, the gain is large.** Most of the time of the `lm()` and `glm()` loops is spent building model frames and formula machinery for every replicate; the engines do only the arithmetic.
2. **Against the best hand-tuned R, the gain is modest but real:** 1.9 times for OLS and 3.25 times for GLM. Those loops already spend much of their time in the same Fortran QR; the engines save R's per-iteration allocation and copying.
3. **Same answers, by construction.** The engines call R's own random-number stream and R's own QR, and the GLM algorithm was matched to `glm.fit()` by black-box tests, so there is no "Arwad answer" to explain to a reviewer: it is R's answer, sooner.
4. **The PLS-SEM engine wins twice:** on arithmetic (one core of compiled code against seminr's R) and on overhead (seminr runs the whole estimation function for every resample and starts a cluster of R processes for every bootstrap). It does so on one core, so a parallel version is the obvious next gain.
5. **The GLM engine has room to grow.** About 0.38 ms per logistic fit is well above what the arithmetic needs; profiling the kernel (allocation per iteration, repeated `exp()` calls) is the next optimisation.

## 6. Found on the way

Matching `glm.fit()` bit for bit exposed two rounding differences in the compiler, fixed for every compiled function: `x ^ 2` is now computed as `x * x`, as R's arithmetic computes it (R's C function `R_pow()` can round squares differently on 64-bit Windows), and `sqrt()` is always the processor's correctly rounded square root (units are built with `-fno-math-errno`; otherwise GCC may call the C library's `sqrt()`, which on Windows rounds some results to the neighbouring double).

Matching seminr bit for bit required numerical details that no paper specifies, all established from seminr's outputs (clean room; [ADR-0006](../../docs/adr/0006-pls-sem-engine.md)): weights are normalised by the uncentred root mean square of their scores, not by the standard deviation; scores and inner proxies are re-standardised at every iteration; resample `b` uses `set.seed(seed + b)`, which is why seminr's results do not depend on the number of cores; HTMT uses absolute correlations and treats a single indicator's within-construct correlation as 1; cross-loadings are covariances multiplied by zero, so a negative covariance leaves a negative zero; and seminr's list of indicators becomes a matrix when every construct has the same number of indicators. Three statistics had to be compiled to R's exact rounding: `colMeans()`, `cov()` and `cor()` (of two vectors and of two matrices; `cor()` of a single matrix rounds differently).

A mistake caught by the benchmark: the first version of the PLS-SEM kernel assigned whole matrix columns, which the compiler does not support yet, and `aw_compile()` then runs a function in GNU R without an error. Its first benchmark therefore timed interpreted R (36.8 s for 1,000 resamples, slower than seminr on four cores) and its first validation run compared interpreted R with seminr. The kernel now assigns element by element, every result above comes from native code, and the tests now fail if the engine's code is not compiled or any call falls back to GNU R.

## 7. Environment and next steps

Intel Core i7-7600U (2 cores, 4 logical), Windows 11, R 4.6.0, seminr 2.5.0, Goose v2026.3, Rtools45 GCC 14.3. Next (ROADMAP Phase 2): Mode B, consistent PLS and interaction terms in the native PLS-SEM path, bias-corrected percentile intervals, and a parallel bootstrap; then the remaining engines (DEA, panel models, ARIMA/GARCH, meta-analysis).
