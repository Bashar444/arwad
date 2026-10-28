# ADR-0006: PLS-SEM engine matched to seminr by black-box tests

- **Status:** Accepted
- **Date:** 2026-10-27

## Context

The third Phase 2 engine is the PLS-SEM path algorithm with its bootstrap, the method behind most PLS-SEM studies in management research and the first engine planned for the PalmyraDoor research portal. The reference implementation in R is `seminr` (Ray, Danks and Calero Valdez; GPL-3). Researchers report `seminr` results, so the engine has to give the same numbers, not merely close ones. `seminr` is GPL-3 and Arwad is MIT, so the clean-room rule of [ADR-0003](0003-mit-licence-dco-clean-room.md) applies to it as it does to GNU R.

## Decision

1. **Algorithm from the literature, rounding from black-box tests.** The kernel `aw_pls_kernel()` (in `r/R/engines.R`, written in the compilable subset) implements the PLS path algorithm as published (Wold, 1982; Lohmöller, 1989; Hair, Hult, Ringle and Sarstedt, *A Primer on PLS-SEM*, 4th ed.): Mode A outer weights, the path weighting inner scheme, standardised indicators, convergence on the sum of absolute weight changes. Where the literature leaves a numerical choice open, the choice was settled by comparing `seminr` 2.5.0's outputs with candidate formulas on many inputs, including `seminr`'s exported and internal functions called as black boxes on our own inputs:
   - indicators and scores are standardised as `scale()` does (mean by `colMeans()`, divisor `sqrt(sum(x^2)/(n - 1))`); each iteration standardises the scores and the inner proxies;
   - weights are normalised by the uncentred root mean square of their scores, `sqrt(sum(y^2)/(n - 1))` (300 of 300 random inputs identical);
   - the iteration count reported is the number of updates minus one; `maxIt` allows `maxIt + 1` updates;
   - loadings are `cov(Z, Y)` on the final, unrescaled scores; R² is `1 - 1 / solve(S)[k + 1, k + 1]` for the correlation matrix `S` of (antecedents, construct);
   - bootstrap resample `b` is `sample.int(n, replace = TRUE)` after `set.seed(seed + b)`, which is why `seminr`'s results do not depend on the number of cores; without a seed, `seminr` draws one with `sample.int(100000, 1)`;
   - HTMT uses absolute correlations.
2. **Three compiled builtins** were added for the kernel, each matched to GNU R by black-box tests: `colMeans()`, and `cov()` and `cor()` of two vectors (the corrected two-pass mean of Chan, Golub and LeVeque, 1983; extended-precision deviations and sums; a correlation's standard deviations are rounded from an extended-precision square root). On 64-bit ARM, R's own results depend on how its C compiler vectorises and fuses the summation loops (a CI diagnostic on macOS showed that no fixed C formula reproduces them reliably), so there the compiled `cov()` and `cor()` call the routine R itself calls, `.Call(stats:::C_cov, ...)`, and are R's by construction.
3. **Native, and checked to be native.** `aw_compile()` falls back to GNU R without an error when a function leaves the subset; the first draft of the kernel did (it assigned whole matrix columns), so the first benchmark timed interpreted R. The kernel now assigns elements, and the tests assert that the engine's unit is compiled and that no call bailed out (`aw_explain()`).
4. **Scope of the native path:** Mode A (composite or reflective), path weighting, complete numeric data, no interaction terms or higher-order constructs. Anything else is passed to `seminr::bootstrap_model()` itself, and the result says so (`native = FALSE`).
5. **What is claimed.** Bit-identical to `seminr`: outer weights, loadings, path coefficients, iteration count and final weight change of the estimate; the bootstrap arrays of path coefficients, total effects, loadings and weights and their descriptive tables. Not bit-identical: HTMT, which agrees to within two units in the last place (relative difference below 4.5e-16); the exact summation order `seminr` uses for it was not found by black-box search, and this is stated wherever the engine is described.

## Clean-room record

`seminr` stores its inner-weighting function in every fitted model, so printing a model object during the first probe displayed the body of `path_weighting()`; printing `seminr::mode_A` to see whether it was a constant displayed its one-line body. Both state textbook definitions (regression coefficients on antecedents and correlations with successors; Mode A weights as covariances with the inner proxy). No other `seminr` source was read; every other numerical detail above was established from outputs only. No `seminr` code is copied, translated or paraphrased in this repository.

## Consequences

- `aw_boot_pls(model, nboot, seed)` is a drop-in replacement for `seminr::bootstrap_model()` that returns a `boot_seminr_model` object, so `summary()` and `seminr`'s plots work on it.
- `seminr` becomes a suggested package; the tests compare against it on 54 models (8 on `seminr`'s own datasets, 46 seeded synthetic ones) on Linux, macOS and Windows.
- Mode B, the factorial and centroid schemes, PLSc, interaction terms and higher-order constructs are the next candidates for the native path.

## Amendment (28 October 2026): speed

Profiling by switching parts off showed half of each resample in correlations computed pair by pair for HTMT and in the cross-loadings (needed only for seminr's signed zeros), each call recomputing column means. The kernel now computes the loadings with one `cov(Z, Y)` and HTMT with one `cor(Xb, Xb)`, compiled matrix forms that compute each column's mean and standard deviation once: 5.15 to 2.85 ms per resample of the ECSI model, results unchanged. `aw_boot_pls(cores = )` runs blocks of resamples in separate processes (forked on Linux and macOS, a socket cluster on Windows) rather than threads, because on 64-bit ARM the compiled `cov()` and `cor()` call into R, which is not thread-safe; the resample indices are drawn before the split, so results do not depend on the number of cores. Headline speed ratios against seminr use its fastest run, because its time varied from 212 to 655 s for the same 10,000 resamples on the benchmark laptop.

## Amendment (28 October 2026, later): column statistics kept by the compiler

A second profile (each part of the kernel replaced by a stand-in, 11 fixed iterations against one) put 80% of a resample in the iterations: per iteration 0.11 ms in the Mode A covariances `cov(Z[, k], Yt[, j])`, 0.09 ms in the inner regressions and 0.07 ms in the inner correlations `cor(Y[, i], Y[, j])`. Each of those calls copied two columns and recomputed both means (and standard deviations), although the indicators `Z` do not change during the iterations. Rather than rewrite the kernel around this, the compiler now keeps, for every matrix whose columns a function passes to `cov()` or `cor()` as `m[, j]`, each column's mean and standard deviation with an epoch that every write to the matrix advances; the columns are read in place ([spec](../../spec/subset-v0.md)). The arithmetic is the same as before, so results are unchanged bit for bit (the 54-model comparison with `seminr` and a new test that writes to the matrices between calls). The kernel also builds each regression's transposed design once. 1,000 resamples of the ECSI model: 2.86 s before, 2.06 s after, on the benchmark laptop; the benchmark report has the full table.
