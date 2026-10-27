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
