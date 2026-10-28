# ADR-0007: Bias-corrected percentile confidence intervals for PLS-SEM

**Status:** Accepted, 28 October 2026 · **Function:** `aw_pls_ci()` in [`r/R/ci.R`](../../r/R/ci.R) · **Tests:** [`r/tests/testthat/test-ci.R`](../../r/tests/testthat/test-ci.R)

## Context

PLS-SEM results are judged by bootstrap confidence intervals. The PLS-SEM Primer (Hair, Hult, Ringle and Sarstedt, 4th ed., pp. 164–166) recommends the percentile method and reporting its **bias-corrected** intervals, keeping the bias-corrected and accelerated (BCa) interval for strongly skewed bootstrap distributions; the project lead's PLS-SEM protocol makes this binding for every coefficient, including indirect effects (10,000 resamples, a fixed seed, bias-corrected percentile 95% intervals). `seminr`'s `summary()` gives percentile intervals only. Black-box tests of `seminr` 2.5.0 showed that its limits are `quantile(type = 7)` of the bootstrap values at `alpha / 2` and `1 - alpha / 2`, that `specific_effect_significance()` multiplies the path coefficients along a chain from left to right, and that `summary()` reports the total indirect effects at 95% whatever `alpha` is.

## Decision

1. **Method.** The bias-corrected percentile interval (Efron, 1982; Efron and Tibshirani, 1993, §14.3, with zero acceleration; Davison and Hinkley, 1997, §5.3): with `z0 = qnorm(share of resamples strictly below the estimate)`, the limits are the bootstrap quantiles at `pnorm(2 * z0 + qnorm(alpha / 2))` and `pnorm(2 * z0 + qnorm(1 - alpha / 2))`. This is the `z0` of `boot::boot.ci(type = "bca")` (ties are not counted as below), and with zero acceleration the same levels up to rounding in the last bits: `boot`'s own interpolation applied to these levels reproduces `boot.ci()`'s limits to 1e-12 in the tests.
2. **Quantile convention: `seminr`'s.** The limits are `quantile(type = 7)` at those levels, so `type = "percentile"` gives `summary()`'s limits bit for bit, and the bias-corrected interval reduces to them exactly when half the resamples lie below the estimate (the levels are then left untouched rather than passed through `pnorm(qnorm())`). `boot` interpolates between order statistics on the normal scale instead; the two conventions bracket the same order statistics and differ by a fraction of the gap between neighbouring resamples (up to about 1e-3 in a limit at 1,000 resamples in the tests, less at 10,000). Consistency with the percentile intervals researchers already report from `seminr` was preferred.
3. **What is reported.** One table per kind of coefficient, rows as in `summary()`: estimate, bootstrap mean, bias (mean minus estimate, as SmartPLS reports it), bootstrap standard deviation, `summary()`'s t statistic, the skewness of the bootstrap values (`m3 / m2^1.5`, so that the Primer's rule of BCa beyond ±2 can be applied), and the two limits, labelled `% BC CI`. Specific indirect effects are added on request as chains of constructs.
4. **Every table uses `alpha`**, total indirect effects included.
5. **Edge cases.** Bootstrap values that differ only by rounding (the loading and weight of a single-indicator construct, 1 give or take the last bits) carry no sampling information and get their percentile limits and no skewness. When the estimate lies outside its bootstrap values, `z0` is infinite and the limits are the extreme resamples (as in `boot`), with a warning naming the coefficients.
6. **Plain R.** A bootstrap of 10,000 resamples of the seven-construct ECSI model gives 119 rows of intervals in about 3 s; compiling this step would not change what users wait for.

## Validation

- `type = "percentile"` equals `summary()` on all 80 models of the PLS-SEM test set at 95% and at 90% (estimate, mean, standard deviation, t statistic and limits, bit for bit; total indirect effects at 95%, where `summary()` ignores `alpha`).
- Specific indirect effects equal `specific_effect_significance()` for chains of two and three paths.
- The bias-corrected levels agree with `boot::boot.ci(type = "bca")` with zero acceleration (supplied as empirical influence values whose third moment is zero), as described in item 1.
- The tables are the same for a bootstrap from `seminr::bootstrap_model()` and from `aw_boot_pls()` with the same seed (HTMT rows to 1e-12, see ADR-0006).

## Clean-room record

`seminr`'s `summary()` and `specific_effect_significance()` and `boot`'s `boot.ci()` and internal `norm.inter()` were called as black boxes on our own inputs; their source was not read. The formulas come from the cited books.

## Consequences

- `aw_pls_ci(boot)` turns any `seminr` or Arwad bootstrap into the intervals the Primer asks for, in one call.
- Not done: BCa intervals (the acceleration needs a jackknife, one re-estimation per case, a natural job for the compiled kernel) and studentized intervals.
