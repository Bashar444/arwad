# Equivalence corpus, compiler slice 2: vectors.
#
# Vectorised arithmetic with recycling, logical masks and index vectors,
# c(), mean(), min(), max(), sequences as values. Same rules as slice1.R:
# every input runs natively and matches GNU R bit for bit.

set.seed(20261027)
xs <- c(stats::rnorm(30), NA, NaN, Inf, -Inf, 0, -0)
xf <- stats::rnorm(50)
ints <- c(sample(-500:500, 25), NA_integer_)

list(
  center_scale = list(
    f = function(x) { m <- mean(x); s <- sqrt(sum((x - m)^2) / (length(x) - 1)); (x - m) / s },
    inputs = list(list(xf), list(c(1, 2, 3, 4)), list(xs))),
  vec_ops = list(
    f = function(x, y) x * y + x / y - y,
    inputs = list(list(xf, xf), list(xf, 2), list(1:6, 1:2), list(ints, 3L), list(numeric(0), 1:3),
                  list(c(TRUE, FALSE), 1:4))),
  vec_compare = list(
    f = function(x, y) (x > y) | is.na(x) & !(x == y),
    inputs = list(list(xs, 0), list(xs, rev(xs)), list(ints, 0L), list(c(TRUE, NA, FALSE), TRUE))),
  vec_math = list(
    f = function(x) sqrt(abs(x)) + exp(-x^2) + log(abs(x) + 1),
    inputs = list(list(xs), list(ints), list(numeric(0)))),
  count_na = list(
    f = function(x) sum(is.na(x)) + sum(x > 0 & !is.na(x)),
    inputs = list(list(xs), list(ints), list(logical(0)))),
  positives = list(
    f = function(x) x[x > 0],
    inputs = list(list(xs), list(ints), list(numeric(0)), list(c(TRUE, NA, FALSE)))),
  clip = list(
    f = function(x, lo, hi) { x[x < lo] <- lo; x[x > hi] <- hi; x },
    inputs = list(list(xs, -1, 1), list(ints, -100L, 100L), list(c(5, NA, -5), 0, 1))),
  gather = list(
    f = function(x, idx) x[idx],
    inputs = list(list(xs, c(3L, 1L, NA, 100L)), list(xs, c(2.7, 1, NaN)), list(1:5, 5:1), list(c(TRUE, NA), c(2L, 2L, 1L)))),
  set_some = list(
    f = function(x, idx, v) { x[idx] <- v; x },
    inputs = list(list(c(1, 2, 3), c(1L, 3L), 0), list(c(1, 2, 3), c(5L, NA, 0L), 9), list(1:3, c(2, 2.5), 7L),
                  list(numeric(0), 2L, 1))),
  build_c = list(
    f = function(a, b) c(a, b, a + b, length(b)),
    inputs = list(list(1, 2), list(1:3, 4.5), list(TRUE, NA), list(c(1, NA), numeric(0)))),
  extremes = list(
    f = function(x) c(min(x), max(x), mean(x)),
    inputs = list(list(xf), list(c(1, NaN, NA)), list(c(NA, NaN, 1)), list(c(NaN, 1)), list(c(-0, 0)), list(c(0, -0)),
                  list(ints), list(1:10), list(c(TRUE, FALSE)), list(c(1e308, 1e308)), list(c(-Inf, Inf)))),
  minmax_args = list(
    f = function(a, b) max(a, b) - min(a, 0, b),
    inputs = list(list(1:3, 2.5), list(c(NA, 1), 5), list(numeric(0), 3), list(2L, 3L))),
  seq_values = list(
    f = function(n) { v <- 1:n; w <- seq_len(n); sum(v * w) + length(seq_along(v)) },
    inputs = list(list(5), list(10L), list(1))),
  reverse = list(
    f = function(x) x[length(x):1],
    inputs = list(list(xs), list(1:5), list(c(TRUE, NA)))),
  running_max = list(
    f = function(x) { out <- x; for (i in seq_along(x)) out[i] <- max(x[1:i]); out },
    inputs = list(list(xf), list(c(3L, 1L, 4L, 1L, 5L)))),
  scalar_from_vec = list(
    f = function(x) if (length(x) > 0 && x[1] > 0 && sum(x) > 1) mean(x) else -1,
    inputs = list(list(c(2, 3)), list(c(-1, 3)), list(numeric(0)), list(0.5))),
  weighted = list(
    f = function(x, w) sum(x * w) / sum(w),
    inputs = list(list(xf, abs(xf)), list(1:4, c(0.1, 0.2, 0.3, 0.4)))),
  rescale_ints = list(
    f = function(x) (x - min(x)) / (max(x) - min(x)),
    inputs = list(list(c(3L, 7L, 1L, 9L)), list(xf))),
  any_large = list(
    f = function(x) sum(x > 2) > 0 || is.na(sum(x)),
    inputs = list(list(xf), list(c(1, NA)), list(c(3, 4)))),
  mean_types = list(
    f = function(x) mean(x),
    inputs = list(list(xs), list(ints), list(c(TRUE, FALSE, TRUE)), list(numeric(0)), list(-0), list(5L)))
)
