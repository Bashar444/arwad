# Compatibility with CRAN

## 1. Census (24 October 2026)

Produced by [`scripts/cran_census.R`](../scripts/cran_census.R) from `tools::CRAN_package_db()`, counting unique packages. Raw output: [`research/`](../research/).

| Measure | Packages | Share |
|---|---:|---:|
| All CRAN packages | 25,504 | 100% |
| Pure R (`NeedsCompilation: no`) | 19,923 | 78.1% |
| Contain compiled code (`NeedsCompilation: yes`) | 5,581 | 21.9% |
| `LinkingTo` Rcpp | 3,378 | 13.2% |
| `LinkingTo` RcppArmadillo | 1,370 | 5.4% |
| `LinkingTo` cpp11 | 114 | 0.4% |
| Licence field mentions GPL | 16,521 | 64.8% |
| Licence field mentions MIT | 7,331 | 28.7% |

Licence categories overlap because some packages are dual-licensed.

**Most depended-upon packages** (direct reverse dependencies through `Depends`, `Imports` and `LinkingTo`): dplyr 5,076 · ggplot2 4,997 · rlang 3,995 · Rcpp 3,419 · tibble 2,533 · tidyr 2,515 · stringr 2,272 · magrittr 2,269 · MASS 2,177 · purrr 2,139 · cli 1,812 · jsonlite 1,772 · data.table 1,678 · Matrix 1,633 · RcppArmadillo 1,374. The top 30 are in `research/cran_top_reverse_deps_2026-10-24.csv`.

## 2. Compatibility levels

| Level | Meaning | Available from |
|---|---|---|
| **L0 Hosted** | The package runs on GNU R with `rgoose` loaded | Phase 1, for every package |
| **L1 Native, pure R** | A pure-R package runs on the standalone evaluator | Phase 4 |
| **L2 Native, compiled** | A package with C, C++ or Fortran code runs through the R C-API layer | Phases 4–5 |
| **L3 Accelerated** | A package's hot functions run in the static tier | Phase 2 onward, package by package |

## 3. What "supported" means

A package is supported at a level when its examples, its tests (testthat, tinytest or RUnit) and its vignettes produce results equivalent to GNU R: the same values within the equivalence tolerance, the same errors and warnings (class and message), and the same printed output wherever the tests compare it.

## 4. Strategy for the standalone runtime

1. **C-API symbol census.** Build every compiled CRAN package once against GNU R, record which R API entry points its object code references, rank the entry points by how many packages need them, and implement them in that order.
2. **Dependency order.** Base and recommended packages first (base, stats, utils, methods, graphics, grDevices, tools, MASS, Matrix, survival, lattice, nlme, mgcv and the rest), then the most depended-upon packages above (rlang, vctrs, cli, glue, Rcpp, tibble, dplyr), because each one unlocks thousands of dependants.
3. **Nightly dashboard.** Run every package's checks on GNU R and on R-Goose, publish pass rates by level, and open an issue automatically for every regression.
4. **Rcpp.** Rcpp and RcppArmadillo are largely header-only C++ layers over the R C API. Once the C-API layer covers what they use, the 3,378 packages linking to Rcpp (overlapping with the 1,370 linking to RcppArmadillo) can follow.

## 5. Targets

Shares are of all CRAN packages at the time of measurement.

| Milestone | L0 | L1 + L2 (native) | L3 |
|---|---:|---:|---|
| Phase 1 exit | 100% | — | functions in `spec/subset-v0.md` |
| Phase 2 exit | 100% | — | statistical engines of Phase 2 |
| Phase 4 exit | 100% | ≥ 50% | growing |
| Phase 5 exit | 100% | ≥ 95%, then ≥ 99% | growing |
