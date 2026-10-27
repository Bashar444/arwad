# Phase 2, first engine: aw_boot_ols() against the ways R users write a case
# bootstrap of OLS coefficients. Same seed everywhere; the R version of the
# same algorithm must give identical results.
# Usage (from the repository root, with ARWAD_GOOSE set):
#   Rscript bench/phase2/ols_boot_bench.R
# Writes bench/phase2/ols_boot_timing.csv; REPORT.md interprets it.

suppressPackageStartupMessages({
  library(arwad)
  library(bench)
})
options(arwad.cache_dir = file.path(tempdir(), "arwad-bench-cache"))
stopifnot(aw_toolchain()$ok)

set.seed(20261027)
n <- 200
k <- 5
X <- cbind(1, matrix(rnorm(n * (k - 1)), n, k - 1))
y <- as.vector(X %*% c(1, 0.5, -0.3, 0.2, 0.1) + rnorm(n))
d <- data.frame(y = y, X[, -1])
B <- 2000L

same_algorithm_in_r <- compiler::cmpfun(arwad:::aw_boot_ols_kernel)
lm_fit_loop <- compiler::cmpfun(function(X, y, B) {
  out <- matrix(0, B, ncol(X))
  for (b in seq_len(B)) {
    idx <- sample.int(nrow(X), replace = TRUE)
    out[b, ] <- .lm.fit(X[idx, , drop = FALSE], y[idx])$coefficients
  }
  out
})
lm_formula_loop <- compiler::cmpfun(function(d, B) {
  out <- matrix(0, B, ncol(d))
  for (b in seq_len(B)) {
    idx <- sample.int(nrow(d), replace = TRUE)
    out[b, ] <- stats::coef(stats::lm(y ~ ., data = d[idx, ]))
  }
  out
})

set.seed(1); t0 <- proc.time()[["elapsed"]]; first <- aw_boot_ols(X, y, B); first_s <- proc.time()[["elapsed"]] - t0
set.seed(1); ref <- same_algorithm_in_r(X, y, B)
set.seed(1); idiom <- lm_fit_loop(X, y, B)
identical_same <- identical(unname(first), ref, num.eq = FALSE)
identical_idiom <- identical(unname(first), idiom, num.eq = FALSE)

bm <- bench::mark(
  arwad = { set.seed(1); aw_boot_ols(X, y, B) },
  same_algorithm_in_r = { set.seed(1); same_algorithm_in_r(X, y, B) },
  lm_fit_loop = { set.seed(1); lm_fit_loop(X, y, B) },
  lm_formula_loop = { set.seed(1); lm_formula_loop(d, B) },
  check = FALSE, min_iterations = 3, max_iterations = 10, time_unit = "ms", filter_gc = FALSE)
med <- as.numeric(bm$median)
res <- data.frame(contender = as.character(bm$expression), median_ms = signif(med, 4),
                  arwad_speedup = round(med / med[1], 2))
print(res, row.names = FALSE)
cat(sprintf("\nB = %d, n = %d, k = %d; first call (build) %.2f s; identical to the same algorithm in R: %s; identical to the .lm.fit loop: %s\n",
            B, n, k, first_s, identical_same, identical_idiom))
cat(R.version.string, "| Goose", aw_toolchain()$version, "|", utils::sessionInfo()$running, "\n")
write.csv(res, file.path("bench", "phase2", "ols_boot_timing.csv"), row.names = FALSE)
