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
  for (k in seq_along(fits)) {
    nm <- names(fits)[k]
    b <- suppressMessages(aw_boot_pls(fits[[nm]], nboot = 20L, seed = k))
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
