# Equivalence corpus, compiler slice 3: random numbers.
#
# runif() and rnorm() draw from GNU R's own generators. Entries with a seed
# are run after set.seed(seed) in R and again compiled; the values and the
# final .Random.seed must both be identical.

list(
  mc_pi = list(
    f = function(n) {
      inside <- 0L
      for (i in seq_len(n)) { x <- runif(1); y <- runif(1); if (x * x + y * y <= 1) inside <- inside + 1L }
      4 * inside / n
    },
    seed = 1L, inputs = list(list(1000), list(10L))),
  random_walk = list(
    f = function(n, sd) { x <- numeric(n); for (i in 2:n) x[i] <- x[i - 1] + rnorm(1, 0, sd); x },
    seed = 42L, inputs = list(list(100, 1), list(5, 0.5))),
  draws = list(
    f = function(n) c(runif(n), rnorm(n, 5, 2)),
    seed = 7L, inputs = list(list(10), list(0), list(1L))),
  param_vectors = list(
    f = function(n) runif(n, min = 1:3, max = 10) + rnorm(n, mean = c(0, 100)),
    seed = 3L, inputs = list(list(6), list(c(1, 1, 1)))),
  boot_mean = list(
    f = function(x, B) {
      n <- length(x)
      m <- numeric(B)
      for (b in seq_len(B)) { s <- 0; for (i in seq_len(n)) s <- s + x[floor(runif(1) * n) + 1]; m[b] <- s / n }
      m
    },
    seed = 2026L, inputs = list(list(c(2.1, 3.4, 1.9, 5.6, 4.4), 50))),
  no_draw = list(
    f = function(n) rnorm(n, 3, 0) + runif(n, 2, 2),
    seed = 9L, inputs = list(list(4))),
  rounding = list(
    f = function(x) c(floor(x), ceiling(x)),
    inputs = list(list(c(-1.5, -0.5, 0.5, 1.5, NA, NaN, Inf, -0)), list(c(3L, NA)))),
  boot_resample = list(
    f = function(x, B) {
      m <- numeric(B)
      for (b in seq_len(B)) m[b] <- mean(x[sample.int(length(x), replace = TRUE)])
      m
    },
    seed = 11L, inputs = list(list(c(2.1, 3.4, 1.9, 5.6, 4.4, 0.2), 200))),
  permutation = list(
    f = function(n) sample.int(n),
    seed = 12L, inputs = list(list(10), list(1L), list(25L))),
  partial_draw = list(
    f = function(n, k) sample.int(n, k),
    seed = 13L, inputs = list(list(100, 7), list(5L, 5L), list(9, 1))),
  shuffle = list(
    f = function(x) sample(x),
    seed = 14L, inputs = list(list(c(10, 20, 30, 40)), list(c(TRUE, FALSE, NA)), list(1:8))),
  with_replacement = list(
    f = function(x, k) sample(x, k, replace = TRUE),
    seed = 15L, inputs = list(list(c(1.5, 2.5, 3.5), 10), list(1:26, 3L))),
  sample_number = list(
    f = function(n) sample(n),
    seed = 16L, inputs = list(list(6), list(3L)))
)
