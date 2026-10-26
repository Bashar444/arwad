# Slices 2 and 3 benchmark: matrix and resampling code, aw_compile() against
# GNU R's byte-compiled closures, with the same seed for both (the results
# are compared bit for bit). For the OLS bootstrap an idiomatic R version
# (X[idx, ] and solve(crossprod())) is timed as well, as the fairer baseline.
# Usage (from the repository root, with ARWAD_GOOSE set):
#   Rscript bench/phase1/slice23_bench.R
# Writes bench/phase1/slice23_timing.csv; REPORT.md interprets it.

suppressPackageStartupMessages({
  library(arwad)
  library(bench)
})
options(arwad.cache_dir = file.path(tempdir(), "arwad-bench-cache"))
stopifnot(aw_toolchain()$ok)

set.seed(20261031)
n <- 200
X <- cbind(1, matrix(rnorm(n * 4), n, 4))
y <- as.vector(X %*% c(1, 0.5, -0.3, 0.2, 0.1) + rnorm(n))
xv <- rnorm(500)
yv <- rnorm(500, 0.1)
Xl <- cbind(1, rnorm(400))
yl <- as.numeric(runif(400) < 1 / (1 + exp(-(0.3 + 0.8 * Xl[, 2]))))
A <- crossprod(matrix(rnorm(100 * 50), 100, 50))

ols_boot_loops <- function(X, y, B) {
  n <- nrow(X); k <- ncol(X)
  out <- matrix(0, B, k); Xb <- matrix(0, n, k); yb <- numeric(n)
  for (b in seq_len(B)) {
    idx <- sample.int(n, replace = TRUE)
    for (i in seq_len(n)) { yb[i] <- y[idx[i]]; for (j in seq_len(k)) Xb[i, j] <- X[idx[i], j] }
    beta <- solve(crossprod(Xb), crossprod(Xb, yb))
    for (j in seq_len(k)) out[b, j] <- beta[j]
  }
  out
}
ols_boot_idiomatic <- function(X, y, B) {
  n <- nrow(X); out <- matrix(0, B, ncol(X))
  for (b in seq_len(B)) {
    idx <- sample.int(n, replace = TRUE)
    Xb <- X[idx, , drop = FALSE]
    out[b, ] <- solve(crossprod(Xb), crossprod(Xb, y[idx]))
  }
  out
}

cases <- list(
  ols_bootstrap = list(f = ols_boot_loops, args = list(X, y, 2000)),
  bootstrap_mean = list(
    f = function(x, B) { n <- length(x); m <- numeric(B); for (b in seq_len(B)) m[b] <- mean(x[sample.int(n, replace = TRUE)]); m },
    args = list(xv, 20000)),
  permutation_test = list(
    f = function(x, y, B) {
      obs <- mean(x) - mean(y); z <- c(x, y); nx <- length(x); cnt <- 0L
      for (b in seq_len(B)) { p <- sample(z); d <- mean(p[1:nx]) - mean(p[(nx + 1):length(z)]); if (abs(d) >= abs(obs)) cnt <- cnt + 1L }
      cnt / B
    },
    args = list(xv, yv, 5000)),
  gibbs = list(
    f = function(n, rho) {
      x <- numeric(n); y <- numeric(n); s <- sqrt(1 - rho^2)
      for (i in 2:n) { x[i] <- rnorm(1, rho * y[i - 1], s); y[i] <- rnorm(1, rho * x[i], s) }
      c(mean(x), mean(y))
    },
    args = list(200000, 0.6)),
  logit_irls = list(
    f = function(X, y, iters) {
      b <- matrix(0, ncol(X), 1)
      for (it in seq_len(iters)) {
        eta <- X %*% b; p <- 1 / (1 + exp(-eta)); W <- p * (1 - p); z <- eta + (y - p) / W
        XW <- X
        for (i in seq_len(nrow(X))) for (j in seq_len(ncol(X))) XW[i, j] <- X[i, j] * W[i]
        b <- solve(crossprod(XW, X), crossprod(XW, z))
      }
      b
    },
    args = list(Xl, yl, 25)),
  power_iteration = list(
    f = function(A, iters) {
      v <- matrix(0, nrow(A), 1); v[1, 1] <- 1; lam <- 0
      for (i in seq_len(iters)) { w <- A %*% v; lam <- sqrt(sum(w * w)); v <- w / lam }
      lam
    },
    args = list(A, 500))
)

seeded <- function(f, args) function() { set.seed(1); do.call(f, args) }
rows <- list()
for (nm in names(cases)) {
  cs <- cases[[nm]]
  fr <- compiler::cmpfun(cs$f)
  ga <- aw_compile(cs$f, name = nm)
  t0 <- proc.time()[["elapsed"]]
  first <- seeded(ga, cs$args)()
  build_s <- proc.time()[["elapsed"]] - t0
  same <- identical(first, seeded(fr, cs$args)(), num.eq = FALSE)
  utils::capture.output(ex <- aw_explain(ga))
  native <- isTRUE(all(ex$native)) && sum(ex$bailouts) == 0
  bm <- bench::mark(R = seeded(fr, cs$args)(), arwad = seeded(ga, cs$args)(),
                    check = FALSE, min_iterations = 3, max_iterations = 50, time_unit = "ms", filter_gc = FALSE)
  med <- as.numeric(bm$median)
  rows[[nm]] <- data.frame(case = nm, identical = same, native = native, first_call_s = round(build_s, 2),
                           r_median_ms = signif(med[1], 4), arwad_median_ms = signif(med[2], 4),
                           speedup = round(med[1] / med[2], 2))
}
fi <- compiler::cmpfun(ols_boot_idiomatic)
bi <- bench::mark(R_idiomatic = { set.seed(1); fi(X, y, 2000) }, min_iterations = 3, max_iterations = 20,
                  time_unit = "ms", filter_gc = FALSE)
res <- do.call(rbind, rows)
res$note <- ""
res$note[res$case == "ols_bootstrap"] <- sprintf("idiomatic R (X[idx, ], vectorised solve): %.4g ms",
                                                 as.numeric(bi$median))
print(res, row.names = FALSE)
cat("\n", R.version.string, "| Goose", aw_toolchain()$version, "|", utils::sessionInfo()$running, "\n")
write.csv(res, file.path("bench", "phase1", "slice23_timing.csv"), row.names = FALSE)
