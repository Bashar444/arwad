# Compilable subset, version 0 (Phase 1)

`aw_compile(f)` compiles a function only if every construct it uses is listed here. Otherwise it returns `f` unchanged and records the reason in `attr(result, "arwad_fallback")`.

## Types

- Double, integer and logical vectors.
- Double matrices.
- Scalars (length-one vectors).

## Constructs

- Function definitions with fixed, named arguments (no `...`); default arguments that are constants.
- `if` / `else`; `for` over `seq_len()`, `seq_along()` or an integer range; `while`; `repeat` with `break` and `next`.
- Assignment with `<-` and `=`; local variables only (no `<<-`).
- Indexing and sub-assignment: `x[i]`, `x[i] <- v`, `m[i, j]`, `m[i, j] <- v`, with positive integer or logical indices.
- Arithmetic `+ - * / ^ %% %/%`; comparison `== != < <= > >=`; logical `! & | && ||`.
- Functions: `length`, `nrow`, `ncol`, `numeric`, `integer`, `logical`, `matrix`, `sum`, `mean`, `min`, `max`, `abs`, `sqrt`, `exp`, `log`, `is.na`, `%*%`, `t`, `crossprod`, `solve` (through LAPACK).
- Late Phase 1: `set.seed`-compatible `runif`, `rnorm` and `sample.int`, bit-identical to GNU R.

## Semantics that must match GNU R

- 1-based indexing. A vector read `x[i]` beyond the length returns `NA`; a matrix read `m[i, j]` out of bounds is an error ("subscript out of bounds"); errors use R's condition classes and messages.
- A vector sub-assignment `x[i] <- v` beyond the length extends `x` and fills the gap with `NA`, as in R (planned as grow-only storage).
- `NA` propagation for each type; `NaN` kept distinct from `NA_real_`.
- Integer overflow yields `NA` with R's warning.
- Recycling, including R's warning when lengths are not multiples.
- `/` always returns double; `%%` and `%/%` follow R's definitions for negative operands.
- `1:0` is `c(1L, 0L)`; `for (i in seq_len(0))` runs zero times.
- `sum()` and `mean()` accumulate as R does (in `long double` on x86-64 GCC builds).

## Implementation status: compiler slice 1 (26 October 2026)

Implemented in the `arwad` package ([`r/`](../r/)), verified by the corpus in [`r/inst/corpus/slice1.R`](../r/inst/corpus/slice1.R):

- Types: double, integer and logical scalars and vectors (arguments without attributes, and local vectors from `numeric()`, `integer()`, `logical()`). One type per variable.
- Constructs: everything listed above except matrices; `for` also runs over a vector variable (`for (v in x)`); `x[[i]]` reads; constant defaults.
- Functions: `length`, `numeric`, `integer`, `logical`, `sum` (one argument), `abs`, `sqrt`, `exp`, `log` (one argument), `is.na` (scalars).
- Semantics: all items in the section above, with these handled by re-running the call in GNU R ([ADR-0005](../docs/adr/0005-guarded-native-execution.md)): `NA` conditions, integer overflow, `NaN` from `sqrt()`/`log()`, zero, negative or `NA` indices where R would not return `NA`, fractional or `NA` loop bounds, and `%%`/`%/%` on doubles that are not whole numbers below 2^52.
- `NA` meeting `NaN`: R documents that such a result "will return NaN or perhaps NA" depending on the platform (`?NA`), because compilers may reorder operands. Compiled `+` and `*` keep the first operand's `NA` or `NaN`, which is what GNU R returns on x86-64 (all three CI platforms). On arm64 an unquieted `NA` taken from data takes priority in hardware, so `NaN + NA` gives `NA` in R and `NaN` in compiled code; other operand orders agree.
- Not yet: matrices, `%*%`, `t`, `crossprod`, `solve`, assigning a vector through an index, R's random-number generators. Each falls back with a recorded reason.

### Compiler slice 2a (26 October 2026): vectors

Verified by [`r/inst/corpus/slice2.R`](../r/inst/corpus/slice2.R) (20 functions; 59 with slice 1):

- Vectorised arithmetic, comparison and logic (`+ - * / ^ %% %/%`, `== != < <= > >=`, `! & |`) and `sqrt`, `exp`, `log`, `abs`, `is.na` on vectors, with R's recycling. Lengths that are not multiples of each other (R warns) are left to GNU R.
- `c()`, `mean()`, `min()` and `max()` (of several arguments), and `a:b`, `seq_len()`, `seq_along()` as values.
- Indexing with index vectors (`x[idx]`) and logical masks (`x[x > 0]`), and sub-assignment of a single value through either (`x[x < lo] <- lo`, `x[idx] <- v`).
- Where R needs one value (`if`, `while`, `&&`, `||`, a length, the ends of `a:b`, `[[`), a vector of another length is left to GNU R.
- `mean()` follows GNU R's algorithm: an extended-precision sum divided by n; when that sum is not finite (it may only have overflowed), the sum of the terms `x[i] / n`; then, when finite, a correction by the mean of the residuals. Its `NA` or `NaN` with mixed data therefore follows the hardware, as in R (an `NA` wins on x86-64; the first one wins on arm64). `min()` and `max()` follow `?Extremes` (NA before NaN, the first of equal values such as `0` and `-0`).
- Compiled `+` and `*` choose the result `NA` or `NaN` as the hardware does for R's operand order, whichever order the C compiler picks for these commutative operations: on arm64 a signalling NaN (R stores `NA_real_` as one) takes priority, otherwise the first NaN wins, quieted.

### Compiler slice 2b, part 1 (26 October 2026): matrices

Verified by [`r/inst/corpus/slice2b.R`](../r/inst/corpus/slice2b.R) (12 functions; 72 in all):

- Matrix arguments (double, integer or logical, with a `dim` attribute and no other) and matrix locals; `matrix(data, nrow, ncol)` by column; `nrow()`, `ncol()`, `dim()`, `length()`, `t()`.
- `m[i, j]` read and write, and `m[i, ]` and `m[, j]` read (dropping to vectors, as R's default).
- Elementwise arithmetic, comparison, logic and math on matrices, with a scalar, a vector or a matrix of equal dimensions, keeping the dimensions.
- Left to GNU R: non-conformable operands, subscripts out of bounds or `NA`, data that do not fill a matrix a whole number of times, and matrices with `dimnames` or other attributes.
- Not yet: vector subscripts of matrices, `byrow`, `tcrossprod`, `diag`.

### Compiler slice 2b, part 2 (26 October 2026): products and `solve()`

Verified by the second half of [`r/inst/corpus/slice2b.R`](../r/inst/corpus/slice2b.R) (7 functions, among them OLS, its residuals and ridge regression; 79 functions in all):

- `%*%` with matrices and vectors (a vector becomes a row or a column as `?matmult` describes; two vectors give their inner product), through R's own BLAS (`dgemv` for matrix-vector products, `dgemm` otherwise).
- `crossprod(x)` (BLAS `dsyrk`) and `crossprod(x, y)` (`dgemm`), with vectors as columns.
- `solve(a)` and `solve(a, b)` for a square double matrix: LAPACK `dgesv`, with the reciprocal condition number (`dgecon`) checked against R's default tolerance.
- Left to GNU R: operands with `NA`, `NaN`, infinite or very large values (R's default matrix product then uses its own code), non-conformable operands, singular systems, integer or logical `a` in `solve()`, and two vectors of different lengths in `%*%`.

### Compiler slice 3 (26 October 2026): random numbers

Verified by [`r/inst/corpus/slice3.R`](../r/inst/corpus/slice3.R) (7 functions, compared on values and on the final `.Random.seed`; 86 functions in all):

- `runif(n, min, max)` and `rnorm(n, mean, sd)`, with vector or scalar parameters recycled as R does, and `n` as a count or, for a vector, its length. Draws come from GNU R's own generators (`Rf_runif`, `Rf_rnorm` in R's C API, under whatever `RNGkind()` is set), between `GetRNGstate()` and `PutRNGstate()`, so the stream is bit-identical to R's.
- `runif(1)` and `rnorm(1, ...)` with a literal count of one give scalars.
- A call that bails out restores `.Random.seed` before GNU R re-runs it ([ADR-0005](../docs/adr/0005-guarded-native-execution.md)); a draw that is `NaN` (R warns "NAs produced") is such a case.
- `floor()` and `ceiling()`.
- `sample(x, size, replace)` and `sample.int(n, size, replace)`: indices from R's own `R_unif_index()` (so `RNGkind(sample.kind = ...)` is honoured), drawn directly with replacement or for fewer than two draws, otherwise from a shrinking pool, as R does. Left to GNU R: `prob`, a single number given to `sample()` where R samples `1:x` from a vector argument, and R's errors (a sample larger than the population without replacement, an `NA` `replace`).
- Not yet: `set.seed()` inside a compiled function, other distributions.

### Phase 2 additions (27 October 2026): least squares, `drop()`, vector sub-assignment

Verified by [`r/tests/testthat/test-engines.R`](../r/tests/testthat/test-engines.R) and by the engines built on them:

- `.lm.fit(x, y, tol)` through R's own LINPACK `dqrls`, either taken directly (`.lm.fit(x, y)$coefficients`) or kept in a variable (`fit <- .lm.fit(x, y, tol = t)`) whose parts `fit$coefficients`, `fit$residuals`, `fit$rank` and `fit$pivot` are values of their own. Rank-deficient designs run natively and are pivoted exactly as R pivots them. A `.lm.fit()` result used as a whole (returned, or assigned to another variable) is outside the subset; data with `NA`, `NaN` or infinite values, which `.lm.fit()` rejects, are left to GNU R.
- `drop()` of a matrix with one row or one column gives a vector; any other matrix is left to GNU R, where it stays a matrix.
- `x[i] <- v` with an integer or double index vector and a value vector: zero indices are dropped and `v` is recycled over the remaining positions, as in R. Left to GNU R: `NA` or negative indices, a value whose length does not divide the number of positions (R warns), and an empty value (R errors).
- Rounding fixes found by the engines: `x ^ 2` is computed as `x * x`, as R's arithmetic computes it, and `sqrt()` is always the processor's correctly rounded square root.

### Phase 2 additions (27 October 2026): `colMeans()`, `cov()`, `cor()`

Verified by black-box comparison with GNU R (300 random cases per build in [`test-engines.R`](../r/tests/testthat/test-engines.R), including data offset by 1e8) and by the PLS-SEM engine ([ADR-0006](../docs/adr/0006-pls-sem-engine.md)):

- `colMeans(x)` of a double matrix: an extended-precision sum per column, divided by the number of rows before rounding.
- `cov(x, y)` and `cor(x, y)` of two numeric vectors, giving one value: the corrected two-pass mean (Chan, Golub and LeVeque, 1983), deviations and their products summed in extended precision and divided by n − 1 before rounding; a correlation divides by two standard deviations, each rounded from an extended-precision square root, and is clamped to [−1, 1]. These are also the values R gives for the same columns of `cov(X, Y)` and `cor(X, Y)` with two matrices; `cor(X)` of a single matrix rounds differently and is not yet compiled. On 64-bit ARM, where R's own rounding depends on how its compiler vectorises these loops, the compiled code calls R's own routine (`stats:::C_cov`, `stats:::C_cor`) instead.
- `cov(X, Y)` and `cor(X, Y)` with a matrix argument (28 October 2026; a vector counts as one column) give the matrix of these values for every pair of columns, with each column's mean and standard deviation computed once; `cor(X, X)` computes one triangle and mirrors it, which is exact.
- Left to GNU R: `NA` or non-finite data, unequal lengths or numbers of rows, fewer than two values, and zero standard deviations (R gives `NA` or warns).

### Phase 2 additions (28 October 2026): assigning a matrix row or column

- `m[, j] <- v` and `m[i, ] <- v` with one subscript: a single value fills the column or row; a vector is recycled when its length divides the column or row, as in R. Integer and logical values are stored into a double matrix as R converts them; assigning a column of `m` into `m` uses the value as it was before the assignment. Left to GNU R (which errors): an empty value, a value longer than the column or row or whose length does not divide it, and a subscript out of bounds. Not yet: `m[, ] <- v` and logical values into an integer matrix.
- A function or a signature that is not compiled now says so once, with the reason (`options(arwad.quiet = TRUE)` turns this off); see the amendment to [ADR-0005](../docs/adr/0005-guarded-native-execution.md).

### Equivalence corpus (26 October 2026): 201 functions

[`r/inst/corpus/`](../r/inst/corpus/) `slice1.R` to `slice5.R` hold 201 functions, beyond the Phase 1 target of 200: the slices above, plus statistics, estimators, numerical methods, finance and time series, linear algebra (IRLS logistic regression, Jacobi, LU), rank statistics, integer algorithms and simulation. Every one runs natively and matches GNU R bit for bit on Linux, macOS and Windows; seeded ones also match `.Random.seed`.

## Not in version 0 (falls back to R)

Closures created inside the function, `...`, environments, `eval` / `quote` / `substitute`, S3 and S4 dispatch, lists, data frames, character vectors, factors, recursion, `tryCatch`, `on.exit`, side effects on global state.
