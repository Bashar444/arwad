test_that("every corpus function runs natively and matches GNU R bit for bit", {
  skip_if_no_toolchain()
  corpus <- source(system.file("corpus", "slice1.R", package = "arwad"), local = new.env())$value
  expect_gte(length(corpus), 30L)
  for (nm in names(corpus)) {
    entry <- corpus[[nm]]
    g <- aw_compile(entry$f, name = nm)
    expect_s3_class(g, "arwad_function")
    for (args in entry$inputs) expect_same_as_r(entry$f, g, args, nm)
    s <- aw_stats(g)
    expect_true(all(s$native), label = paste(nm, "runs natively:", paste(stats::na.omit(s$reason), collapse = "; ")))
    expect_identical(sum(s$bailouts), 0L, label = paste(nm, "bailouts"))
  }
})

test_that("calls switch between native units by argument type", {
  skip_if_no_toolchain()
  f <- function(x) { s <- 0; for (v in x) s <- s + v; s }
  g <- aw_compile(f)
  for (a in list(1:3, c(1.5, 2), 1:3, c(TRUE, NA), c(a = 1, b = 2), 7)) expect_identical(g(a), f(a))
  s <- aw_stats(g)
  expect_setequal(s$signature[s$native], c("int[]", "dbl[]", "lgl[]"))
  expect_identical(sum(!s$native), 1L)
  expect_identical(sum(s$calls), 6L)
})

test_that("both build paths work: direct, and R CMD SHLIB as the fallback", {
  skip_if_no_toolchain()
  f <- function(x) { s <- 0; for (v in x) s <- s + v * v; s }
  method <- function(g) get("dbl[]", envir = attr(g, "arwad_state")$specs)$method
  g <- aw_compile(f)
  expect_identical(g(c(1.5, -2)), f(c(1.5, -2)))
  expect_identical(method(g), "direct")
  old <- options(arwad.build = "shlib", arwad.cache_dir = tempfile("arwad-shlib"))
  on.exit(options(old))
  h <- aw_compile(f)
  expect_identical(h(c(1.5, -2)), f(c(1.5, -2)))
  expect_identical(method(h), "R CMD SHLIB")
})

test_that("a compiled function does not change its caller's vector", {
  skip_if_no_toolchain()
  g <- aw_compile(function(x) { x[1] <- 100; x })
  v <- c(1, 2, 3)
  expect_identical(g(v), c(100, 2, 3))
  expect_identical(v, c(1, 2, 3))
})

test_that("the native unit is reused across calls and from the disk cache", {
  skip_if_no_toolchain()
  f <- function(x) { s <- 0; for (v in x) s <- s + v; s }
  g1 <- aw_compile(f)
  g1(c(1, 2))
  g2 <- aw_compile(f)
  g2(c(3, 4, 5))
  st <- attr(g2, "arwad_state")
  sp <- get("dbl[]", envir = st$specs)
  expect_true(sp$ok)
  expect_true(sp$cached)
  expect_match(aw_source(g2) |> utils::capture.output() |> paste(collapse = "\n"), "export \"aw_entry_")
})
