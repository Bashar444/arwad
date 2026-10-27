# Signatures that cannot be compiled run in GNU R, with the reason recorded.

test_that("vector sub-assignment and type changes run in R with a reason", {
  f <- function(x) { x[c(TRUE, FALSE, TRUE)] <- c(9, 8); x }
  g <- aw_compile(f)
  expect_identical(g(c(1, 2, 3)), c(9, 2, 8))
  s <- aw_stats(g)
  expect_false(s$native)
  expect_match(s$reason, "assigning a vector into x\\[i\\] with a single or a logical index")

  h <- aw_compile(function(n) { s <- 0L; for (i in seq_len(n)) s <- s + 0.5; s })
  expect_identical(h(2L), 1)
  expect_match(aw_stats(h)$reason, "changes from integer scalar to double scalar")
})

test_that("arguments outside the subset run in R", {
  g <- aw_compile(function(x) x + 1)
  expect_identical(suppressWarnings(g(factor("a"))), suppressWarnings(factor("a") + 1))
  expect_error(g("a"), "non-numeric argument")
  expect_match(paste(aw_stats(g)$reason, collapse = " "), "type character")
})

test_that("without Goose every call runs in R", {
  old <- options(arwad.goose = file.path(tempdir(), "no-such-goose"))
  on.exit({ options(old); aw_toolchain(refresh = TRUE) })
  aw_toolchain(refresh = TRUE)
  g <- aw_compile(function(x) { s <- 0; for (v in x) s <- s + v; s })
  expect_identical(g(c(1, 2, 3)), 6)
  expect_match(aw_stats(g)$reason, "Goose not found")
})
