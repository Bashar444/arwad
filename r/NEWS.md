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
