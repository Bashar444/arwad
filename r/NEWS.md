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
