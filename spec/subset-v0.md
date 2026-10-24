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

## Not in version 0 (falls back to R)

Closures created inside the function, `...`, environments, `eval` / `quote` / `substitute`, S3 and S4 dispatch, lists, data frames, character vectors, factors, recursion, `tryCatch`, `on.exit`, side effects on global state.
