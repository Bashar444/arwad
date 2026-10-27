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
#' resampled design is rank-deficient gets the coefficients `.lm.fit()` gives
#' (pivoted).
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

# The compiled kernel of aw_glm_fit() and aw_boot_glm(): iteratively
# reweighted least squares for three families with their canonical links,
# re-implemented from R's documentation (?glm, ?glm.control, ?family) and
# black-box tests against R's own family functions and glm.fit().
# fam: 1 binomial (logit), 2 poisson (log), 3 gaussian (identity).
# B = 0 fits the data once; B > 0 refits B case resamples. One row per fit:
# the coefficients, the deviance, the iterations, a status and the rank.
# Status 0: converged with nothing to warn about. Anything else (divergence,
# invalid fitted values, no convergence, fitted values at the boundary) is a
# case for which glm.fit() warns or errors; the R wrappers hand it to
# glm.fit() so that the result and its warnings are R's own.
aw_glm_kernel <- function(X, y, wt, fam, B, epsilon, maxit) {
  n <- nrow(X)
  p <- ncol(X)
  eps <- 2.220446049250313e-16
  tol <- min(1e-07, epsilon / 1000)
  reps <- if (B > 0L) B else 1L
  out <- matrix(0, reps, p + 4L)
  Xb <- matrix(0, n, p)
  yb <- numeric(n)
  wb <- numeric(n)
  off <- numeric(n)
  eta <- numeric(n)
  mu <- numeric(n)
  mev <- numeric(n)
  vm <- numeric(n)
  dr <- numeric(n)
  for (b in seq_len(reps)) {
    if (B > 0L) {
      idx <- sample.int(n, replace = TRUE)
    } else {
      idx <- seq_len(n)
    }
    for (i in seq_len(n)) {
      k <- idx[i]
      yb[i] <- y[k]
      wb[i] <- wt[k]
      for (j in seq_len(p)) Xb[i, j] <- X[k, j]
    }
    # Starting values: the family's mustart, through the link.
    for (i in seq_len(n)) {
      if (fam == 1L) {
        m <- (wb[i] * yb[i] + 0.5) / (wb[i] + 1)
        eta[i] <- log(m / (1 - m))
      } else if (fam == 2L) {
        eta[i] <- log(yb[i] + 0.1)
      } else {
        eta[i] <- yb[i]
      }
    }
    start <- numeric(p)
    piv <- seq_len(p)
    rank <- p
    status <- 0
    iter <- 0L
    conv <- FALSE
    devold <- 0
    dev <- 0
    for (it in 0:maxit) {
      # Fitted values, deviance residuals and their validity at eta.
      for (i in seq_len(n)) {
        e <- eta[i]
        if (is.na(e)) {
          status <- 2
          m <- e
        } else if (fam == 1L) {
          ex <- if (e < -30) eps else if (e > 30) 1 / eps else exp(e)
          m <- ex / (1 + ex)
          a1 <- if (yb[i] != 0) yb[i] * log(yb[i] / m) else 0
          y0 <- 1 - yb[i]
          a0 <- if (y0 != 0) y0 * log(y0 / (1 - m)) else 0
          dr[i] <- 2 * wb[i] * (a1 + a0)
          if (!(m > 0 && m < 1)) status <- 2
        } else if (fam == 2L) {
          m <- max(exp(e), eps)
          dr[i] <- if (yb[i] > 0) 2 * (wb[i] * (yb[i] * log(yb[i] / m) - (yb[i] - m))) else 2 * (m * wb[i])
          if (m == 1 / 0) status <- 2
        } else {
          m <- e
          dr[i] <- wb[i] * ((yb[i] - m)^2)
        }
        mu[i] <- m
      }
      if (status != 0) break
      dev <- sum(dr)
      if (it > 0L) {
        if (is.na(dev) || abs(dev) == 1 / 0) {
          status <- 1
          break
        }
        if (abs(dev - devold) / (abs(dev) + 0.1) < epsilon) {
          conv <- TRUE
          break
        }
      }
      devold <- dev
      if (it == maxit) break
      # One weighted least-squares step.
      for (i in seq_len(n)) {
        e <- eta[i]
        if (fam == 1L) {
          mev[i] <- if (e > 30 || e < -30) eps else exp(e) / ((1 + exp(e)) * (1 + exp(e)))
          vm[i] <- mu[i] * (1 - mu[i])
        } else if (fam == 2L) {
          mev[i] <- max(exp(e), eps)
          vm[i] <- mu[i]
        } else {
          mev[i] <- 1
          vm[i] <- 1
        }
        if (is.na(vm[i]) || vm[i] == 0 || is.na(mev[i]) || mev[i] == 0) status <- 3
      }
      if (status != 0) break
      z <- (eta - off) + (yb - mu) / mev
      w <- sqrt((wb * mev^2) / vm)
      fit <- .lm.fit(Xb * w, z * w, tol = tol)
      cf <- fit$coefficients
      for (j in seq_len(p)) if (is.na(cf[j]) || abs(cf[j]) == 1 / 0) status <- 4
      if (status != 0) break
      piv <- fit$pivot
      rank <- fit$rank
      start[piv] <- cf
      eta <- drop(Xb %*% start)
      eta <- eta + off
      iter <- it + 1L
    }
    if (status == 0 && !conv) status <- 5
    if (status == 0) {
      for (i in seq_len(n)) {
        if (fam == 1L && (mu[i] > 1 - 10 * eps || mu[i] < 10 * eps)) status <- 6
        if (fam == 2L && mu[i] < 10 * eps) status <- 6
      }
    }
    if (rank < p) for (j in (rank + 1L):p) start[piv[j]] <- NA_real_
    for (j in seq_len(p)) out[b, j] <- start[j]
    out[b, p + 1L] <- dev
    out[b, p + 2L] <- iter
    out[b, p + 3L] <- status
    out[b, p + 4L] <- rank
  }
  out
}

# The family code the kernel knows, or 0 for glm.fit().
aw_glm_family <- function(family) {
  if (is.function(family)) family <- family()
  if (!inherits(family, "family")) stop("'family' must be a family object, such as binomial()")
  code <- c("binomial logit" = 1L, "poisson log" = 2L, "gaussian identity" = 3L)[paste(family$family, family$link)]
  list(family = family, code = if (is.na(code)) 0L else unname(code))
}

# Data the kernel fits exactly as glm.fit() does: finite numbers, positive
# prior weights, and responses for which glm.fit() neither warns nor errors
# before it starts (binomial: 0 <= y <= 1 with whole numbers of successes;
# poisson: whole non-negative counts).
aw_glm_native_ok <- function(X, y, w, code) {
  if (code == 0L || !is.numeric(X) || !(is.numeric(y) || is.logical(y)) || nrow(X) == 0L || ncol(X) == 0L ||
      length(y) != nrow(X) || length(w) != nrow(X)) return(FALSE)
  if (!all(is.finite(X)) || !all(is.finite(y)) || !all(is.finite(w)) || any(w <= 0)) return(FALSE)
  switch(code,
    { m <- w * y; all(y >= 0 & y <= 1) && !any(abs(m - round(m)) > 0.001) },
    all(y >= 0 & y == round(y)),
    TRUE)
}

aw_glm_unit <- function() {
  if (is.null(aw_state$glm)) aw_state$glm <- aw_compile(aw_glm_kernel, name = "aw_glm")
  aw_state$glm
}

#' Fit a generalised linear model, compiled
#'
#' Iteratively reweighted least squares for binomial (logit), Poisson (log)
#' and Gaussian (identity) models, run as native code through Arwad and
#' identical to [stats::glm.fit()]: the same coefficients, deviance and
#' number of iterations, bit for bit. Each step solves its weighted least
#' squares problem with R's own LINPACK QR, as `glm.fit()` does. Anything the
#' native path does not cover is handed to `glm.fit()` itself: other families
#' and links, zero or missing weights, non-finite data, and every fit for
#' which `glm.fit()` warns (no convergence, fitted probabilities of 0 or 1,
#' step halving), so that the result and its warnings are R's.
#'
#' @param x A numeric design matrix; include a column of ones for an intercept.
#' @param y The response: for the binomial family, proportions between 0 and
#'   1 (with `weights` the numbers of trials) or 0/1 outcomes.
#' @param family A family object or function: `binomial()`, `poisson()` or
#'   `gaussian()` run natively with their default links.
#' @param weights Optional prior weights.
#' @param epsilon,maxit Convergence tolerance and iteration limit, as in
#'   [stats::glm.control()].
#' @return A list: `coefficients` (named by the columns of `x`; `NA` for
#'   columns dropped as linearly dependent), `deviance`, `iter`, `converged`,
#'   `rank`, and `native` (`FALSE` when `glm.fit()` produced the result).
#' @export
#' @examples
#' X <- cbind(intercept = 1, wt = mtcars$wt, hp = mtcars$hp)
#' fit <- aw_glm_fit(X, mtcars$am, family = binomial())
#' fit$coefficients
#' identical(fit$coefficients, glm.fit(X, mtcars$am, family = binomial())$coefficients)
aw_glm_fit <- function(x, y, family = stats::gaussian(), weights = NULL, epsilon = 1e-8, maxit = 25L) {
  fam <- aw_glm_family(family)
  ctl <- stats::glm.control(epsilon = epsilon, maxit = maxit)
  X <- as.matrix(x)
  w <- if (is.null(weights)) rep(1, NROW(y)) else weights
  r_fit <- function() {
    f <- stats::glm.fit(X, y, weights = weights, family = fam$family, control = ctl)
    list(coefficients = f$coefficients, deviance = f$deviance, iter = f$iter, converged = f$converged,
         rank = f$rank, native = FALSE)
  }
  if (!aw_glm_native_ok(X, y, w, fam$code)) return(r_fit())
  p <- ncol(X)
  res <- tryCatch(aw_glm_unit()(matrix(as.double(X), nrow(X), p), as.double(y), as.double(w), fam$code, 0L,
                                ctl$epsilon, as.integer(ctl$maxit)),
                  error = function(e) NULL)
  if (is.null(res) || res[1L, p + 3L] != 0) return(r_fit())
  cf <- res[1L, seq_len(p)]
  names(cf) <- colnames(X)
  list(coefficients = cf, deviance = res[1L, p + 1L], iter = as.integer(res[1L, p + 2L]), converged = TRUE,
       rank = as.integer(res[1L, p + 4L]), native = TRUE)
}

#' Bootstrap GLM coefficients, compiled
#'
#' Case-resampling (nonparametric) bootstrap of the coefficients of a
#' binomial (logit), Poisson (log) or Gaussian (identity) model. Each
#' replicate draws `nrow(x)` rows with replacement
#' (`sample.int(n, replace = TRUE)`) and fits them as [aw_glm_fit()] does. For
#' the same seed the result is identical to this loop in R, warnings
#' included: `for (b in 1:B) { i <- sample.int(n, replace = TRUE);
#' out[b, ] <- glm.fit(x[i, , drop = FALSE], y[i], weights = weights[i],
#' family = family)$coefficients }`. Replicates for which `glm.fit()` warns
#' are refitted by `glm.fit()` itself, from the same resample.
#'
#' @inheritParams aw_glm_fit
#' @param B The number of bootstrap replicates.
#' @return A `B` by `ncol(x)` matrix of coefficients, one row per replicate,
#'   with the column names of `x`.
#' @export
#' @examples
#' X <- cbind(intercept = 1, wt = mtcars$wt)
#' set.seed(1)
#' b <- aw_boot_glm(X, mtcars$vs, family = binomial(), B = 200)
#' apply(b, 2, sd) # bootstrap standard errors
aw_boot_glm <- function(x, y, family = stats::gaussian(), B = 1000L, weights = NULL, epsilon = 1e-8, maxit = 25L) {
  fam <- aw_glm_family(family)
  ctl <- stats::glm.control(epsilon = epsilon, maxit = maxit)
  X <- as.matrix(x)
  n <- nrow(X)
  p <- ncol(X)
  B <- as.integer(B)
  w <- if (is.null(weights)) rep(1, NROW(y)) else weights
  one <- function(i) {
    stats::glm.fit(X[i, , drop = FALSE], y[i], weights = if (!is.null(weights)) weights[i],
                   family = fam$family, control = ctl)$coefficients
  }
  r_loop <- function() {
    out <- matrix(NA_real_, B, p)
    for (b in seq_len(B)) out[b, ] <- one(sample.int(n, replace = TRUE))
    out
  }
  if (!aw_glm_native_ok(X, y, w, fam$code)) {
    out <- r_loop()
  } else {
    if (!exists(".Random.seed", envir = globalenv(), inherits = FALSE)) stats::runif(0L)
    seed0 <- get(".Random.seed", envir = globalenv())
    res <- tryCatch(aw_glm_unit()(matrix(as.double(X), n, p), as.double(y), as.double(w), fam$code, B,
                                  ctl$epsilon, as.integer(ctl$maxit)),
                    error = function(e) NULL)
    if (is.null(res)) {
      assign(".Random.seed", seed0, envir = globalenv())
      out <- r_loop()
    } else {
      out <- res[, seq_len(p), drop = FALSE]
      redo <- which(res[, p + 3L] != 0)
      if (length(redo)) {
        # Replay the resamples up to the last one to redo, then leave the
        # stream where the kernel left it.
        seed1 <- get(".Random.seed", envir = globalenv())
        assign(".Random.seed", seed0, envir = globalenv())
        for (b in seq_len(max(redo))) {
          i <- sample.int(n, replace = TRUE)
          if (b %in% redo) out[b, ] <- one(i)
        }
        assign(".Random.seed", seed1, envir = globalenv())
      }
    }
  }
  colnames(out) <- colnames(X)
  out
}
