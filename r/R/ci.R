# Bootstrap confidence intervals for PLS-SEM models: the percentile interval
# and the bias-corrected (BC) percentile interval that the PLS-SEM Primer
# recommends reporting. Plain R: the work is a few quantiles per coefficient.
# See docs/adr/0007-pls-sem-confidence-intervals.md.

# The limits of one interval from the bootstrap values x of a coefficient
# whose estimate is t0. BC: z0 is the normal quantile of the share of
# resamples strictly below t0, and the levels move to
# pnorm(2 * z0 + qnorm(level)) (Efron, 1982; boot::boot.ci(type = "bca") with
# zero acceleration). When z0 is 0 the levels stay as they are, so the BC
# interval is then exactly the percentile interval. The quantiles are
# quantile(type = 7), as seminr's summary() takes them. Returns the two
# limits and whether the estimate lies outside the bootstrap values (where
# z0 is infinite and the limits are the extreme resamples).
aw_ci_limits <- function(x, t0, alpha, type) {
  x <- x[!is.na(x)]
  if (!length(x) || is.na(t0)) return(list(lim = c(NA_real_, NA_real_), outside = FALSE))
  p <- c(alpha / 2, 1 - alpha / 2)
  outside <- FALSE
  if (type == "bc" && !aw_ci_flat(x)) {
    z0 <- stats::qnorm(sum(x < t0) / length(x))
    if (z0 != 0) p <- stats::pnorm(2 * z0 + stats::qnorm(p))
    outside <- !is.finite(z0)
  }
  list(lim = stats::quantile(x, p, type = 7, names = FALSE), outside = outside)
}

# Bootstrap values that differ only by rounding, such as the loading and
# weight of a single-indicator construct (1 in every resample, give or take
# the last bits): they carry no sampling information, so they get no bias
# correction and no skewness.
aw_ci_flat <- function(x) diff(range(x)) <= 1e-12 * max(abs(x))

# Skewness of the bootstrap values, m3 / m2^1.5 with central moments over
# the values (NA when they differ only by rounding).
aw_ci_skew <- function(x) {
  x <- x[!is.na(x)]
  if (!length(x) || aw_ci_flat(x)) return(NA_real_)
  d <- x - mean(x)
  mean(d^3) / mean(d^2)^1.5
}

# One table: estimate, bootstrap mean, bias, standard deviation and t
# statistic (as given), skewness, and the two limits, for every row.
aw_ci_table <- function(rn, est, mu, sdv, tstat, draws, alpha, type, outside) {
  lims <- lapply(seq_along(draws), function(r) aw_ci_limits(draws[[r]], est[r], alpha, type))
  lab <- paste0(vapply(100 * c(alpha / 2, 1 - alpha / 2), format, "", digits = 6), if (type == "bc") "% BC CI" else "% CI")
  out <- cbind(est, mu, mu - est, sdv, tstat, vapply(draws, aw_ci_skew, 1),
               matrix(as.numeric(unlist(lapply(lims, `[[`, "lim"))), ncol = 2L, byrow = TRUE))
  dimnames(out) <- list(rn, c("Original Est.", "Bootstrap Mean", "Bias", "Bootstrap SD", "T Stat.", "Skewness", lab))
  hit <- vapply(lims, `[[`, NA, "outside")
  if (any(hit)) outside$rows <- c(outside$rows, rn[hit])
  out
}

#' Bias-corrected bootstrap confidence intervals for a PLS-SEM model
#'
#' Confidence intervals for every coefficient of a bootstrapped PLS-SEM
#' model: path coefficients, total and total indirect effects, loadings,
#' weights and HTMT ratios, and, on request, specific indirect effects. It
#' works on a bootstrap from [aw_boot_pls()] or from
#' `seminr::bootstrap_model()`.
#'
#' The default is the bias-corrected (BC) percentile interval (Efron, 1982;
#' Efron and Tibshirani, 1993, section 14.3, with zero acceleration; Davison
#' and Hinkley, 1997, section 5.3), the interval the PLS-SEM Primer
#' recommends reporting (Hair, Hult, Ringle and Sarstedt, 4th ed.,
#' pp. 164-166). With `z0 = qnorm(share of resamples below the estimate)`,
#' its limits are the bootstrap quantiles at levels
#' `pnorm(2 * z0 + qnorm(alpha / 2))` and `pnorm(2 * z0 + qnorm(1 - alpha / 2))`.
#' `z0` is the one `boot::boot.ci(type = "bca")` uses, and so are the levels
#' when the acceleration is zero (up to rounding in the last bits). The
#' quantiles are taken as `seminr`'s `summary()` takes its percentile limits,
#' with `quantile(type = 7)`: with `type = "percentile"` the limits are
#' `summary()`'s, and a BC interval is the percentile interval when exactly
#' half the resamples fall below the estimate. Bootstrap values that differ
#' only by rounding, such as the loading of a single-indicator construct,
#' get their percentile limits and no skewness.
#'
#' Unlike `summary()` of `seminr` (2.5.0 and 2.6.0), which reports total indirect effects
#' at 95% whatever `alpha` is, every table here uses `alpha`.
#'
#' @param boot A bootstrapped model, from [aw_boot_pls()] or
#'   `seminr::bootstrap_model()`.
#' @param alpha The two-sided error level: 0.05 gives 95% intervals. A
#'   one-sided test at 5%, as the Primer uses for directional hypotheses and
#'   for HTMT, reads the matching limit of the 90% interval (`alpha = 0.10`).
#' @param type `"bc"`, the bias-corrected percentile interval (the default),
#'   or `"percentile"`.
#' @param indirect Specific indirect effects to add, as a list of construct
#'   chains, each from the antecedent through the mediators to the outcome:
#'   `list(c("Image", "Value", "Satisfaction"))`. The effect is the product
#'   of the path coefficients along the chain in every resample, as
#'   `seminr::specific_effect_significance()` computes it.
#' @return A list of class `aw_pls_ci` with the tables `paths`,
#'   `total_paths`, `total_indirect_paths`, `loadings`, `weights` and `HTMT`
#'   (and `specific_indirect_paths` when `indirect` is given), rows as in
#'   `summary()` of the bootstrapped model, and `alpha`, `type` and `nboot`.
#'   Each table has the columns `Original Est.`, `Bootstrap Mean`, `Bias`
#'   (mean minus estimate), `Bootstrap SD`, `T Stat.` (as `summary()` gives
#'   it: for HTMT, one minus the estimate over the standard deviation),
#'   `Skewness` of the bootstrap values (the Primer reserves the BCa
#'   interval for skewness beyond plus or minus 2), and the lower and upper
#'   limits.
#' @references
#' Davison, A. C., & Hinkley, D. V. (1997). *Bootstrap methods and their
#' application*. Cambridge University Press.
#'
#' Efron, B. (1982). *The jackknife, the bootstrap and other resampling
#' plans*. SIAM.
#'
#' Efron, B., & Tibshirani, R. J. (1993). *An introduction to the bootstrap*.
#' Chapman & Hall.
#' @export
#' @examplesIf requireNamespace("seminr", quietly = TRUE)
#' library(seminr)
#' mm <- constructs(composite("Image", multi_items("IMAG", 1:5)),
#'                  composite("Value", multi_items("PERV", 1:2)),
#'                  composite("Satisfaction", multi_items("CUSA", 1:3)))
#' sm <- relationships(paths(from = "Image", to = c("Value", "Satisfaction")),
#'                     paths(from = "Value", to = "Satisfaction"))
#' model <- estimate_pls(mobi, mm, sm)
#' boot <- aw_boot_pls(model, nboot = 500, seed = 123)
#' ci <- aw_pls_ci(boot, indirect = list(c("Image", "Value", "Satisfaction")))
#' ci$paths
#' ci$specific_indirect_paths
aw_pls_ci <- function(boot, alpha = 0.05, type = c("bc", "percentile"), indirect = NULL) {
  if (!inherits(boot, "boot_seminr_model")) {
    stop("'boot' must be a bootstrapped model from aw_boot_pls() or seminr::bootstrap_model()")
  }
  if (!requireNamespace("seminr", quietly = TRUE)) stop("aw_pls_ci() needs the seminr package")
  if (!is.numeric(alpha) || length(alpha) != 1L || is.na(alpha) || alpha <= 0 || alpha >= 1) {
    stop("'alpha' must be a single number between 0 and 1")
  }
  type <- match.arg(type)
  if (!is.null(indirect) && (!is.list(indirect) || !all(vapply(indirect, is.character, NA)))) {
    stop("'indirect' must be a list of character vectors of construct names")
  }
  s <- summary(boot, alpha = alpha)
  bp <- boot$boot_paths
  bt <- boot$boot_total_paths
  get <- list(
    paths = list(s$bootstrapped_paths, function(a, b) bp[a, b, ]),
    total_paths = list(s$bootstrapped_total_paths, function(a, b) bt[a, b, ]),
    total_indirect_paths = list(s$bootstrapped_total_indirect_paths, function(a, b) bt[a, b, ] - bp[a, b, ]),
    loadings = list(s$bootstrapped_loadings, function(a, b) boot$boot_loadings[a, b, ]),
    weights = list(s$bootstrapped_weights, function(a, b) boot$boot_weights[a, b, ]),
    HTMT = list(s$bootstrapped_HTMT, function(a, b) boot$boot_HTMT[a, b, ]))
  outside <- new.env()
  outside$rows <- character()
  out <- lapply(get, function(g) {
    tab <- g[[1L]]
    # Without indirect effects seminr gives the text "No indirect effects":
    # an empty table here.
    if (!is.matrix(tab) || !nrow(tab)) return(aw_ci_table(character(), numeric(), numeric(), numeric(), numeric(), list(), alpha, type, outside))
    parts <- strsplit(rownames(tab), "  ->  ", fixed = TRUE)
    draws <- lapply(parts, function(p) g[[2L]](p[1L], p[2L]))
    aw_ci_table(rownames(tab), unname(tab[, "Original Est."]), unname(tab[, "Bootstrap Mean"]), unname(tab[, "Bootstrap SD"]),
                unname(tab[, "T Stat."]), draws, alpha, type, outside)
  })
  if (length(indirect)) {
    cons <- boot$constructs
    sm <- boot$smMatrix
    pc <- boot$path_coef
    est <- numeric(length(indirect))
    draws <- vector("list", length(indirect))
    for (k in seq_along(indirect)) {
      ch <- indirect[[k]]
      if (length(ch) < 3L || !all(ch %in% cons)) {
        stop("each element of 'indirect' must name at least three constructs of the model, from antecedent to outcome")
      }
      for (i in seq_len(length(ch) - 1L)) {
        if (!any(sm[, "source"] == ch[i] & sm[, "target"] == ch[i + 1L])) {
          stop(sprintf("the model has no path from %s to %s", ch[i], ch[i + 1L]))
        }
        # Left to right, as seminr::specific_effect_significance() multiplies.
        est[k] <- if (i == 1L) pc[ch[1L], ch[2L]] else est[k] * pc[ch[i], ch[i + 1L]]
        draws[[k]] <- if (i == 1L) bp[ch[1L], ch[2L], ] else draws[[k]] * bp[ch[i], ch[i + 1L], ]
      }
    }
    m <- vapply(draws, mean, 1)
    sdv <- vapply(draws, stats::sd, 1)
    out$specific_indirect_paths <- aw_ci_table(vapply(indirect, paste, "", collapse = "  ->  "), est, m, sdv, est / sdv, draws,
                                               alpha, type, outside)
  }
  if (length(outside$rows)) {
    warning(sprintf("the estimate lies outside its bootstrap values for %s; the bias-corrected limits are the extreme resamples",
                    paste(unique(outside$rows), collapse = ", ")), call. = FALSE)
  }
  out$alpha <- alpha
  out$type <- type
  out$nboot <- dim(bp)[3L]
  class(out) <- "aw_pls_ci"
  out
}

#' @export
print.aw_pls_ci <- function(x, digits = 3L, ...) {
  what <- if (x$type == "bc") "Bias-corrected percentile" else "Percentile"
  cat(sprintf("%s bootstrap confidence intervals, %s%%, %d resamples\n", what,
              format(100 * (1 - x$alpha), digits = 6, trim = TRUE), x$nboot))
  for (nm in intersect(c("paths", "total_paths", "total_indirect_paths", "specific_indirect_paths", "loadings", "weights", "HTMT"),
                       names(x))) {
    if (!nrow(x[[nm]])) {
      cat("\n", nm, ": none\n", sep = "")
      next
    }
    cat("\n", nm, ":\n", sep = "")
    print(round(x[[nm]], digits))
  }
  invisible(x)
}
