# Phase 2 engines are validated on at least 50 datasets: the numeric data
# frames of R's datasets package (response = first numeric column, design =
# intercept plus the other numeric columns) and seeded synthetic designs.
aw_designs <- function() {
  out <- list()
  items <- utils::data(package = "datasets")$results[, "Item"]
  for (nm in items) {
    d <- tryCatch(get(nm, envir = asNamespace("datasets")), error = function(e) NULL)
    if (!is.data.frame(d)) next
    num <- d[vapply(d, is.numeric, logical(1))]
    num <- num[stats::complete.cases(num), , drop = FALSE]
    if (ncol(num) < 2L || nrow(num) < ncol(num) + 3L) next
    X <- cbind(1, as.matrix(num[-1L]))
    out[[nm]] <- list(X = matrix(as.double(X), nrow(X)), y = as.double(num[[1L]]))
    if (length(out) >= 30L) break
  }
  seed <- get0(".Random.seed", envir = globalenv(), inherits = FALSE)
  set.seed(20261027)
  for (i in seq_len(25L)) {
    n <- c(15L, 40L, 120L, 400L, 1000L)[(i - 1L) %% 5L + 1L]
    k <- (i - 1L) %% 5L + 2L
    X <- cbind(1, matrix(stats::rnorm(n * (k - 1L)) * 10^((i %% 4L) - 1L), n, k - 1L))
    y <- as.vector(X %*% stats::rnorm(k) + stats::rnorm(n))
    out[[paste0("synthetic_", i)]] <- list(X = X, y = y)
  }
  if (!is.null(seed)) assign(".Random.seed", seed, envir = globalenv())
  out
}

# The same designs with a response for each GLM family: the response plus
# seeded noise of its own spread, split at the median (binomial; without the
# noise most designs separate perfectly), shifted and rounded to counts
# (poisson), as is (gaussian).
aw_glm_response <- function(y, family) {
  switch(family,
    binomial = {
      seed <- get0(".Random.seed", envir = globalenv(), inherits = FALSE)
      set.seed(length(y))
      z <- y + stats::rnorm(length(y), sd = stats::sd(y))
      if (!is.null(seed)) assign(".Random.seed", seed, envir = globalenv())
      as.double(z > stats::median(z))
    },
    poisson = round(y - min(y)),
    gaussian = y)
}

# Value and warnings of an expression.
aw_with_warnings <- function(expr) {
  w <- character()
  v <- withCallingHandlers(expr, warning = function(cnd) {
    w <<- c(w, conditionMessage(cnd))
    invokeRestart("muffleWarning")
  })
  list(value = v, warnings = w)
}

# PLS-SEM models for the seminr comparison: models on seminr's own datasets
# (ECSI mobile phone data, the corporate reputation data of Hair et al.'s
# Primer, the influencer data) and seeded synthetic models with 2 to 7
# constructs, 1 to 6 indicators each, n from 40 to 800, Likert-type and
# rescaled data, shuffled declaration and path orders, Mode A composites,
# models with formative (Mode B) constructs, including the Primer's extended
# corporate reputation model and a Mode B version of every second synthetic
# model, models with reflective constructs, which seminr estimates by
# consistent PLS (all reflective; reflective next to Mode A composites, which
# seminr then corrects too; reflective next to Mode B; single-indicator
# reflective constructs), and seminr's default maxIt (300) or the 3,000 the
# Primer recommends.
aw_pls_models <- function() {
  if (!requireNamespace("seminr", quietly = TRUE)) return(list())
  blk <- function(nm, items, refl, form) {
    if (refl) seminr::reflective(nm, items) else if (form) seminr::composite(nm, items, weights = seminr::mode_B) else seminr::composite(nm, items)
  }
  mm <- function(blocks, refl = rep(FALSE, length(blocks)), form = rep(FALSE, length(blocks))) {
    do.call(seminr::constructs, unname(Map(blk, names(blocks), blocks, refl, form)))
  }
  sm <- function(...) {
    e <- rbind(...)
    do.call(seminr::relationships, lapply(seq_len(nrow(e)), function(r) seminr::paths(from = e[r, 1L], to = e[r, 2L])))
  }
  it <- function(stem, k) paste0(stem, k)
  mobi <- seminr::mobi
  ecsi <- list(Image = it("IMAG", 1:5), Expectation = it("CUEX", 1:3), Value = it("PERV", 1:2), Satisfaction = it("CUSA", 1:3))
  ecsi_sm <- sm(c("Image", "Value"), c("Expectation", "Value"), c("Image", "Satisfaction"), c("Expectation", "Satisfaction"),
                c("Value", "Satisfaction"))
  full <- list(Image = it("IMAG", 1:5), Expectation = it("CUEX", 1:3), Quality = it("PERQ", 1:7), Value = it("PERV", 1:2),
               Satisfaction = it("CUSA", 1:3), Complaints = "CUSCO", Loyalty = it("CUSL", 1:3))
  full_sm <- sm(c("Image", "Expectation"), c("Image", "Satisfaction"), c("Image", "Loyalty"), c("Expectation", "Quality"),
                c("Expectation", "Value"), c("Expectation", "Satisfaction"), c("Quality", "Value"), c("Quality", "Satisfaction"),
                c("Value", "Satisfaction"), c("Satisfaction", "Complaints"), c("Satisfaction", "Loyalty"), c("Complaints", "Loyalty"))
  cr <- list(COMP = it("comp_", 1:3), LIKE = it("like_", 1:3), CUSA = "cusa", CUSL = it("cusl_", 1:3))
  cr_sm <- sm(c("COMP", "CUSA"), c("LIKE", "CUSA"), c("COMP", "CUSL"), c("LIKE", "CUSL"), c("CUSA", "CUSL"))
  crx <- c(list(QUAL = it("qual_", 1:8), PERF = it("perf_", 1:5), CSOR = it("csor_", 1:5), ATTR = it("attr_", 1:3)), cr)
  crx_sm <- sm(c("QUAL", "COMP"), c("PERF", "COMP"), c("CSOR", "COMP"), c("ATTR", "COMP"), c("QUAL", "LIKE"), c("PERF", "LIKE"),
               c("CSOR", "LIKE"), c("ATTR", "LIKE"), c("COMP", "CUSA"), c("LIKE", "CUSA"), c("COMP", "CUSL"), c("LIKE", "CUSL"),
               c("CUSA", "CUSL"))
  inf <- list(SIC = it("sic_", 1:7), PQ = it("pq_", 1:4), PL = it("pl_", 1:4), PI = it("pi_", 1:5), WTP = "wtp")
  inf_sm <- sm(c("SIC", "PQ"), c("SIC", "PL"), c("SIC", "PI"), c("PQ", "PI"), c("PL", "PI"), c("PI", "WTP"))
  out <- list(
    mobi_ecsi_core = list(data = mobi, mm = mm(ecsi), sm = ecsi_sm, maxIt = 300L),
    mobi_ecsi_core_3000 = list(data = mobi, mm = mm(ecsi), sm = ecsi_sm, maxIt = 3000L),
    mobi_ecsi_reflective = list(data = mobi, mm = mm(ecsi, rep(TRUE, 4L)), sm = ecsi_sm, maxIt = 300L),
    mobi_ecsi_full = list(data = mobi, mm = mm(full), sm = full_sm, maxIt = 300L),
    corp_rep_simple = list(data = seminr::corp_rep_data, mm = mm(cr), sm = cr_sm, maxIt = 3000L),
    corp_rep_extended = list(data = seminr::corp_rep_data, mm = mm(crx), sm = crx_sm, maxIt = 300L),
    # The Primer's extended corporate reputation model: QUAL, PERF, CSOR and
    # ATTR are formative (Mode B).
    corp_rep_extended_modeB = list(data = seminr::corp_rep_data, mm = mm(crx, form = names(crx) %in% c("QUAL", "PERF", "CSOR", "ATTR")),
                                   sm = crx_sm, maxIt = 3000L),
    mobi_ecsi_image_modeB = list(data = mobi, mm = mm(ecsi, form = names(ecsi) == "Image"), sm = ecsi_sm, maxIt = 300L),
    mobi_ecsi_full_modeB = list(data = mobi, mm = mm(full, form = names(full) %in% c("Image", "Quality", "Loyalty")), sm = full_sm,
                                maxIt = 300L),
    corp_rep2_simple = list(data = seminr::corp_rep_data2, mm = mm(cr), sm = cr_sm, maxIt = 300L),
    influencer = list(data = seminr::influencer_data, mm = mm(inf), sm = inf_sm, maxIt = 300L),
    # Consistent PLS: the full ECSI model with every construct reflective
    # (Complaints has one indicator), and with four reflective constructs next
    # to three Mode A composites; the Primer's extended model with its
    # formative drivers and reflective outcomes.
    mobi_ecsi_full_reflective = list(data = mobi, mm = mm(full, rep(TRUE, 7L)), sm = full_sm, maxIt = 300L),
    mobi_ecsi_full_mixed = list(data = mobi, mm = mm(full, names(full) %in% c("Image", "Quality", "Satisfaction", "Loyalty")),
                                sm = full_sm, maxIt = 300L),
    corp_rep_extended_plsc = list(data = seminr::corp_rep_data, mm = mm(crx, refl = names(crx) %in% c("COMP", "LIKE", "CUSA", "CUSL"),
                                                                       form = names(crx) %in% c("QUAL", "PERF", "CSOR", "ATTR")),
                                  sm = crx_sm, maxIt = 3000L))
  seed <- get0(".Random.seed", envir = globalenv(), inherits = FALSE)
  set.seed(20261028)
  for (g in seq_len(46L)) {
    J <- sample(2:7, 1L)
    n <- sample(c(40L, 60L, 100L, 150L, 250L, 400L, 800L), 1L)
    k <- sample(c(1L, 2L, 3L, 3L, 4L, 4L, 5L, 6L), J, replace = TRUE)
    if (all(k == 1L)) k[1L] <- 3L
    E <- matrix(integer(), 0L, 2L)
    for (j in 2:J) {
      pr <- which(stats::runif(j - 1L) < 0.5)
      if (!length(pr)) pr <- sample.int(j - 1L, 1L)
      E <- rbind(E, cbind(pr, j))
    }
    if (!1L %in% E) E <- rbind(E, c(1L, J))
    eta <- matrix(0, n, J)
    for (j in seq_len(J)) {
      pr <- E[E[, 2L] == j, 1L]
      eta[, j] <- stats::rnorm(n) + if (length(pr)) drop(eta[, pr, drop = FALSE] %*% stats::runif(length(pr), -0.6, 0.8)) else 0
    }
    cols <- list()
    blocks <- list()
    for (j in seq_len(J)) {
      nm <- paste0("c", j, "_", seq_len(k[j]))
      blocks[[paste0("C", j)]] <- nm
      for (i in seq_len(k[j])) {
        repeat {
          x <- stats::runif(1L, 0.5, 0.95) * eta[, j] / stats::sd(eta[, j]) + stats::rnorm(n, 0, 0.6)
          if (g %% 3L == 0L) x <- pmin(pmax(round(4 + 1.2 * x), 1), 7)
          if (g %% 4L == 1L) x <- x * 10^stats::runif(1L, -1, 2) + stats::runif(1L, -50, 50)
          if (stats::sd(x) > 0) break
        }
        cols[[nm[i]]] <- x
      }
    }
    ord <- sample.int(J)
    e <- cbind(paste0("C", E[, 1L]), paste0("C", E[, 2L]))[sample.int(nrow(E)), , drop = FALSE]
    base <- list(data = as.data.frame(cols), mm = mm(blocks[ord]), sm = do.call(sm, lapply(seq_len(nrow(e)), function(r) e[r, ])),
                 maxIt = if (g %% 5L == 0L) 3000L else 300L)
    out[[sprintf("sim%02d_J%d_n%d", g, J, n)]] <- base
    # Every second model again with its odd-numbered multi-indicator
    # constructs formative (Mode B); chosen without drawing random numbers,
    # so the models above stay as they were.
    form <- k > 1L & seq_len(J) %% 2L == 1L
    if (g %% 2L == 0L && any(form)) {
      out[[sprintf("sim%02d_J%d_n%d_modeB", g, J, n)]] <- list(data = base$data, mm = mm(blocks[ord], form = form[ord]),
                                                              sm = base$sm, maxIt = base$maxIt)
    }
    # Consistent PLS, also without drawing random numbers: every third model
    # with all constructs reflective, the next with its odd-numbered constructs
    # reflective and the others Mode A composites, and every fourth Mode B
    # model with its other constructs reflective.
    refl <- seq_len(J) %% 2L == 1L
    if (g %% 3L == 2L) {
      out[[sprintf("sim%02d_J%d_n%d_plsc", g, J, n)]] <- list(data = base$data, mm = mm(blocks[ord], refl = rep(TRUE, J)),
                                                             sm = base$sm, maxIt = base$maxIt)
    }
    if (g %% 3L == 0L) {
      out[[sprintf("sim%02d_J%d_n%d_plsc_mixed", g, J, n)]] <- list(data = base$data, mm = mm(blocks[ord], refl = refl[ord]),
                                                                   sm = base$sm, maxIt = base$maxIt)
    }
    if (g %% 4L == 2L && any(form)) {
      out[[sprintf("sim%02d_J%d_n%d_modeB_plsc", g, J, n)]] <- list(data = base$data, mm = mm(blocks[ord], refl = !form[ord], form = form[ord]),
                                                                   sm = base$sm, maxIt = base$maxIt)
    }
  }
  if (is.null(seed)) rm(".Random.seed", envir = globalenv()) else assign(".Random.seed", seed, envir = globalenv())
  out
}

# The models of aw_pls_models(), estimated by seminr::estimate_pls().
aw_pls_fit_models <- function() {
  lapply(aw_pls_models(), function(d) suppressMessages(seminr::estimate_pls(d$data, d$mm, d$sm, maxIt = d$maxIt)))
}

# For a case seminr does not bootstrap (it stops when fewer than two
# resamples are left): aw_boot_pls() handed it to seminr and ended the same
# way (the same error, or the model returned as it was). The tests call
# seminr::bootstrap_model() in the test body, not in a helper: seminr sends
# its caller's environment to its worker processes, and under
# devtools::test() a helper's environment leads to the attached development
# package, which seminr's workers cannot load (seminr then stops).
expect_same_outcome <- function(got, want, label) {
  testthat::expect_identical(class(got), class(want), label = paste(label, "outcome"))
  if (inherits(want, "error")) {
    testthat::expect_identical(conditionMessage(got), conditionMessage(want), label = paste(label, "error"))
  } else {
    testthat::expect_false(got$native, label = paste(label, "native"))
    testthat::expect_null(got$boot_paths, label = paste(label, "not bootstrapped"))
  }
}
