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
  set.seed(20261027)
  for (i in seq_len(25L)) {
    n <- c(15L, 40L, 120L, 400L, 1000L)[(i - 1L) %% 5L + 1L]
    k <- (i - 1L) %% 5L + 2L
    X <- cbind(1, matrix(stats::rnorm(n * (k - 1L)) * 10^((i %% 4L) - 1L), n, k - 1L))
    y <- as.vector(X %*% stats::rnorm(k) + stats::rnorm(n))
    out[[paste0("synthetic_", i)]] <- list(X = X, y = y)
  }
  out
}

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

test_that("a rank-deficient design is left to R, which pivots", {
  skip_if_no_toolchain()
  cf <- aw_compile(function(X, y) .lm.fit(X, y)$coefficients)
  X <- cbind(1, 1:6, 2 * (1:6))
  y <- c(1, 3, 2, 5, 4, 6)
  expect_identical(cf(X, y), .lm.fit(X, y)$coefficients)
  expect_identical(sum(aw_stats(cf)$bailouts), 1L)
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
