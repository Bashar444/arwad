# Phase 2, second engine: aw_boot_glm() against the ways R users write a case
# bootstrap of logistic-regression coefficients. Same seed everywhere; every
# contender must give identical coefficients.
# Usage (from the repository root, with ARWAD_GOOSE set):
#   Rscript bench/phase2/glm_boot_bench.R
# Writes bench/phase2/glm_boot_timing.csv; REPORT.md interprets it.

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
y <- rbinom(n, 1, plogis(as.vector(X %*% c(-0.3, 0.8, -0.5, 0.4, 0.2))))
d <- data.frame(y = y, X[, -1])
B <- 1000L

same_algorithm_in_r <- compiler::cmpfun(function(X, y, B) {
  arwad:::aw_glm_kernel(X, y, rep(1, nrow(X)), 1L, B, 1e-8, 25L)[, seq_len(ncol(X))]
})
glm_fit_loop <- compiler::cmpfun(function(X, y, B) {
  out <- matrix(0, B, ncol(X))
  for (b in seq_len(B)) {
    idx <- sample.int(nrow(X), replace = TRUE)
    out[b, ] <- stats::glm.fit(X[idx, , drop = FALSE], y[idx], family = stats::binomial())$coefficients
  }
  out
})
glm_formula_loop <- compiler::cmpfun(function(d, B) {
  out <- matrix(0, B, ncol(d))
  for (b in seq_len(B)) {
    idx <- sample.int(nrow(d), replace = TRUE)
    out[b, ] <- stats::coef(stats::glm(y ~ ., data = d[idx, ], family = stats::binomial))
  }
  out
})

warned <- 0L
count <- function(expr) withCallingHandlers(expr, warning = function(w) {
  warned <<- warned + 1L
  invokeRestart("muffleWarning")
})
set.seed(1); t0 <- proc.time()[["elapsed"]]; first <- count(aw_boot_glm(X, y, binomial(), B)); first_s <- proc.time()[["elapsed"]] - t0
set.seed(1); ref <- same_algorithm_in_r(X, y, B)
set.seed(1); idiom <- count(glm_fit_loop(X, y, B))
set.seed(1); formula <- count(glm_formula_loop(d, B))
identical_same <- identical(unname(first), ref, num.eq = FALSE)
identical_idiom <- identical(unname(first), idiom, num.eq = FALSE)
identical_formula <- identical(unname(first), unname(formula), num.eq = FALSE)

bm <- bench::mark(
  arwad = { set.seed(1); aw_boot_glm(X, y, binomial(), B) },
  same_algorithm_in_r = { set.seed(1); same_algorithm_in_r(X, y, B) },
  glm_fit_loop = { set.seed(1); glm_fit_loop(X, y, B) },
  glm_formula_loop = { set.seed(1); glm_formula_loop(d, B) },
  check = FALSE, min_iterations = 3, max_iterations = 10, time_unit = "ms", filter_gc = FALSE)
med <- as.numeric(bm$median)
res <- data.frame(contender = as.character(bm$expression), median_ms = signif(med, 4),
                  arwad_speedup = round(med / med[1], 2))
print(res, row.names = FALSE)
cat(sprintf(paste0("\nB = %d, n = %d, k = %d, logistic regression; first call (build) %.2f s; warnings: %d\n",
                   "identical to the same algorithm in R: %s; to the glm.fit loop: %s; to the glm() loop: %s\n"),
            B, n, k, first_s, warned, identical_same, identical_idiom, identical_formula))
cat(R.version.string, "| Goose", aw_toolchain()$version, "|", utils::sessionInfo()$running, "\n")
write.csv(res, file.path("bench", "phase2", "glm_boot_timing.csv"), row.names = FALSE)
