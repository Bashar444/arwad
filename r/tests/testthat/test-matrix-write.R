# m[, j] <- v and m[i, ] <- v (Phase 2), and fallbacks that say so.

test_that("m[, j] <- v and m[i, ] <- v compile and match R", {
  skip_if_no_toolchain()
  standardise <- function(X) {
    n <- nrow(X)
    Z <- matrix(0, n, ncol(X))
    for (j in seq_len(ncol(X))) {
      v <- X[, j] - mean(X[, j])
      Z[, j] <- v / sqrt(sum(v^2) / (n - 1))
    }
    Z
  }
  set_col <- function(M, v, j) {
    M[, j] <- v
    M
  }
  set_row <- function(M, v, i) {
    M[i, ] <- v
    M
  }
  swap <- function(M) {
    M[, 1] <- M[, 2]
    M[2, ] <- M[1, ]
    M
  }
  fs <- aw_compile(standardise)
  fc <- aw_compile(set_col)
  fr <- aw_compile(set_row)
  fw <- aw_compile(swap)
  set.seed(11)
  for (t in seq_len(20L)) {
    X <- matrix(stats::rnorm(60, 10, 3), 12, 5)
    expect_true(identical(fs(X), standardise(X), num.eq = FALSE), label = paste("standardise", t))
  }
  M <- matrix(as.double(1:12), 4, 3)
  for (v in list(7, c(1.5, -2), c(9, 8, 7, 6), 5L, c(2L, NA))) {
    expect_identical(fc(M, v, 2), set_col(M, v, 2))
  }
  expect_identical(fr(M, c(-1, -2, -3), 3), set_row(M, c(-1, -2, -3), 3))
  expect_identical(fr(M, 0.5, 4L), set_row(M, 0.5, 4L))
  expect_identical(fw(M), swap(M))
  for (g in list(fs, fc, fr, fw)) {
    utils::capture.output(info <- aw_explain(g))
    expect_true(all(info$native), label = "native")
  }
  # Lengths R rejects in a matrix are left to R, which errors with its message.
  for (v in list(1:3, 1:8, numeric(0))) {
    expect_identical(tryCatch(fc(M, v, 1), error = conditionMessage), tryCatch(set_col(M, v, 1), error = conditionMessage))
  }
  expect_identical(tryCatch(fr(M, 1, 5), error = conditionMessage), tryCatch(set_row(M, 1, 5), error = conditionMessage))
})

test_that("a function that cannot be compiled says so, unless arwad.quiet is set", {
  expect_message(h <- aw_compile(function(x) paste(x)), "runs in GNU R, not as native code")
  expect_false(inherits(h, "arwad_function"))
  old <- options(arwad.quiet = TRUE)
  on.exit(options(old))
  expect_silent(aw_compile(function(x) paste(x)))
})
