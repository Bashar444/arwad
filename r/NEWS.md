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
