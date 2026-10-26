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
