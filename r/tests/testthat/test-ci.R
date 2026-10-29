# Bootstrap confidence intervals for PLS-SEM models (aw_pls_ci()), checked
# against seminr's summary() and specific_effect_significance(), and the bias
# correction against boot::boot.ci() (Davison and Hinkley's implementation).

ci_model <- function() {
  mm <- seminr::constructs(
    seminr::composite("Image", seminr::multi_items("IMAG", 1:5)), seminr::composite("Expectation", seminr::multi_items("CUEX", 1:3)),
    seminr::composite("Value", seminr::multi_items("PERV", 1:2)), seminr::composite("Satisfaction", seminr::multi_items("CUSA", 1:3)),
    seminr::composite("Complaints", seminr::single_item("CUSCO")), seminr::composite("Loyalty", seminr::multi_items("CUSL", 1:3)))
  sm <- seminr::relationships(
    seminr::paths(from = c("Image", "Expectation"), to = c("Value", "Satisfaction")), seminr::paths(from = "Value", to = "Satisfaction"),
    seminr::paths(from = "Satisfaction", to = c("Complaints", "Loyalty")), seminr::paths(from = "Complaints", to = "Loyalty"))
  suppressMessages(seminr::estimate_pls(seminr::mobi, mm, sm))
}

# The columns aw_pls_ci() shares with summary(): estimate, mean, SD, t, limits.
ci_shared <- c(1L, 2L, 4L, 5L, 7L, 8L)

test_that("aw_pls_ci(type = \"percentile\") equals seminr's summary() on every test model", {
  skip_if_no_toolchain()
  skip_if_not_installed("seminr")
  fits <- aw_pls_fit_models()
  expect_gte(length(fits), 50L)
  tabs <- c(paths = "bootstrapped_paths", total_paths = "bootstrapped_total_paths", total_indirect_paths = "bootstrapped_total_indirect_paths",
            loadings = "bootstrapped_loadings", weights = "bootstrapped_weights", HTMT = "bootstrapped_HTMT")
  covered <- 0L
  for (k in seq_along(fits)) {
    nm <- names(fits)[k]
    # From seminr 2.6.0 on, a weak consistent-PLS model can keep fewer than two
    # of its 20 resamples (the others inadmissible): seminr then stops, and so
    # does aw_boot_pls(), which hands that case to it. Nothing to compare.
    utils::capture.output(b <- tryCatch(suppressMessages(aw_boot_pls(fits[[nm]], nboot = 20L, seed = k)), error = function(e) e))
    if (!inherits(b, "boot_seminr_model")) {
      expect_true(arwad:::aw_seminr_260() && any(fits[[nm]]$mmMatrix[, "type"] == "C"),
                  label = paste(nm, "is a consistent-PLS model under seminr 2.6.0"))
      next
    }
    covered <- covered + 1L
    for (alpha in c(0.05, 0.10)) {
      got <- aw_pls_ci(b, alpha = alpha, type = "percentile")
      want <- summary(b, alpha = alpha)
      for (t in names(tabs)) {
        w <- want[[tabs[[t]]]]
        if (!is.matrix(w)) {
          expect_identical(nrow(got[[t]]), 0L, label = paste(nm, t, "empty"))
          next
        }
        # seminr reports total indirect effects at 95% whatever alpha is.
        cols <- if (t == "total_indirect_paths" && alpha != 0.05) 1:4 else 1:6
        expect_identical(rownames(got[[t]]), rownames(w), label = paste(nm, t, "rows"))
        expect_true(identical(unname(got[[t]][, ci_shared[cols]]), unname(w[, cols]), num.eq = FALSE),
                    label = paste(nm, t, "alpha", alpha))
      }
    }
  }
  expect_gte(covered, 115L)
})

test_that("the bias correction is boot::boot.ci()'s with zero acceleration", {
  skip_if_no_toolchain()
  skip_if_not_installed("seminr")
  skip_if_not_installed("boot")
  m <- ci_model()
  b <- aw_boot_pls(m, nboot = 999L, seed = 21L)
  for (alpha in c(0.05, 0.10)) {
    ci <- aw_pls_ci(b, alpha = alpha)
    for (t in c("paths", "total_paths", "weights")) {
      tab <- ci[[t]]
      arr <- switch(t, paths = b$boot_paths, total_paths = b$boot_total_paths, weights = b$boot_weights)
      for (r in seq_len(nrow(tab))) {
        p <- strsplit(rownames(tab)[r], "  ->  ", fixed = TRUE)[[1L]]
        x <- arr[p[1L], p[2L], ]
        # A single indicator's weight differs only by rounding: percentile
        # limits by design (checked below).
        if (arwad:::aw_ci_flat(x)) next
        est <- tab[r, "Original Est."]
        z0 <- stats::qnorm(sum(x < est) / length(x))
        lv <- stats::pnorm(2 * z0 + stats::qnorm(c(alpha / 2, 1 - alpha / 2)))
        # The limits are the type-7 quantiles at the bias-corrected levels ...
        expect_identical(unname(tab[r, 7:8]), stats::quantile(x, lv, type = 7, names = FALSE), label = paste(t, r, "levels"))
        # ... and those levels are boot.ci()'s: boot's own interpolation at
        # them gives boot.ci()'s bias-corrected limits.
        bo <- structure(list(t0 = est, t = matrix(x, ncol = 1L), R = length(x), sim = "ordinary", stype = "i", data = matrix(0, 10L, 1L),
                             statistic = function(d, i) 0, call = quote(boot()), weights = rep(0.1, 10L), strata = rep(1, 10L)),
                        class = "boot")
        ref <- boot::boot.ci(bo, conf = 1 - alpha, type = "bca", L = rep(c(1, -1), 5L))$bca[4:5]
        expect_equal(unname(boot:::norm.inter(x, lv)[, 2L]), unname(ref), tolerance = 1e-12, label = paste(t, r, "boot.ci"))
      }
    }
  }
})

test_that("the limits follow the rules for unbiased, one-sided and rounding-only bootstrap values", {
  x <- c(0.2, 0.5, 0.1, 0.9, 0.4, 0.7, 0.3, 0.8, 0.6, 0.0)
  # Half below the estimate: z0 = 0 and the BC interval is the percentile interval.
  expect_identical(arwad:::aw_ci_limits(x, 0.45, 0.05, "bc")$lim, stats::quantile(x, c(0.025, 0.975), type = 7, names = FALSE))
  # An estimate below every resample: the extreme resample, flagged.
  r <- arwad:::aw_ci_limits(x, -1, 0.05, "bc")
  expect_identical(r$lim, c(0, 0))
  expect_true(r$outside)
  # Values that differ only by rounding: percentile limits, no skewness.
  one <- 1 + c(0, 1, -1, 0, 2) * .Machine$double.eps
  expect_identical(arwad:::aw_ci_limits(one, 1, 0.05, "bc")$lim, stats::quantile(one, c(0.025, 0.975), type = 7, names = FALSE))
  expect_false(arwad:::aw_ci_limits(one, 1, 0.05, "bc")$outside)
  expect_identical(arwad:::aw_ci_skew(one), NA_real_)
  expect_equal(arwad:::aw_ci_skew(c(0, 0, 0, 1)), 1.1547005383792515)
})

test_that("aw_pls_ci() computes specific indirect effects as seminr does, and uses alpha for every table", {
  skip_if_no_toolchain()
  skip_if_not_installed("seminr")
  m <- ci_model()
  b <- aw_boot_pls(m, nboot = 300L, seed = 5L)
  ch <- list(c("Image", "Value", "Satisfaction"), c("Image", "Value", "Satisfaction", "Loyalty"))
  got <- aw_pls_ci(b, type = "percentile", indirect = ch)$specific_indirect_paths
  for (k in seq_along(ch)) {
    c1 <- ch[[k]]
    want <- seminr::specific_effect_significance(b, from = c1[1L], through = c1[-c(1L, length(c1))], to = c1[length(c1)], alpha = 0.05)
    expect_true(identical(unname(got[k, ci_shared]), unname(want[1L, 1:6]), num.eq = FALSE), label = paste("chain", k))
  }
  expect_identical(rownames(got), c("Image  ->  Value  ->  Satisfaction", "Image  ->  Value  ->  Satisfaction  ->  Loyalty"))
  # Total indirect effects at 90%: summary() stays at 95%, aw_pls_ci() does not.
  ti <- aw_pls_ci(b, alpha = 0.10, type = "percentile")$total_indirect_paths
  x <- b$boot_total_paths["Image", "Loyalty", ] - b$boot_paths["Image", "Loyalty", ]
  expect_identical(unname(ti["Image  ->  Loyalty", 7:8]), stats::quantile(x, c(0.05, 0.95), type = 7, names = FALSE))
  expect_identical(colnames(ti)[7:8], c("5% CI", "95% CI"))
  expect_error(aw_pls_ci(b, indirect = list(c("Image", "Value", "Loyalty"))), "no path from Value to Loyalty")
  expect_error(aw_pls_ci(b, indirect = list(c("Image", "Value"))), "at least three constructs")
})

test_that("aw_pls_ci() gives the same tables for seminr's and Arwad's bootstrap, and checks its input", {
  skip_if_no_toolchain()
  skip_if_not_installed("seminr")
  m <- ci_model()
  want <- aw_pls_ci(suppressMessages(seminr::bootstrap_model(m, nboot = 200L, cores = 1L, seed = 9L)))
  got <- aw_pls_ci(aw_boot_pls(m, nboot = 200L, seed = 9L))
  for (t in c("paths", "total_paths", "total_indirect_paths", "loadings", "weights")) {
    expect_true(identical(got[[t]], want[[t]], num.eq = FALSE), label = t)
  }
  # HTMT agrees to within four units in the last place (ADR-0006); the t
  # statistic divides 1 - HTMT by a small standard deviation.
  expect_equal(got$HTMT, want$HTMT, tolerance = 1e-12)
  expect_identical(colnames(got$paths), c("Original Est.", "Bootstrap Mean", "Bias", "Bootstrap SD", "T Stat.", "Skewness",
                                          "2.5% BC CI", "97.5% BC CI"))
  expect_identical(unname(got$paths[, "Bias"]), unname(got$paths[, "Bootstrap Mean"] - got$paths[, "Original Est."]))
  expect_match(paste(utils::capture.output(print(got)), collapse = "\n"),
               "Bias-corrected percentile bootstrap confidence intervals, 95%, 200 resamples")
  expect_error(aw_pls_ci(m), "bootstrapped model")
  b <- aw_boot_pls(m, nboot = 50L, seed = 1L)
  for (a in list(0, 1, -0.1, c(0.05, 0.1), NA_real_, "0.05")) expect_error(aw_pls_ci(b, alpha = a), "'alpha'")
  expect_error(aw_pls_ci(b, indirect = c("Image", "Value", "Satisfaction")), "list of character vectors")
})

test_that("BCa: the jackknife equals seminr's estimates on every leave-one-out sample, and the limits follow Efron's formula", {
  skip_if_no_toolchain()
  skip_if_not_installed("seminr")
  fits <- aw_pls_fit_models()
  designs <- aw_pls_models()
  chain <- c("Image", "Value", "Satisfaction")
  # Mode A composites, a Mode B construct, and all constructs reflective.
  for (nm in c("mobi_ecsi_core", "mobi_ecsi_image_modeB", "mobi_ecsi_reflective")) {
    m <- fits[[nm]]
    d <- designs[[nm]]
    n <- nrow(m$rawdata)
    b <- suppressMessages(aw_boot_pls(m, nboot = 200L, seed = 5L))
    ci <- aw_pls_ci(b, type = "bca", indirect = list(chain))
    expect_identical(ci$jackknife, n)
    expect_identical(colnames(ci$paths)[7:8], c("2.5% BCa CI", "97.5% BCa CI"))
    # seminr's own estimates with each case left out (inadmissible ones too,
    # as estimate_pls() returns them).
    jk <- lapply(seq_len(n), function(i) suppressWarnings(suppressMessages(
      seminr::estimate_pls(m$rawdata[-i, , drop = FALSE], d$mm, d$sm, maxIt = d$maxIt))))
    bm <- m
    class(bm) <- c("pls_model", "seminr_model")
    spec <- arwad:::aw_pls_spec(bm)
    rows <- arwad:::aw_pls_jack(spec)
    cons <- spec$cons
    J <- length(cons)
    p <- length(spec$items)
    at <- cbind(spec$items, cons[spec$blk])
    for (i in seq_len(n)) {
      expect_true(identical(rows[i, seq_len(p)], unname(jk[[i]]$outer_weights[at]), num.eq = FALSE), label = paste(nm, i, "weights"))
      expect_true(identical(rows[i, p + seq_len(p * J)], as.vector(unname(jk[[i]]$outer_loadings[spec$items, cons])), num.eq = FALSE),
                  label = paste(nm, i, "loadings"))
      expect_true(identical(rows[i, p + p * J + seq_len(J * J)], as.vector(jk[[i]]$path_coef[cons, cons]), num.eq = FALSE),
                  label = paste(nm, i, "paths"))
    }
    # The limits from seminr's jackknife and Arwad's bootstrap by Efron's
    # formula, written out here.
    bca <- function(x, est, j) {
      dd <- mean(j) - j
      a <- sum(dd^3) / (6 * sum(dd^2)^1.5)
      z0 <- stats::qnorm(sum(x < est) / length(x))
      z <- stats::qnorm(c(0.025, 0.975))
      stats::quantile(x, stats::pnorm(z0 + (z0 + z) / (1 - a * (z0 + z))), type = 7, names = FALSE)
    }
    for (r in rownames(ci$paths)) {
      pp <- strsplit(r, "  ->  ", fixed = TRUE)[[1L]]
      j <- vapply(jk, function(f) f$path_coef[pp[1L], pp[2L]], 1)
      expect_identical(unname(ci$paths[r, 7:8]), bca(b$boot_paths[pp[1L], pp[2L], ], m$path_coef[pp[1L], pp[2L]], j),
                       label = paste(nm, r, "BCa limits"))
    }
    for (r in rownames(ci$loadings)) {
      pp <- strsplit(r, "  ->  ", fixed = TRUE)[[1L]]
      x <- b$boot_loadings[pp[1L], pp[2L], ]
      if (diff(range(x)) <= 1e-12 * max(abs(x))) next
      j <- vapply(jk, function(f) f$outer_loadings[pp[1L], pp[2L]], 1)
      expect_identical(unname(ci$loadings[r, 7:8]), bca(x, m$outer_loadings[pp[1L], pp[2L]], j), label = paste(nm, r, "BCa limits"))
    }
    j <- vapply(jk, function(f) f$path_coef[chain[1L], chain[2L]] * f$path_coef[chain[2L], chain[3L]], 1)
    x <- b$boot_paths[chain[1L], chain[2L], ] * b$boot_paths[chain[2L], chain[3L], ]
    expect_identical(unname(ci$specific_indirect_paths[1L, 7:8]),
                     bca(x, m$path_coef[chain[1L], chain[2L]] * m$path_coef[chain[2L], chain[3L]], j), label = paste(nm, "indirect BCa limits"))
  }
})

test_that("BCa with zero acceleration is the BC interval, and needs a model in the native subset", {
  skip_if_no_toolchain()
  skip_if_not_installed("seminr")
  x <- stats::qnorm(seq(0.001, 0.999, length.out = 501)) * 0.1 + 0.3
  for (t0 in c(0.25, 0.3, 0.37)) {
    expect_equal(arwad:::aw_ci_limits(x, t0, 0.05, "bca", 0)$lim, arwad:::aw_ci_limits(x, t0, 0.05, "bc")$lim, tolerance = 1e-14)
  }
  # The estimate outside every resample: the extreme resamples, as for BC.
  expect_identical(arwad:::aw_ci_limits(x, 1, 0.05, "bca", 0.1)$lim, rep(max(x), 2L))
  expect_identical(arwad:::aw_ci_accel(rep(0.4, 10L)), 0)
  mm <- seminr::constructs(seminr::composite("Image", seminr::multi_items("IMAG", 1:5)),
                           seminr::composite("Value", seminr::multi_items("PERV", 1:2)))
  sm <- seminr::relationships(seminr::paths(from = "Image", to = "Value"))
  mf <- suppressMessages(seminr::estimate_pls(seminr::mobi, mm, sm, inner_weights = seminr::path_factorial))
  bf <- suppressMessages(aw_boot_pls(mf, nboot = 20L, seed = 1L))
  expect_error(aw_pls_ci(bf, type = "bca"), "outside it")
})

test_that("BCa works with two-stage interaction terms: the jackknife equals seminr's leave-one-out estimates", {
  skip_if_no_toolchain()
  skip_if_not_installed("seminr")
  designs <- aw_pls_interaction_models()
  fits <- aw_pls_fit_interaction_models()
  for (nm in c("mobi_ie_between", "mobi_two_terms")) {
    m <- fits[[nm]]
    d <- designs[[nm]]
    n <- nrow(m$rawdata)
    b <- suppressMessages(aw_boot_pls(m, nboot = 100L, seed = 4L))
    expect_true(b$native)
    ci <- aw_pls_ci(b, type = "bca")
    expect_identical(ci$jackknife, n)
    expect_true("Image*Expectation  ->  Satisfaction" %in% rownames(ci$paths))
    bm <- m
    class(bm) <- c("pls_model", "seminr_model")
    spec <- arwad:::aw_pls_spec(bm)
    rows <- arwad:::aw_pls_jack(spec)
    cons <- spec$cons
    J <- length(cons)
    p <- length(spec$items)
    at <- cbind(spec$items, cons[spec$blk])
    # Every tenth leave-one-out sample, estimated by seminr itself (both
    # stages, with the model's maxIt and stopCriterion).
    for (i in seq(1L, n, by = 10L)) {
      f <- suppressMessages(seminr::estimate_pls(m$rawdata[-i, , drop = FALSE], d$mm, d$sm, maxIt = d$maxIt, stopCriterion = d$stop))
      expect_true(identical(rows[i, seq_len(p)], unname(f$outer_weights[at]), num.eq = FALSE), label = paste(nm, i, "weights"))
      expect_true(identical(rows[i, p + seq_len(p * J)], as.vector(unname(f$outer_loadings[spec$items, cons])), num.eq = FALSE),
                  label = paste(nm, i, "loadings"))
      expect_true(identical(rows[i, p + p * J + seq_len(J * J)], as.vector(f$path_coef[cons, cons]), num.eq = FALSE),
                  label = paste(nm, i, "paths"))
    }
  }
})
