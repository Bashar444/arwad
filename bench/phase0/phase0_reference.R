# Phase 0 reference: OLS and a nonparametric case bootstrap in GNU R.
# Usage (from the repository root): Rscript bench/phase0/phase0_reference.R [B]
# Writes bench/phase0/data.csv (once), bench/phase0/reference.csv and bench/phase0/reference_timing.csv.

args <- commandArgs(trailingOnly = TRUE)
B <- if (length(args)) as.integer(args[1]) else 10000L
here <- file.path("bench", "phase0")
n <- 1000L
p <- 9L
k <- p + 1L

# Data: written once with 17 significant digits; both R and Goose read this file.
data_path <- file.path(here, "data.csv")
if (!file.exists(data_path)) {
  set.seed(20261024)
  xg <- matrix(rnorm(n * p), n, p)
  beta_true <- c(0.5, seq(-1, 1, length.out = p))
  yg <- drop(cbind(1, xg) %*% beta_true + rnorm(n))
  body <- apply(cbind(xg, yg), 1, function(r) paste(sprintf("%.17g", r), collapse = ","))
  writeLines(c(paste(c(paste0("x", seq_len(p)), "y"), collapse = ","), body), data_path)
}
d <- read.csv(data_path)
X <- cbind(1, as.matrix(d[, seq_len(p)]))
y <- d$y

# Resampling indices: Park-Miller minimal-standard LCG, reproduced exactly in Goose.
lcg_indices <- function(B, n, seed = 20261024) {
  m <- 2147483647
  s <- seed
  idx <- numeric(B * n)
  for (t in seq_len(B * n)) {
    s <- (16807 * s) %% m
    idx[t] <- s %% n + 1
  }
  storage.mode(idx) <- "integer"
  matrix(idx, n, B)
}
t_idx <- system.time(idx <- lcg_indices(B, n))[["elapsed"]]

beta <- lm.fit(X, y)$coefficients

boot_with <- function(fitfun) {
  coefs <- matrix(0, B, k)
  for (b in seq_len(B)) {
    ii <- idx[, b]
    coefs[b, ] <- fitfun(X[ii, , drop = FALSE], y[ii])
  }
  coefs
}
gc()
t_lmfit <- system.time(c1 <- boot_with(function(x, y) lm.fit(x, y)$coefficients))[["elapsed"]]
gc()
t_dotlmfit <- system.time(c2 <- boot_with(function(x, y) .lm.fit(x, y)$coefficients))[["elapsed"]]
stopifnot(max(abs(c1 - c2)) < 1e-12)

fmt <- function(v) sprintf("%.17g", v)
ref <- data.frame(term = c("(Intercept)", paste0("x", seq_len(p))),
                  beta = fmt(beta), boot_mean = fmt(colMeans(c1)), boot_sd = fmt(apply(c1, 2, sd)))
write.csv(ref, file.path(here, "reference.csv"), row.names = FALSE, quote = FALSE)

timing <- data.frame(
  contender = c("R lm.fit loop", "R .lm.fit loop"),
  seconds = c(t_lmfit, t_dotlmfit),
  B = B, n = n, k = k
)
write.csv(timing, file.path(here, "reference_timing.csv"), row.names = FALSE)

cat("R", R.version$major, ".", R.version$minor, " | BLAS: ", extSoftVersion()[["BLAS"]], "\n", sep = "")
cat("index generation (untimed in comparisons):", t_idx, "s; checksum", sum(as.numeric(idx)), "\n")
cat("bootstrap B =", B, "| lm.fit:", t_lmfit, "s | .lm.fit:", t_dotlmfit, "s\n")
print(ref, row.names = FALSE)
