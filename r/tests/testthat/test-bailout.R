# When the native code meets a case it does not model, the call is re-run in
# GNU R, so errors, warnings and values are exactly R's.

bailouts <- function(g) sum(aw_stats(g)$bailouts)

test_that("an NA condition gives R's error", {
  skip_if_no_toolchain()
  f <- function(x) if (x > 0) 1 else -1
  g <- aw_compile(f)
  expect_identical(g(2), 1)
  expect_error(g(NA_real_), "missing value where TRUE/FALSE needed")
  expect_identical(bailouts(g), 1L)
})

test_that("integer overflow gives R's NA and warning", {
  skip_if_no_toolchain()
  g <- aw_compile(function(x) x + 1L)
  expect_identical(g(41L), 42L)
  expect_warning(v <- g(.Machine$integer.max), "NAs produced by integer overflow")
  expect_identical(v, NA_integer_)
})

test_that("sqrt() and log() of negative numbers give R's warning", {
  skip_if_no_toolchain()
  g <- aw_compile(function(x) sqrt(x) + log(-x))
  expect_warning(v <- g(-4), "NaNs produced")
  expect_identical(v, suppressWarnings(sqrt(-4) + log(4)))
})

test_that("zero, negative and out-of-range indices give R's results", {
  skip_if_no_toolchain()
  g <- aw_compile(function(x, i) x[i])
  x <- c(10, 20, 30)
  expect_identical(g(x, 2L), 20)
  expect_identical(g(x, 0L), numeric(0))
  expect_identical(g(x, -1L), c(20, 30))
  expect_identical(g(x, 0.5), numeric(0))
  h <- aw_compile(function(x, i) x[[i]])
  expect_identical(h(x, 3L), 30)
  expect_error(h(x, 4L), "subscript out of bounds")
})

test_that("fractional loop bounds and %% of fractions are left to R", {
  skip_if_no_toolchain()
  g <- aw_compile(function(n) { s <- 0L; for (i in 1:n) s <- s + i; s })
  expect_identical(g(4), 10L)
  expect_identical(g(2.5), 3L)
  m <- aw_compile(function(a, b) a %% b)
  expect_identical(m(7, 3), 1)
  expect_identical(m(5.5, 2), 1.5)
  expect_identical(m(1, 0.2), 1 %% 0.2)
  expect_identical(bailouts(m), 2L)
})

test_that("vector cases that R warns or errors about are left to R", {
  skip_if_no_toolchain()
  add <- aw_compile(function(x, y) x + y)
  expect_identical(add(1:6, 1:2), 1:6 + 1:2)
  expect_warning(v <- add(1:6, 1:4), "longer object length is not a multiple")
  expect_identical(v, suppressWarnings(1:6 + 1:4))
  top <- aw_compile(function(x) max(x))
  expect_identical(top(c(2, 9, 4)), 9)
  expect_warning(v <- top(numeric(0)), "no non-missing arguments")
  expect_identical(v, -Inf)
  pos <- aw_compile(function(x) if (x > 0) 1 else 2)
  expect_error(pos(c(1, 2)), "the condition has length > 1")
})

test_that("matrix cases that R warns or errors about are left to R", {
  skip_if_no_toolchain()
  add <- aw_compile(function(a, b) a + b)
  m <- matrix(1:6, 2)
  expect_identical(add(m, m), m + m)
  expect_error(add(m, matrix(1:4, 2)), "non-conformable arrays")
  get <- aw_compile(function(m, i, j) m[i, j])
  expect_identical(get(m, 2L, 3L), 6L)
  expect_error(get(m, 3L, 1L), "subscript out of bounds")
  mk <- aw_compile(function(x, r, c) matrix(x, r, c))
  expect_identical(mk(1:4, 2, 2), matrix(1:4, 2, 2))
  expect_warning(v <- mk(1:3, 2, 2), "not a sub-multiple")
  expect_identical(v, suppressWarnings(matrix(1:3, 2, 2)))
  named <- matrix(1:4, 2, dimnames = list(c("a", "b"), NULL))
  expect_identical(add(named, named), named + named)
})

test_that("seq_len() of a negative number gives R's error", {
  skip_if_no_toolchain()
  g <- aw_compile(function(n) { s <- 0L; for (i in seq_len(n)) s <- s + 1L; s })
  expect_identical(g(3L), 3L)
  expect_error(g(-1L), class = "error")
  expect_error(g(-1L), conditionMessage(tryCatch(seq_len(-1L), error = identity)), fixed = TRUE)
})
