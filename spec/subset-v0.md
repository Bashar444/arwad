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

## Not in version 0 (falls back to R)

Closures created inside the function, `...`, environments, `eval` / `quote` / `substitute`, S3 and S4 dispatch, lists, data frames, character vectors, factors, recursion, `tryCatch`, `on.exit`, side effects on global state.
