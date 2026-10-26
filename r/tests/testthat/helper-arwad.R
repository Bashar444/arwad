# Built units go to a per-session temporary cache, never the user's cache.
options(arwad.cache_dir = file.path(tempdir(), "arwad-cache"))

skip_if_no_toolchain <- function() {
  skip_if_not(aw_toolchain()$ok, "Goose toolchain not available (set ARWAD_GOOSE)")
}

aw_stats <- function(g) {
  out <- NULL
  utils::capture.output(out <- aw_explain(g))
  out
}

# For functions that draw random numbers: the same seed before each run, and
# afterwards the same values and the same generator state.
expect_same_stream <- function(f, g, args, label, seed) {
  set.seed(seed)
  want <- withVisible(do.call(f, args))
  s_want <- get(".Random.seed", envir = globalenv())
  set.seed(seed)
  got <- withVisible(do.call(g, args))
  s_got <- get(".Random.seed", envir = globalenv())
  expect_true(identical(got$value, want$value, num.eq = FALSE), label = paste(label, "values"))
  expect_identical(got$visible, want$visible, label = paste(label, "visibility"))
  expect_identical(s_got, s_want, label = paste(label, "generator state"))
}

# Bit-for-bit equality with GNU R: same value (num.eq = FALSE also tells
# -0 from 0 and NA from NaN) and same visibility.
expect_same_as_r <- function(f, g, args, label) {
  want <- withVisible(do.call(f, args))
  got <- withVisible(do.call(g, args))
  ok <- identical(got$value, want$value, num.eq = FALSE)
  expect_true(ok, label = sprintf("%s(%s): got %s, R gives %s", label,
                                  paste(vapply(args, function(a) paste(deparse(a), collapse = ""), ""), collapse = ", "),
                                  paste(deparse(got$value), collapse = ""), paste(deparse(want$value), collapse = "")))
  expect_identical(got$visible, want$visible, label = paste(label, "visibility"))
}
