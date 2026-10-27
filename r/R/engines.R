# Statistical engines (Phase 2): functions written in the compilable subset,
# shipped with the package and compiled on first use. Each returns exactly
# what GNU R returns when it runs the same algorithm with the same seed, and
# is validated on at least 50 datasets (tests/testthat/test-engines.R).

# The compiled kernel of aw_boot_ols(): case resampling and LINPACK QR.
aw_boot_ols_kernel <- function(X, y, B) {
  n <- nrow(X)
  k <- ncol(X)
  out <- matrix(0, B, k)
  Xb <- matrix(0, n, k)
  yb <- numeric(n)
  for (b in seq_len(B)) {
    idx <- sample.int(n, replace = TRUE)
    for (i in seq_len(n)) {
      yb[i] <- y[idx[i]]
      for (j in seq_len(k)) Xb[i, j] <- X[idx[i], j]
    }
    cf <- .lm.fit(Xb, yb)$coefficients
    for (j in seq_len(k)) out[b, j] <- cf[j]
  }
  out
}

#' Bootstrap OLS coefficients, compiled
#'
#' Case-resampling (nonparametric) bootstrap of least-squares coefficients.
#' Each replicate draws `nrow(X)` rows with replacement
#' (`sample.int(n, replace = TRUE)`) and fits them with [stats::.lm.fit()],
#' R's own LINPACK QR, which [stats::lm()] uses too. The loop runs as native
#' code when the Arwad toolchain is available ([aw_toolchain()]) and in GNU R
#' otherwise; for the same seed both give identical results. A replicate whose
#' resampled design is rank-deficient is handed to GNU R, which returns the
#' coefficients `.lm.fit()` gives (pivoted).
#'
#' @param X A numeric design matrix; include a column of ones for an intercept.
#' @param y A numeric response vector of length `nrow(X)`.
#' @param B The number of bootstrap replicates.
#' @return A `B` by `ncol(X)` matrix of coefficients, one row per replicate,
#'   with the column names of `X`.
#' @export
#' @examples
#' X <- cbind(intercept = 1, wt = mtcars$wt, hp = mtcars$hp)
#' set.seed(1)
#' b <- aw_boot_ols(X, mtcars$mpg, B = 200)
#' apply(b, 2, sd) # bootstrap standard errors
aw_boot_ols <- function(X, y, B = 1000L) {
  X <- as.matrix(X)
  cn <- colnames(X)
  Xd <- matrix(as.double(X), nrow(X), ncol(X))
  yd <- as.double(y)
  if (length(yd) != nrow(Xd)) stop("length(y) must equal nrow(X)")
  if (is.null(aw_state$boot_ols)) aw_state$boot_ols <- aw_compile(aw_boot_ols_kernel, name = "aw_boot_ols")
  out <- aw_state$boot_ols(Xd, yd, as.integer(B))
  colnames(out) <- cn
  out
}
