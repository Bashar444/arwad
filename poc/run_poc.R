# Phase 0.4: call the Goose kernels from inside R and compare with GNU R.
# Usage (from the repository root): Rscript poc/run_poc.R [B] [runs]

args <- commandArgs(trailingOnly = TRUE)
B <- if (length(args) >= 1) as.integer(args[1]) else 10000L
runs <- if (length(args) >= 2) as.integer(args[2]) else 3L

dll <- dyn.load(file.path("poc", "arwadpoc.dll"))
aw_ols <- function(X, y) .Call("aw_ols_call", X, y, PACKAGE = "arwadpoc")
aw_boot <- function(X, y, idx) .Call("aw_boot_ols_call", X, y, idx, PACKAGE = "arwadpoc")

d <- read.csv(file.path("bench", "phase0", "data.csv"))
n <- nrow(d)
X <- cbind(1, as.matrix(d[, 1:9]))
y <- d$y
storage.mode(X) <- "double"

# Same resampling indices as the Phase 0 benchmark (Park-Miller LCG).
lcg_indices <- function(B, n, seed = 20261024) {
  m <- 2147483647; s <- seed
  idx <- numeric(B * n)
  for (t in seq_len(B * n)) { s <- (16807 * s) %% m; idx[t] <- s %% n + 1 }
  storage.mode(idx) <- "integer"
  matrix(idx, n, B)
}
idx <- lcg_indices(B, n)
cat("index checksum:", sum(as.numeric(idx)), "\n")

# 1. Equivalence of a single fit.
b_r <- lm.fit(X, y)$coefficients
b_g <- aw_ols(X, y)
cat(sprintf("single fit: max relative error vs lm.fit = %.3g\n", max(abs(b_g - b_r) / abs(b_r))))

# 2. Bootstrap: R loops vs one .Call into Goose.
boot_r <- function(fitfun) {
  out <- matrix(0, ncol(X), B)
  for (b in seq_len(B)) { ii <- idx[, b]; out[, b] <- fitfun(X[ii, , drop = FALSE], y[ii]) }
  out
}
time_it <- function(expr_fun) {
  vapply(seq_len(runs), function(r) { gc(); system.time(res <<- expr_fun())[["elapsed"]] }, numeric(1))
}
res <- NULL
t_lmfit <- time_it(function() boot_r(function(x, y) lm.fit(x, y)$coefficients)); c_lmfit <- res
t_dot <- time_it(function() boot_r(function(x, y) .lm.fit(x, y)$coefficients)); c_dot <- res
t_goose <- time_it(function() aw_boot(X, y, idx)); c_goose <- res

rel <- function(a, b) max(abs(a - b) / pmax(abs(b), 1e-300))
cat(sprintf("bootstrap: max relative error Goose vs lm.fit loop = %.3g\n", rel(c_goose, c_lmfit)))
cat(sprintf("bootstrap SDs: max relative error = %.3g\n",
            rel(apply(c_goose, 1, sd), apply(c_lmfit, 1, sd))))

# 3. Memory R allocates for each approach (one replicate set), if 'bench' is available.
if (requireNamespace("bench", quietly = TRUE)) {
  bm <- bench::mark(
    goose = aw_boot(X, y, idx[, 1:100, drop = FALSE]),
    dot_lm_fit = { o <- matrix(0, ncol(X), 100); for (b in 1:100) { ii <- idx[, b]; o[, b] <- .lm.fit(X[ii, , drop = FALSE], y[ii])$coefficients }; o },
    iterations = 5, check = FALSE, filter_gc = FALSE)
  cat("\nR memory allocated per 100 replicates:\n")
  print(bm[, c("expression", "median", "mem_alloc")])
}

timing <- data.frame(
  contender = c("R loop + lm.fit", "R loop + .lm.fit", "Goose via .Call (gcc -O2)"),
  runs = c(paste(t_lmfit, collapse = ", "), paste(t_dot, collapse = ", "), paste(t_goose, collapse = ", ")),
  median_s = c(median(t_lmfit), median(t_dot), median(t_goose))
)
timing$speedup_vs_dot_lm_fit <- round(median(t_dot) / timing$median_s, 2)
cat("\nBootstrap B =", B, ", n =", n, ", k =", ncol(X), "\n")
print(timing, row.names = FALSE)
write.csv(timing, file.path("poc", "poc_timing.csv"), row.names = FALSE)
