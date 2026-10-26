# arwad (R package)

`aw_compile()` compiles an R function written in the statistical subset of R ([spec/subset-v0.md](../spec/subset-v0.md)) to native code through [Goose](https://github.com/aardappel/goose) and the C compiler R uses for packages, and keeps GNU R's results: whenever the native code meets a case it does not model, the call is re-run in GNU R ([ADR-0005](../docs/adr/0005-guarded-native-execution.md)).

Status: Phase 1, compiler slice 1. Scalars and vectors, loops, indexing; matrices and vectorised arithmetic come in slice 2. Speed and limits are measured in [bench/phase1/REPORT.md](../bench/phase1/REPORT.md).

## Install

```r
# from a clone of https://github.com/bashar-al-agha/arwad
install.packages("r", repos = NULL, type = "source")
```

Compilation needs the `goose` executable ([releases](https://github.com/aardappel/goose/releases), v2026.3 or later) and R's package toolchain (Rtools on Windows). Point arwad at Goose with `options(arwad.goose = "/path/to/goose")` or the `ARWAD_GOOSE` environment variable; check with `aw_toolchain()`. Without Goose every function still runs, in GNU R.

## Use

```r
library(arwad)

collatz <- function(n) {
  steps <- 0L
  while (n != 1) {
    if (n %% 2 == 0) n <- n / 2 else n <- 3 * n + 1
    steps <- steps + 1L
  }
  steps
}

g <- aw_compile(collatz)
g(27)          # first call with a double argument builds the native unit
#> [1] 111
aw_explain(g)  # native or GNU R for each argument signature, and why
aw_source(g)   # the generated Goose
```

A function outside the subset comes back unchanged, with the reason:

```r
attr(aw_compile(function(x) paste(x, "!")), "arwad_fallback")
#> [1] "call to `paste` is not in subset v0: paste(x, \"!\")"
```

## Guarantees and limits

- Results, errors and warnings are GNU R's: the 39-function corpus in [`inst/corpus/slice1.R`](inst/corpus/slice1.R) is checked bit for bit (`identical(..., num.eq = FALSE)`), including `NA`, `NaN`, `-0` and visibility.
- The first call for each argument signature builds a native library (4–5 s on the Phase 0 laptop, mostly `R CMD SHLIB` overhead); later calls and later sessions reuse it from the cache in `tools::R_user_dir("arwad", "cache")`.
- Each call pays an R-level dispatch cost (about 33 µs), so tiny functions are slower than in R; the gain is in loops (14–35× against R's byte code in [the report](../bench/phase1/REPORT.md)).
- Arguments are evaluated on entry rather than lazily, and a running compiled loop cannot be interrupted.
