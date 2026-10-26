# Equivalence corpus, compiler slice 1.
#
# Each entry is a self-contained function in the compilable subset and a list
# of argument lists. Every input must run natively (no bailout) and match GNU
# R bit for bit. The inputs deliberately include NA, NaN, +/-Inf, -0, empty
# and length-one vectors. Phase 1 grows this corpus to 200 functions.

set.seed(20261026)
xs <- c(stats::rnorm(40), NA, NaN, Inf, -Inf, 0, -0, 1e300, -1e-300)
ints <- c(sample(-1000:1000, 30), NA_integer_)
tf <- c(TRUE, FALSE, NA)
lgl_pairs <- unlist(lapply(tf, function(a) lapply(tf, function(b) list(a, b))), recursive = FALSE)

list(
  sum_sq = list(
    f = function(x) { s <- 0; for (i in seq_along(x)) s <- s + x[i]^2; s },
    inputs = list(list(xs), list(numeric(0)), list(1.5), list(ints))),
  count_pos = list(
    f = function(x) { n <- 0L; for (v in x) if (v > 0) n <- n + 1L; n },
    inputs = list(list(stats::rnorm(50)), list(c(-1L, 2L, 3L)), list(numeric(0)))),
  cumsum_loop = list(
    f = function(x) { out <- numeric(length(x)); acc <- 0; for (i in seq_along(x)) { acc <- acc + x[i]; out[i] <- acc }; out },
    inputs = list(list(xs), list(numeric(0)), list(ints))),
  fib = list(
    f = function(n) { a <- 0; b <- 1; for (i in seq_len(n)) { t <- a + b; a <- b; b <- t }; a },
    inputs = list(list(0), list(1), list(10L), list(90), list(1500))),
  collatz = list(
    f = function(n) { steps <- 0L; while (n != 1) { if (n %% 2 == 0) n <- n / 2 else n <- 3 * n + 1; steps <- steps + 1L }; steps },
    inputs = list(list(27), list(97), list(1), list(871))),
  int_sum_loop = list(
    f = function(x) { s <- 0L; for (v in x) s <- s + v; s },
    inputs = list(list(1:100), list(c(5L, NA, 3L)), list(integer(0)))),
  newton_sqrt = list(
    f = function(a, tol) { x <- a; repeat { nx <- 0.5 * (x + a / x); if (abs(nx - x) < tol) break; x <- nx }; nx },
    inputs = list(list(2, 1e-12), list(1e10, 1e-6), list(0.25, 1e-15))),
  trapezoid = list(
    f = function(a, b, n) { h <- (b - a) / n; s <- 0.5 * (exp(-a * a) + exp(-b * b)); for (i in seq_len(n - 1)) { x <- a + i * h; s <- s + exp(-x * x) }; s * h },
    inputs = list(list(0, 1, 100), list(-2, 2, 1000L))),
  prime_count = list(
    f = function(n) {
      count <- 0L
      for (k in 2:n) {
        is_p <- TRUE
        d <- 2L
        while (d * d <= k) { if (k %% d == 0L) { is_p <- FALSE; break }; d <- d + 1L }
        if (is_p) count <- count + 1L
      }
      count
    },
    inputs = list(list(100), list(2000L), list(2))),
  max_loop = list(
    f = function(x) { m <- -Inf; for (v in x) if (v > m) m <- v; m },
    inputs = list(list(stats::rnorm(100)), list(numeric(0)), list(c(1, 5, 3)))),
  which_first = list(
    f = function(x, thr) { for (i in seq_along(x)) if (x[i] > thr) return(i); 0L },
    inputs = list(list(stats::rnorm(20), 1), list(c(1, 2, 3), 10))),
  clamp = list(
    f = function(x, lo, hi) { if (x < lo) lo else if (x > hi) hi else x },
    inputs = list(list(5, 0, 1), list(-1, 0, 1), list(0.5, 0, 1), list(5L, 0L, 10L), list(5L, 0, 10))),
  logic_mix = list(
    f = function(a, b) (a && !b) || (is.na(a) & b),
    inputs = lgl_pairs),
  int_div_mod = list(
    f = function(a, b) { q <- a %/% b; r <- a %% b; q * 1000L + r },
    inputs = list(list(17L, 5L), list(-17L, 5L), list(17L, -5L), list(-17L, -5L), list(5L, 0L), list(NA_integer_, 3L))),
  dbl_div_mod = list(
    f = function(a, b) (a %/% b) * 10 + a %% b,
    inputs = list(list(17, 5), list(-17, 5), list(17, -5), list(-17, -5), list(0, 3), list(-0, 3),
                  list(123456789012, 97), list(4503599627370496, 3), list(7L, 2))),
  pow_table = list(
    f = function(x, p) { out <- numeric(length(x)); for (i in seq_along(x)) out[i] <- x[i]^p; out },
    inputs = list(list(xs, 2), list(xs, 0.5), list(c(-8, 8, 0, NA), 1 / 3), list(ints, 3L), list(c(1L, NA), 0L))),
  grow_vec = list(
    f = function(n) { out <- numeric(0); for (i in seq_len(n)) out[i] <- i * 2; out },
    inputs = list(list(0), list(5), list(100L))),
  lgl_vec = list(
    f = function(x) { out <- logical(length(x)); for (i in seq_along(x)) out[i] <- x[i] > 0; out },
    inputs = list(list(xs), list(ints))),
  vec_sum = list(
    f = function(x) sum(x),
    inputs = list(list(xs), list(stats::rnorm(1000)), list(1:10), list(c(TRUE, NA)), list(integer(0)),
                  list(c(1e308, 1e308)), list(-0), list(c(0.1, 0.2, 0.3)))),
  mean_skip_na = list(
    f = function(x) { s <- 0; n <- 0L; for (v in x) { if (is.na(v)) next; s <- s + v; n <- n + 1L }; s / n },
    inputs = list(list(xs), list(c(NA, NA)), list(c(1, 2, 3)))),
  nested_loops = list(
    f = function(n) { s <- 0; for (i in seq_len(n)) for (j in seq_len(i)) s <- s + 1 / (i * j); s },
    inputs = list(list(50), list(200L))),
  while_scan = list(
    f = function(x) { i <- 1L; while (i <= length(x) && x[i] != 0) i <- i + 1L; i },
    inputs = list(list(c(3, 2, 0, 5)), list(c(1, 2)), list(numeric(0)))),
  sign_flip = list(
    f = function(x) { out <- x; for (i in seq_along(out)) out[i] <- -out[i]; out },
    inputs = list(list(xs), list(ints))),
  modify_arg = list(
    f = function(x) { x[1] <- 100L; x },
    inputs = list(list(c(1, 2, 3)), list(numeric(0)), list(1:3))),
  bool_count = list(
    f = function(x) { n <- 0L; for (b in x) if (b) n <- n + 1L; n },
    inputs = list(list(c(TRUE, FALSE, TRUE)), list(logical(0)))),
  descending = list(
    f = function(n) { s <- 0L; for (i in n:1) s <- s * 2L + i; s },
    inputs = list(list(10L), list(1L), list(0L))),
  sqrt_log = list(
    f = function(x) { if (x > 0) log(sqrt(x)) else exp(x) },
    inputs = list(list(4), list(1e-300), list(-1), list(0), list(1e308))),
  div_by = list(
    f = function(a, b) a / b,
    inputs = list(list(1, 0), list(-1, 0), list(0, 0), list(5L, 2L), list(NA_real_, 1), list(7L, 0L))),
  mixed_types = list(
    f = function(a, b) { c1 <- a + b; c2 <- a * 2L; c1 - c2 },
    inputs = list(list(1L, 2L), list(1.5, 2L), list(TRUE, FALSE), list(1e300, 1e300))),
  repeat_break = list(
    f = function(x) { i <- 0L; repeat { i <- i + 1L; if (i >= length(x) || x[i] < 0) break }; i },
    inputs = list(list(c(1, 2, -3, 4)), list(c(1, 2)), list(5))),
  index_read = list(
    f = function(x, i) x[i],
    inputs = list(list(c(1, 2, 3), 2), list(c(1, 2, 3), 2.9), list(c(1, 2, 3), 5), list(c(1, 2, 3), NA_real_),
                  list(1:3, 3L), list(c(TRUE, NA), 2L))),
  int_abs_sum = list(
    f = function(x) { s <- 0L; for (v in x) s <- s + abs(v); s },
    inputs = list(list(c(-3L, 4L, -5L)), list(c(NA, 1L)))),
  no_args = list(
    f = function() { s <- 0; for (i in 1:10) s <- s + i; s },
    inputs = list(list())),
  if_value = list(
    f = function(x) { y <- if (x > 0) x * 2 else -x; y + 1 },
    inputs = list(list(3), list(-2), list(0))),
  invisible_assign = list(
    f = function(x) y <- x * 2,
    inputs = list(list(2), list(NA_real_))),
  loop_value = list(
    f = function(n) for (i in seq_len(n)) n,
    inputs = list(list(3))),
  logic_scalar = list(
    f = function(a, b) { x <- a & b; y <- a | b; z <- !a; (x | y) & !z },
    inputs = c(lgl_pairs, list(list(0.5, 0), list(NaN, 1)))),
  constants = list(
    f = function(x) { if (x > pi) T else F },
    inputs = list(list(3), list(4)))
)
