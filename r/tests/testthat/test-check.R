reason <- function(f) attr(aw_compile(f), "arwad_fallback")

test_that("functions in the subset are compiled", {
  g <- aw_compile(function(x) { s <- 0; for (i in seq_along(x)) s <- s + x[i]; s })
  expect_s3_class(g, "arwad_function")
  expect_null(attr(g, "arwad_fallback"))
  expect_identical(names(formals(g)), "x")
  expect_output(print(g), "arwad function")
})

test_that("constructs outside the subset fall back with a reason", {
  expect_match(reason(function(...) 1), "`...`", fixed = TRUE)
  expect_match(reason(function(x) { y <<- x }), "superassignment")
  expect_match(reason(function(x) paste(x)), "call to `paste` is not in subset v0")
  expect_match(reason(function(x) x + y), "free variable 'y'")
  expect_match(reason(function(x) { if (x > 0) y <- 1; y }), "may be used before it is assigned")
  expect_match(reason(function(m) m[1, 2, 3]), "more than two dimensions")
  expect_match(reason(function(x) "a"), "character constant")
  expect_match(reason(function(x) { f <- function(y) y; f(x) }), "closures")
  expect_match(reason(function(x, n = length(x)) n), "default of argument 'n' is not a constant")
  expect_match(reason(function(x) x[]), "empty argument")
  expect_match(reason(function() break), "outside a loop")
  expect_match(reason(function(x) sample(x)), "sample\\(\\) is planned")
  expect_match(reason(function(x) sum(x, na.rm = TRUE)), "na.rm")
  expect_match(reason(function(x) seq(1, x)), "seq\\(\\) is planned")
  expect_identical(aw_compile(sum), sum)
})

test_that("a base function redefined where f was made is not trusted", {
  e <- new.env()
  e$sqrt <- function(x) 0
  f <- function(x) sqrt(x)
  environment(f) <- e
  expect_match(reason(f), "`sqrt` is redefined")
})

test_that("names defined by a repeat body before its break are assigned after it", {
  g <- aw_compile(function(a) { x <- a; repeat { nx <- x / 2; if (nx < 1) break; x <- nx }; nx })
  expect_s3_class(g, "arwad_function")
})

test_that("aw_explain() reports a function that was not compiled", {
  expect_output(aw_explain(aw_compile(function(x) paste(x))), "Not compiled")
})
