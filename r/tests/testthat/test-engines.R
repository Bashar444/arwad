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

test_that("colMeans(), cov() and cor() compile and match R bit for bit", {
  skip_if_no_toolchain()
  fc <- aw_compile(function(x, y) cov(x, y))
  fr <- aw_compile(function(x, y) cor(x, y))
  fm <- aw_compile(function(X) colMeans(X))
  set.seed(7)
  for (t in seq_len(300L)) {
    n <- sample(c(2:9, 40L, 300L), 1L)
    x <- (if (t %% 3L == 0L) 1e8 else stats::runif(1L, -5, 5)) + stats::rnorm(n, 0, 10^stats::runif(1L, -3, 2))
    y <- if (t %% 4L == 0L) -2 * x + 3 else 0.4 * x + stats::rnorm(n, 0, 10^stats::runif(1L, -3, 2))
    expect_true(identical(fc(x, y), stats::cov(x, y), num.eq = FALSE), label = paste("cov", t))
    expect_true(identical(fr(x, y), stats::cor(x, y), num.eq = FALSE), label = paste("cor", t))
    M <- cbind(x, y, x * y)
    dimnames(M) <- NULL
    expect_true(identical(fm(M), colMeans(M), num.eq = FALSE), label = paste("colMeans", t))
  }
  expect_identical(fc(c(1, NA, 3), c(2, 5, 1)), stats::cov(c(1, NA, 3), c(2, 5, 1)))
  expect_identical(suppressWarnings(fr(c(1, 1, 1), c(2, 5, 1))), suppressWarnings(stats::cor(c(1, 1, 1), c(2, 5, 1))))
})

aw_pls_fit_models <- function() {
  lapply(aw_pls_models(), function(d) suppressMessages(seminr::estimate_pls(d$data, d$mm, d$sm, maxIt = d$maxIt)))
}

test_that("the compiled PLS path algorithm equals seminr::estimate_pls() on at least 50 models", {
  skip_if_no_toolchain()
  skip_if_not_installed("seminr")
  fits <- aw_pls_fit_models()
  native <- 0L
  for (nm in names(fits)) {
    m <- fits[[nm]]
    s <- arwad:::aw_pls_spec(m)
    if (is.null(s)) {
      expect_true(any(m$mmMatrix[, "type"] != "A"), label = paste(nm, "is outside the native subset only for its PLSc constructs"))
      next
    }
    native <- native + 1L
    o <- arwad:::aw_pls_run(s, matrix(seq_len(nrow(s$X)), ncol = 1L))
    p <- length(s$items)
    pJ <- p * length(s$cons)
    JJ <- length(s$cons)^2
    at <- cbind(s$items, s$cons[s$blk])
    expect_true(identical(o[1L, seq_len(p)], unname(m$outer_weights[at]), num.eq = FALSE), label = paste(nm, "weights"))
    expect_true(identical(o[1L, p + seq_len(pJ)], as.vector(unname(m$outer_loadings[s$items, s$cons])), num.eq = FALSE),
                label = paste(nm, "loadings, signed zeros included"))
    expect_true(identical(o[1L, p + pJ + seq_len(JJ)], as.vector(m$path_coef[s$cons, s$cons]), num.eq = FALSE),
                label = paste(nm, "paths"))
    expect_identical(as.integer(o[1L, p + pJ + 3L * JJ + 1L]), m$iterations, label = paste(nm, "iterations"))
    expect_true(identical(o[1L, p + pJ + 3L * JJ + 2L], m$weightDiff, num.eq = FALSE), label = paste(nm, "weight change"))
  }
  expect_gte(native, 50L)
})

test_that("aw_boot_pls() equals seminr::bootstrap_model() on at least 50 models", {
  skip_if_no_toolchain()
  skip_if_not_installed("seminr")
  fits <- aw_pls_fit_models()
  expect_gte(length(fits), 50L)
  exact <- c("boot_paths", "boot_loadings", "boot_weights", "boot_total_paths", "paths_descriptives",
             "loadings_descriptives", "weights_descriptives", "total_paths_descriptives", "boots", "seed")
  for (k in seq_along(fits)) {
    nm <- names(fits)[k]
    want <- suppressMessages(seminr::bootstrap_model(fits[[nm]], nboot = 3L, cores = 1L, seed = k))
    got <- aw_boot_pls(fits[[nm]], nboot = 3L, seed = k)
    expect_identical(got$native, !is.null(arwad:::aw_pls_spec(fits[[nm]])), label = paste(nm, "native"))
    for (f in exact) expect_true(identical(got[[f]], want[[f]], num.eq = FALSE), label = paste(nm, f))
    expect_identical(is.na(got$boot_HTMT), is.na(want$boot_HTMT), label = paste(nm, "HTMT pattern"))
    ok <- !is.na(want$boot_HTMT)
    expect_lte(max(0, abs(got$boot_HTMT[ok] - want$boot_HTMT[ok]) / abs(want$boot_HTMT[ok])), 4 * .Machine$double.eps,
               label = paste(nm, "HTMT within a few units in the last place"))
  }
  # The comparisons above are with native code, not with GNU R running the
  # kernel after a static fallback or a bailout.
  u <- arwad:::aw_pls_unit()
  expect_s3_class(u, "arwad_function")
  utils::capture.output(info <- aw_explain(u))
  expect_gt(sum(info$calls), 50L)
  expect_identical(sum(info$bailouts), 0L)
})

test_that("aw_boot_pls() leaves the random-number state as bootstrap_model() does, and hands other models to seminr", {
  skip_if_no_toolchain()
  skip_if_not_installed("seminr")
  m <- aw_pls_fit_models()[["mobi_ecsi_core"]]
  set.seed(77)
  want <- suppressMessages(seminr::bootstrap_model(m, nboot = 4L, cores = 1L))
  seed_want <- .Random.seed
  set.seed(77)
  got <- aw_boot_pls(m, nboot = 4L)
  expect_identical(.Random.seed, seed_want)
  expect_identical(got$seed, want$seed)
  expect_identical(got$boot_paths, want$boot_paths)
  sg <- summary(got)
  sw <- summary(want)
  for (f in c("bootstrapped_paths", "bootstrapped_weights", "bootstrapped_loadings", "bootstrapped_total_paths"))
    expect_identical(sg[[f]], sw[[f]], label = paste("summary()", f))
  mb <- suppressMessages(seminr::estimate_pls(seminr::mobi, seminr::constructs(
    seminr::composite("Image", seminr::multi_items("IMAG", 1:5), weights = seminr::mode_B),
    seminr::composite("Value", seminr::multi_items("PERV", 1:2))), seminr::relationships(seminr::paths(from = "Image", to = "Value"))))
  fb <- suppressMessages(aw_boot_pls(mb, nboot = 3L, seed = 1L))
  expect_false(fb$native)
  expect_identical(fb$boot_paths, suppressMessages(seminr::bootstrap_model(mb, nboot = 3L, cores = 1L, seed = 1L))$boot_paths)
})
