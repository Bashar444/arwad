# Phase 2 engines: designs and responses come from helper-designs.R.

test_that(".lm.fit() compiles and matches R bit for bit on at least 50 datasets", {
  skip_if_no_toolchain()
  designs <- aw_designs()
  expect_gte(length(designs), 50L)
  cf <- aw_compile(function(X, y) .lm.fit(X, y)$coefficients)
  rs <- aw_compile(function(X, y) .lm.fit(X, y)$residuals)
  for (nm in names(designs)) {
    d <- designs[[nm]]
    want <- .lm.fit(d$X, d$y)
    expect_true(identical(cf(d$X, d$y), want$coefficients, num.eq = FALSE), label = paste(nm, "coefficients"))
    expect_true(identical(rs(d$X, d$y), want$residuals, num.eq = FALSE), label = paste(nm, "residuals"))
  }
  expect_true(all(aw_stats(cf)$native))
})

test_that("a .lm.fit() result in a variable compiles: rank, pivot and tol, rank-deficient designs too", {
  skip_if_no_toolchain()
  f <- function(X, y, tol) {
    fit <- .lm.fit(X, y, tol = tol)
    c(fit$coefficients, fit$residuals, fit$rank, fit$pivot)
  }
  g <- aw_compile(f)
  designs <- list(full = list(cbind(1, 1:6, c(2, 1, 4, 3, 6, 5)), c(1, 3, 2, 5, 4, 6)),
                  deficient = list(cbind(1, 1:6, 2 * (1:6)), c(1, 3, 2, 5, 4, 6)),
                  wide = list(cbind(1, 1:3, c(4, 1, 2), c(0, 1, 1)), c(2, 1, 3)),
                  near = list(cbind(1, 1:8, (1:8) + 1e-9 * c(1, -1, 1, -1, 1, -1, 1, -1)), c(1, 2, 2, 3, 5, 4, 6, 7)))
  for (nm in names(designs)) {
    d <- designs[[nm]]
    for (tol in c(1e-7, 1e-11)) {
      expect_true(identical(g(d[[1L]], d[[2L]], tol), f(d[[1L]], d[[2L]], tol), num.eq = FALSE),
                  label = paste(nm, "design, tol", tol))
    }
  }
  expect_true(all(aw_stats(g)$native))
  expect_identical(sum(aw_stats(g)$bailouts), 0L)
  inline <- aw_compile(function(X, y) .lm.fit(X, y)$rank)
  expect_identical(inline(designs$deficient[[1L]], designs$deficient[[2L]]), 2L)
})

test_that("a .lm.fit() result is only used through its parts", {
  skip_if_no_toolchain()
  X <- cbind(1, c(1, 3, 2, 5))
  y <- c(1, 2, 2, 4)
  f1 <- function(X, y) { fit <- .lm.fit(X, y); fit }
  g1 <- aw_compile(f1)
  expect_identical(g1(X, y), f1(X, y))
  expect_match(aw_stats(g1)$reason[1], "holds a .lm.fit() result", fixed = TRUE)
  f2 <- function(X, y) fit <- .lm.fit(X, y)
  g2 <- aw_compile(f2)
  expect_identical(g2(X, y), f2(X, y))
  expect_match(aw_stats(g2)$reason[1], "a .lm.fit() result (a list)", fixed = TRUE)
  expect_error(arwad:::aw_check(function(X, y) .lm.fit(X, y)$qr), "only $coefficients", fixed = TRUE)
})

test_that("drop() turns a one-column or one-row matrix into a vector", {
  skip_if_no_toolchain()
  f <- function(X, b) drop(X %*% b)
  g <- aw_compile(f)
  X <- matrix(c(1.5, 2, -1, 4, 0.5, 3), 3)
  expect_identical(g(X, c(2, -1)), f(X, c(2, -1)))
  expect_identical(g(t(X), c(1, 2, 3)), f(t(X), c(1, 2, 3)))
  h <- function(X) drop(X)
  gh <- aw_compile(h)
  expect_identical(gh(X), h(X))
  expect_identical(sum(aw_stats(gh)$bailouts), 1L)
})

test_that("x[i] <- v with an index vector and a value vector matches R", {
  skip_if_no_toolchain()
  f <- function(x, i, v) { x[i] <- v; x }
  g <- aw_compile(f)
  cases <- list(list(c(1, 2, 3, 4), c(4L, 1L), c(10, 20)), list(c(1, 2, 3, 4), c(2L, 0L, 3L), c(7, 8)),
                list(c(1, 2, 3), c(5L, 1L), c(9, 8)), list(c(1, 2, 3, 4), 1:4, c(5, 6)),
                list(c(1, 2, 3), c(2L, 2L), c(4, 5)), list(c(1, 2, 3), integer(0), c(1, 2)),
                list(c(1, 2, 3), c(1L, NA), c(4, 5)), list(c(1, 2, 3), 1:3, c(4, 5)),
                list(c(1, 2, 3), c(-1L, 2L), c(4, 5)), list(c(1, 2, 3), c(1L, 2L), numeric(0)),
                list(c(1, 2, 3), c(3.7, 1.2), c(4, 5)))
  for (k in seq_along(cases)) {
    a <- cases[[k]]
    want <- tryCatch(f(a[[1]], a[[2]], a[[3]]), warning = function(w) "warning", error = function(e) "error")
    got <- tryCatch(g(a[[1]], a[[2]], a[[3]]), warning = function(w) "warning", error = function(e) "error")
    expect_identical(got, want, label = paste("case", k))
  }
  h <- function(x) { x[c(2L, 1L)] <- x; x }
  expect_identical(aw_compile(h)(c(1, 2)), h(c(1, 2)))
  i <- function(x, k) { y <- numeric(3); y[k] <- x; y }
  expect_identical(aw_compile(i)(1:2, c(3L, 1L)), i(1:2, c(3L, 1L)))
})

test_that("powers and square roots are rounded as R rounds them", {
  skip_if_no_toolchain()
  set.seed(11)
  x <- c(stats::rnorm(1e5) * 10^stats::runif(1e5, -8, 8), 0x1.24ec2267d99ecp+9)
  sq <- aw_compile(function(x) x^2)
  cu <- aw_compile(function(x) x^3)
  rt <- aw_compile(function(x) { s <- 0; for (v in x) s <- s + sqrt(abs(v)); s })
  expect_identical(sq(x), x^2)
  expect_identical(cu(x), x^3)
  expect_identical(rt(x), { s <- 0; for (v in x) s <- s + sqrt(abs(v)); s })
  expect_match(arwad:::aw_makevars[1L], "-fno-math-errno", fixed = TRUE)
})

test_that("aw_boot_ols() equals the same bootstrap run in R, on 50 datasets", {
  skip_if_no_toolchain()
  designs <- aw_designs()
  for (nm in names(designs)[seq_len(50L)]) {
    d <- designs[[nm]]
    set.seed(7)
    want <- arwad:::aw_boot_ols_kernel(d$X, d$y, 40L)
    set.seed(7)
    got <- aw_boot_ols(d$X, d$y, 40L)
    expect_true(identical(unname(got), want, num.eq = FALSE), label = paste(nm, "bootstrap"))
  }
})

test_that("aw_boot_ols() keeps the column names of X", {
  X <- cbind(intercept = 1, wt = mtcars$wt)
  set.seed(1)
  b <- aw_boot_ols(X, mtcars$mpg, B = 5)
  expect_identical(colnames(b), c("intercept", "wt"))
  expect_identical(dim(b), c(5L, 2L))
})

test_that("aw_glm_fit() equals glm.fit() on 55 designs for each family, warnings included", {
  skip_if_no_toolchain()
  designs <- aw_designs()
  for (fn in c("binomial", "poisson", "gaussian")) {
    fam <- get(fn, envir = asNamespace("stats"))()
    native <- 0L
    for (nm in names(designs)) {
      d <- designs[[nm]]
      y <- aw_glm_response(d$y, fn)
      want <- aw_with_warnings(stats::glm.fit(d$X, y, family = fam))
      got <- aw_with_warnings(aw_glm_fit(d$X, y, family = fam))
      lab <- paste(fn, nm)
      expect_true(identical(unname(got$value$coefficients), unname(want$value$coefficients), num.eq = FALSE),
                  label = paste(lab, "coefficients"))
      expect_identical(got$value$deviance, want$value$deviance, label = paste(lab, "deviance"))
      expect_identical(got$value$iter, want$value$iter, label = paste(lab, "iterations"))
      expect_identical(got$value$converged, want$value$converged, label = paste(lab, "converged"))
      expect_identical(got$warnings, want$warnings, label = paste(lab, "warnings"))
      native <- native + got$value$native
    }
    expect_gte(native, 50L, label = paste(fn, "fits run natively"))
  }
  expect_true(all(aw_stats(arwad:::aw_glm_unit())$native))
  expect_identical(sum(aw_stats(arwad:::aw_glm_unit())$bailouts), 0L)
})

test_that("aw_glm_fit() handles weights, aliased columns and families it hands to glm.fit()", {
  skip_if_no_toolchain()
  X <- cbind(1, esoph$agegp == "25-34", as.numeric(esoph$alcgp), as.numeric(esoph$tobgp))
  y <- esoph$ncases / (esoph$ncases + esoph$ncontrols)
  w <- esoph$ncases + esoph$ncontrols
  same <- function(got, want) {
    identical(unname(got$coefficients), unname(want$coefficients), num.eq = FALSE) &&
      identical(got$deviance, want$deviance) && identical(got$iter, want$iter)
  }
  fit <- aw_glm_fit(X, y, family = binomial(), weights = w)
  expect_true(fit$native)
  expect_true(same(fit, glm.fit(X, y, weights = w, family = binomial())))
  Xa <- cbind(X, 2 * X[, 3L])
  fa <- aw_glm_fit(Xa, y, family = binomial(), weights = w)
  expect_true(fa$native)
  expect_true(same(fa, glm.fit(Xa, y, weights = w, family = binomial())))
  expect_true(is.na(fa$coefficients[5L]))
  fp <- aw_glm_fit(X, y, family = binomial("probit"), weights = w)
  expect_false(fp$native)
  expect_true(same(fp, glm.fit(X, y, weights = w, family = binomial("probit"))))
  expect_error(aw_glm_fit(X, -y, family = poisson()), "negative values not allowed")
  expect_identical(names(aw_glm_fit(cbind(a = 1, b = mtcars$wt), mtcars$am, binomial())$coefficients), c("a", "b"))
})

test_that("aw_boot_glm() equals the same bootstrap loop in R on 50 designs, warnings and seed included", {
  skip_if_no_toolchain()
  designs <- aw_designs()
  r_boot <- function(X, y, family, B) {
    out <- matrix(NA_real_, B, ncol(X))
    for (b in seq_len(B)) {
      i <- sample.int(nrow(X), replace = TRUE)
      out[b, ] <- stats::glm.fit(X[i, , drop = FALSE], y[i], family = family)$coefficients
    }
    out
  }
  redone <- 0L
  for (nm in names(designs)[seq_len(50L)]) {
    d <- designs[[nm]]
    y <- aw_glm_response(d$y, "binomial")
    set.seed(5)
    want <- aw_with_warnings(r_boot(d$X, y, binomial(), 20L))
    seed_want <- .Random.seed
    set.seed(5)
    got <- aw_with_warnings(aw_boot_glm(d$X, y, family = binomial(), B = 20L))
    expect_true(identical(unname(got$value), want$value, num.eq = FALSE), label = paste(nm, "bootstrap"))
    expect_identical(got$warnings, want$warnings, label = paste(nm, "warnings"))
    expect_identical(.Random.seed, seed_want, label = paste(nm, "random number stream"))
    redone <- redone + (length(want$warnings) > 0L)
  }
  expect_gt(redone, 0L)
  set.seed(2)
  b <- aw_boot_glm(cbind(intercept = 1, wt = mtcars$wt), mtcars$vs, family = binomial(), B = 3)
  expect_identical(colnames(b), c("intercept", "wt"))
})
