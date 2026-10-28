# arwad 0.0.0.9015

* New `aw_pls_ci()`: bias-corrected percentile confidence intervals, the
  intervals the PLS-SEM Primer asks for, for every coefficient of a
  bootstrapped model (paths, total and total indirect effects, loadings,
  weights, HTMT) and for specific indirect effects, from `aw_boot_pls()` or
  `seminr::bootstrap_model()`. With `type = "percentile"` the limits are
  seminr's `summary()` limits, bit for bit; the bias correction is
  `boot::boot.ci()`'s with zero acceleration. Each table adds the bias and
  the skewness of the bootstrap values. Unlike seminr's `summary()`, the
  total indirect effects follow `alpha` too.
* Fixed: with `cores` above 1 on Windows, `aw_boot_pls()`'s worker processes
  ran the engine in GNU R (same results, about 9 times slower) when Goose
  was set only by `options(arwad.goose = )`. Workers now receive every
  `arwad` option and the Goose executable this session uses. The published
  benchmarks set Goose by environment variable and were not affected.

# arwad 0.0.0.9014

* `aw_boot_pls()` runs models with formative constructs
  (`composite(..., weights = mode_B)`) as native code, including the Primer's
  extended corporate reputation model; results are bit-identical to seminr
  (HTMT within four units in the last place, see below). Only `reflective()`
  (PLSc) models, other weighting schemes, interactions, higher-order
  constructs and missing data still go to seminr.
* `cov(X)` and `cor(X)` of one matrix compile, matched to GNU R bit for bit
  (R's `cor(X)` rounds differently from `cor(X, X)`).
* Correction: HTMT agrees with seminr to within four units in the last
  place, not two as stated since 0.0.0.9010. Measured over 1,000 resamples:
  the ECSI model has values up to 3 units apart, the Primer's extended
  corporate reputation model one value 4 units apart; about three in four
  values are identical. The test now checks the distance in units.

# arwad 0.0.0.9013

* `cov(m[, j], k[, i])` and `cor(m[, j], k[, i])` of matrix columns read the
  columns in place and keep each column's mean (and standard deviation) until
  the matrix is written again, so repeated calls skip repeated work; values
  stay R's, bit for bit. The PLS-SEM engine uses it: 1,000 resamples of the
  ECSI model in 2.06 s instead of 2.86 s on the benchmark laptop, results
  unchanged.
* The PLS-SEM kernel builds each regression's transposed design once.

# arwad 0.0.0.9012

* `aw_boot_pls()` is 1.8 times faster (loadings and HTMT from one covariance
  and one correlation matrix, compiled matrix forms of `cov()` and `cor()`),
  and `cores =` runs resamples in parallel processes with identical results.

# arwad 0.0.0.9011

* `m[, j] <- v` and `m[i, ] <- v` compile. A function or signature that runs
  in GNU R instead of native code now says so once, with the reason
  (`options(arwad.quiet = TRUE)` turns this off).

# arwad 0.0.0.9010

* Third Phase 2 engine: `aw_boot_pls()`, a compiled drop-in for
  `seminr::bootstrap_model()` (Mode A composites, path weighting scheme).
  Path coefficients, total effects, loadings and weights are bit-identical to
  seminr on 54 models; HTMT agrees to within two units in the last place.
* `colMeans()`, `cov()` and `cor()` compile, matched to GNU R bit for bit; on
  64-bit ARM, `cov()` and `cor()` call R's own routine.

# arwad 0.0.0.9009

* Second Phase 2 engine: `aw_glm_fit()` and `aw_boot_glm()`, iteratively
  reweighted least squares for binomial (logit), Poisson (log) and Gaussian
  (identity) models, compiled. Coefficients, deviance and iteration counts
  are bit-identical to `glm.fit()` on 55 designs for each family; every fit
  for which `glm.fit()` warns or errors is handed to `glm.fit()`, so warnings
  are R's too. Re-implemented from R's documentation and black-box tests.
* `fit <- .lm.fit(x, y, tol)` compiles, with `fit$coefficients`,
  `$residuals`, `$rank` and `$pivot`; rank-deficient designs now run
  natively, pivoted exactly as R pivots them.
* `drop()` compiles; so does `x[i] <- v` with an index vector and a value
  vector (zero indices dropped, value recycled, as in R).
* Fix: `x ^ 2` is computed as `x * x`, as R's arithmetic does; R's C
  function `R_pow()` can round squares differently on 64-bit Windows.
* Fix: `sqrt()` is always the processor's correctly rounded square root
  (units are built with `-fno-math-errno`); GCC could otherwise call the C
  library's `sqrt()`, which on Windows rounds some results differently.
* Fix: the portable build path (R CMD SHLIB) works on macOS again; R's
  `R_ext/Applic.h` is no longer included.

# arwad 0.0.0.9008

* First Phase 2 engine: `aw_boot_ols()`, a compiled case-resampling
  bootstrap of OLS coefficients, bit-identical to R running the same
  bootstrap; 43.7x faster than an `lm()` loop and 1.9x faster than an
  `.lm.fit()` loop on one laptop (bench/phase2/REPORT.md).
* `.lm.fit(x, y)$coefficients` and `$residuals` compile, through R's own
  LINPACK `dqrls`; validated bit for bit on 55 designs.
* `stats` added to Imports.

# arwad 0.0.0.9007

* Corpus grown to 201 functions (Phase 1 target: 200): `slice4.R` and
  `slice5.R` add statistics, estimators, numerical methods, finance and
  time series, linear algebra (IRLS logistic regression, Jacobi, LU), rank
  statistics, integer algorithms and simulation (bootstrap, permutation
  tests, Gibbs, Metropolis). All run natively and match GNU R bit for bit.

# arwad 0.0.0.9006

* `sample()` and `sample.int()` with and without replacement, drawing
  indices through R's own `R_unif_index()`; bootstrap resampling such as
  `mean(x[sample.int(n, replace = TRUE)])` now compiles and reproduces R's
  stream. Corpus: 92 functions.

# arwad 0.0.0.9005

* Compiler slice 3, random numbers: `runif()` and `rnorm()` draw from GNU
  R's own generators through its C API, between `GetRNGstate()` and
  `PutRNGstate()`, so values and the final `.Random.seed` are identical to
  R's. A call that bails out restores `.Random.seed` before R re-runs it.
* `floor()` and `ceiling()`.
* Corpus: 86 functions; seeded entries compare the generator state too.

# arwad 0.0.0.9004

* Compiler slice 2b, part 2: `%*%`, `crossprod()` and `solve()` through R's
  own BLAS (`dgemv`, `dgemm`, `dsyrk`) and LAPACK (`dgesv`, `dgecon`), so
  OLS as `solve(crossprod(X), crossprod(X, y))` compiles and matches R bit
  for bit. Units now link `$(LAPACK_LIBS) $(BLAS_LIBS)`.
* Compiled `+` and `*` select the result NaN in C as each platform's
  hardware does for R's operand order (arm64 favours signalling NaNs); the
  earlier `x + 0.0` quieting was optimised away by clang.
* Corpus: 79 functions.

# arwad 0.0.0.9003

* Compiler slice 2b, part 1, matrices: matrix arguments and locals,
  `matrix()`, `m[i, j]` read and write, rows and columns, `t()`, `nrow()`,
  `ncol()`, `dim()`, and elementwise arithmetic that keeps dimensions.
  Results are returned with their `dim` attribute.
* `mean()` now follows GNU R's algorithm, including its fallback to the sum
  of `x[i] / n` when the plain sum is not finite (found by CI on macOS
  arm64, where `long double` is `double`).
* Compiled `+` and `*` return a quieted `NA` or `NaN`, as R's arithmetic
  does; arm64 hardware otherwise favours R's signalling `NA_real_`.
* Corpus: 72 functions.

# arwad 0.0.0.9002

* Compiler slice 2a, vectors: vectorised arithmetic, comparison, logic and
  math with R's recycling; `c()`, `mean()`, `min()`, `max()`; `a:b`,
  `seq_len()`, `seq_along()` as values; index vectors and logical masks for
  reading and for assigning a single value. Corpus: 59 functions, all native
  and bit-identical to GNU R.

# arwad 0.0.0.9001

* First compiler slice (Phase 1): `aw_compile()` for double, integer and
  logical scalars and vectors, `if`/`for`/`while`/`repeat`, indexing and
  sub-assignment, and `length`, `numeric`, `integer`, `logical`, `sum`, `abs`,
  `sqrt`, `exp`, `log`, `is.na`.
* Guarded native execution: cases the native code does not model re-run the
  call in GNU R, so values, errors and warnings are R's (ADR-0005).
* `aw_explain()`, `aw_source()`, `aw_toolchain()`, `aw_cache_clear()`.
* Equivalence corpus of 39 functions, all native and bit-identical to GNU R.
* Compiled `+` and `*` keep the first operand's `NA` or `NaN`, as GNU R does,
  whatever operand order the C compiler picks (found by CI on Linux).
* Direct build path: R's compile and link commands are read once from a dry
  run of `R CMD SHLIB` and the Goose runtime is compiled once per toolchain,
  so a new signature builds in about 1 s instead of 4-5 s.
  `options(arwad.build = "shlib")` keeps the old path, which is also the
  fallback.
* Dispatch: the native unit of the previous call checks the argument types
  in C, cutting the per-call cost from about 33 us to 4.5 us.
