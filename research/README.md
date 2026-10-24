# Research data

| File | Contents |
|---|---|
| `cran_census_2026-10-24.csv` | Counts of CRAN packages by compilation need, C++ linkage and licence family |
| `cran_top_reverse_deps_2026-10-24.csv` | The 30 non-base packages with the most direct reverse dependencies |

Reproduce with `Rscript scripts/cran_census.R` (R 4.6.0 was used). The script reads the live CRAN package database, so later runs give later figures; keep each dated output.

Summary of the 24 October 2026 census: 25,504 packages; 19,923 pure R (78.1%); 5,581 with compiled code (21.9%); 3,378 linking to Rcpp; most depended-upon packages dplyr (5,076), ggplot2 (4,997), rlang (3,995) and Rcpp (3,419).
