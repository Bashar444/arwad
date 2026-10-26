# Equivalence corpus, part 4: statistics, numerical methods and algorithms
# written the way R users write them (loops, accumulators, vector and matrix
# operations, simulation). Same rules as slice1.R: every input runs natively
# and matches GNU R bit for bit; seeded entries also match .Random.seed.

set.seed(20261029)
x50 <- stats::rnorm(50, 10, 3)
y50 <- 2 + 0.5 * x50 + stats::rnorm(50)
p50 <- stats::runif(50)
k50 <- sample(0:20, 50, TRUE)
M <- matrix(stats::rnorm(40), 10, 4)

list(
  var_loop = list(
    f = function(x) { n <- length(x); m <- mean(x); s <- 0; for (v in x) s <- s + (v - m)^2; s / (n - 1) },
    inputs = list(list(x50), list(c(1, 2, 3, 4)))),
  sd_vec = list(
    f = function(x) sqrt(sum((x - mean(x))^2) / (length(x) - 1)),
    inputs = list(list(x50), list(p50))),
  cov_loop = list(
    f = function(x, y) {
      mx <- mean(x); my <- mean(y); s <- 0
      for (i in seq_along(x)) s <- s + (x[i] - mx) * (y[i] - my)
      s / (length(x) - 1)
    },
    inputs = list(list(x50, y50))),
  cor_vec = list(
    f = function(x, y) { dx <- x - mean(x); dy <- y - mean(y); sum(dx * dy) / sqrt(sum(dx^2) * sum(dy^2)) },
    inputs = list(list(x50, y50), list(p50, x50))),
  zscore = list(
    f = function(x) (x - mean(x)) / sqrt(sum((x - mean(x))^2) / (length(x) - 1)),
    inputs = list(list(x50))),
  welford = list(
    f = function(x) {
      n <- 0L; m <- 0; s2 <- 0
      for (v in x) { n <- n + 1L; d <- v - m; m <- m + d / n; s2 <- s2 + d * (v - m) }
      c(m, s2 / (n - 1))
    },
    inputs = list(list(x50), list(p50))),
  moving_avg = list(
    f = function(x, k) {
      n <- length(x); out <- numeric(n - k + 1)
      for (i in seq_len(n - k + 1)) out[i] <- mean(x[i:(i + k - 1)])
      out
    },
    inputs = list(list(x50, 5), list(p50, 3L))),
  ema = list(
    f = function(x, a) {
      out <- numeric(length(x)); out[1] <- x[1]
      for (i in 2:length(x)) out[i] <- a * x[i] + (1 - a) * out[i - 1]
      out
    },
    inputs = list(list(x50, 0.3))),
  cumprod_loop = list(
    f = function(x) { out <- numeric(length(x)); p <- 1; for (i in seq_along(x)) { p <- p * x[i]; out[i] <- p }; out },
    inputs = list(list(1 + p50 / 10))),
  geometric_mean = list(
    f = function(x) exp(mean(log(x))),
    inputs = list(list(1 + p50), list(c(1, 10, 100)))),
  harmonic_mean = list(
    f = function(x) length(x) / sum(1 / x),
    inputs = list(list(1 + p50))),
  skewness = list(
    f = function(x) { m <- mean(x); s <- sqrt(mean((x - m)^2)); mean(((x - m) / s)^3) },
    inputs = list(list(x50))),
  kurtosis = list(
    f = function(x) { m <- mean(x); v <- mean((x - m)^2); mean((x - m)^4) / v^2 - 3 },
    inputs = list(list(x50))),
  mean_abs_dev = list(
    f = function(x) mean(abs(x - mean(x))),
    inputs = list(list(x50))),
  range_width = list(
    f = function(x) max(x) - min(x),
    inputs = list(list(x50), list(k50))),
  count_between = list(
    f = function(x, lo, hi) sum(x >= lo & x <= hi),
    inputs = list(list(x50, 8, 12), list(k50, 5L, 10L))),
  prop_above = list(
    f = function(x, t) mean(x > t),
    inputs = list(list(x50, 10), list(p50, 0.5))),
  ols_simple = list(
    f = function(x, y) {
      mx <- mean(x); my <- mean(y)
      b <- sum((x - mx) * (y - my)) / sum((x - mx)^2)
      c(my - b * mx, b)
    },
    inputs = list(list(x50, y50))),
  r_squared = list(
    f = function(x, y) {
      n <- length(x); X <- matrix(1, n, 2)
      for (i in seq_len(n)) X[i, 2] <- x[i]
      b <- solve(crossprod(X), crossprod(X, y))
      r <- y - X %*% b
      1 - sum(r^2) / sum((y - mean(y))^2)
    },
    inputs = list(list(x50, y50))),
  logistic = list(
    f = function(x) 1 / (1 + exp(-x)),
    inputs = list(list(x50 - 10), list(c(-800, 0, 800)))),
  softmax = list(
    f = function(x) { e <- exp(x - max(x)); e / sum(e) },
    inputs = list(list(p50), list(c(1, 2, 3)))),
  log_sum_exp = list(
    f = function(x) { m <- max(x); m + log(sum(exp(x - m))) },
    inputs = list(list(x50))),
  normal_pdf = list(
    f = function(x, mu, s) exp(-0.5 * ((x - mu) / s)^2) / (s * sqrt(2 * pi)),
    inputs = list(list(x50, 10, 3))),
  normal_loglik = list(
    f = function(x, mu, s) { n <- length(x); -n / 2 * log(2 * pi * s^2) - sum((x - mu)^2) / (2 * s^2) },
    inputs = list(list(x50, 10, 3))),
  poisson_loglik = list(
    f = function(k, lambda) {
      s <- 0
      for (v in k) { lf <- 0; if (v > 1) for (j in 2:v) lf <- lf + log(j); s <- s + v * log(lambda) - lambda - lf }
      s
    },
    inputs = list(list(k50, 4.5))),
  bisection = list(
    f = function(a, b, tol) {
      fa <- a^3 - a - 2
      while (b - a > tol) { m <- (a + b) / 2; fm <- m^3 - m - 2; if (fa * fm <= 0) b <- m else { a <- m; fa <- fm } }
      (a + b) / 2
    },
    inputs = list(list(1, 2, 1e-10))),
  newton_cubic = list(
    f = function(x0) { x <- x0; for (i in 1:50) x <- x - (x^3 - 2 * x - 5) / (3 * x^2 - 2); x },
    inputs = list(list(2), list(3))),
  simpson = list(
    f = function(a, b, n) {
      h <- (b - a) / n; s <- exp(-a * a) + exp(-b * b)
      for (i in seq_len(n - 1)) { x <- a + i * h; s <- s + (if (i %% 2 == 1) 4 else 2) * exp(-x * x) }
      s * h / 3
    },
    inputs = list(list(0, 1, 100), list(-1, 1, 1000L))),
  horner = list(
    f = function(coef, x) { r <- 0; for (i in length(coef):1) r <- r * x + coef[i]; r },
    inputs = list(list(c(1, -2, 0.5, 3), 1.7), list(c(2, 0, 1), -3))),
  poly_vec = list(
    f = function(x) 3 * x^3 - 2 * x^2 + x - 7,
    inputs = list(list(x50), list(1:10))),
  euclid_gcd = list(
    f = function(a, b) { while (b != 0L) { r <- a %% b; a <- b; b <- r }; a },
    inputs = list(list(1071L, 462L), list(17L, 5L))),
  lcm = list(
    f = function(a, b) { x <- a; y <- b; while (y != 0L) { r <- x %% y; x <- y; y <- r }; a %/% x * b },
    inputs = list(list(12L, 18L), list(7L, 5L))),
  digits_sum = list(
    f = function(n) { s <- 0L; while (n > 0L) { s <- s + n %% 10L; n <- n %/% 10L }; s },
    inputs = list(list(987654321L), list(0L))),
  palindrome_number = list(
    f = function(n) { r <- 0L; m <- n; while (m > 0L) { r <- r * 10L + m %% 10L; m <- m %/% 10L }; r == n },
    inputs = list(list(12321L), list(12345L))),
  sieve = list(
    f = function(n) {
      is_p <- logical(n)
      for (i in 2:n) is_p[i] <- TRUE
      for (i in 2:n) if (is_p[i]) { j <- i * i; while (j <= n) { is_p[j] <- FALSE; j <- j + i } }
      sum(is_p)
    },
    inputs = list(list(1000L), list(30L))),
  binary_search = list(
    f = function(x, target) {
      lo <- 1L; hi <- length(x)
      while (lo <= hi) {
        mid <- (lo + hi) %/% 2L
        if (x[mid] == target) return(mid)
        if (x[mid] < target) lo <- mid + 1L else hi <- mid - 1L
      }
      0L
    },
    inputs = list(list(c(1, 3, 5, 7, 9, 11), 7), list(c(1, 3, 5), 4))),
  insertion_sort = list(
    f = function(x) {
      n <- length(x)
      if (n > 1) for (i in 2:n) {
        key <- x[i]; j <- i - 1L
        while (j >= 1L && x[j] > key) { x[j + 1L] <- x[j]; j <- j - 1L }
        x[j + 1L] <- key
      }
      x
    },
    inputs = list(list(x50[1:20]), list(c(5L, 2L, 9L, 1L)))),
  bubble_count = list(
    f = function(x) {
      n <- length(x); swaps <- 0L
      for (i in seq_len(n - 1L)) for (j in seq_len(n - i)) if (x[j] > x[j + 1L]) {
        tmp <- x[j]; x[j] <- x[j + 1L]; x[j + 1L] <- tmp; swaps <- swaps + 1L
      }
      c(swaps, x)
    },
    inputs = list(list(c(5L, 1L, 4L, 2L, 8L)))),
  matrix_trace = list(
    f = function(m) { s <- 0; for (i in seq_len(nrow(m))) s <- s + m[i, i]; s },
    inputs = list(list(crossprod(M)))),
  matrix_power = list(
    f = function(m, k) { r <- m; for (i in seq_len(k - 1)) r <- r %*% m; r },
    inputs = list(list(matrix(c(0.5, 0.2, 0.1, 0.7), 2, 2), 5))),
  col_sums_loop = list(
    f = function(m) { out <- numeric(ncol(m)); for (j in seq_len(ncol(m))) out[j] <- sum(m[, j]); out },
    inputs = list(list(M))),
  row_means_loop = list(
    f = function(m) { out <- numeric(nrow(m)); for (i in seq_len(nrow(m))) out[i] <- mean(m[i, ]); out },
    inputs = list(list(M))),
  cov_matrix = list(
    f = function(m) {
      n <- nrow(m); cm <- m
      for (j in seq_len(ncol(m))) { mu <- mean(m[, j]); for (i in seq_len(n)) cm[i, j] <- m[i, j] - mu }
      crossprod(cm) / (n - 1)
    },
    inputs = list(list(M))),
  gram_schmidt_norms = list(
    f = function(m) {
      q <- m; k <- ncol(m); norms <- numeric(k)
      for (j in seq_len(k)) {
        v <- q[, j]
        if (j > 1) for (i in 1:(j - 1)) { u <- q[, i]; v <- v - sum(u * v) / sum(u * u) * u }
        for (r in seq_len(nrow(m))) q[r, j] <- v[r]
        norms[j] <- sqrt(sum(v * v))
      }
      norms
    },
    inputs = list(list(M))),
  ridge_path = list(
    f = function(X, y, lambdas) {
      p <- ncol(X); out <- numeric(length(lambdas))
      for (k in seq_along(lambdas)) {
        A <- crossprod(X)
        for (j in seq_len(p)) A[j, j] <- A[j, j] + lambdas[k]
        b <- solve(A, crossprod(X, y))
        out[k] <- sum(b * b)
      }
      out
    },
    inputs = list(list(M, x50[1:10], c(0.1, 1, 10)))),
  gibbs_bivariate = list(
    f = function(n, rho) {
      x <- numeric(n); y <- numeric(n); s <- sqrt(1 - rho^2)
      for (i in 2:n) { x[i] <- rnorm(1, rho * y[i - 1], s); y[i] <- rnorm(1, rho * x[i], s) }
      c(mean(x), mean(y))
    },
    seed = 21L, inputs = list(list(500, 0.6))),
  ar1_sim = list(
    f = function(n, phi) { e <- rnorm(n); x <- numeric(n); x[1] <- e[1]; for (t in 2:n) x[t] <- phi * x[t - 1] + e[t]; x },
    seed = 22L, inputs = list(list(200, 0.8))),
  mc_integral = list(
    f = function(n) { u <- runif(n); mean(exp(-u^2)) },
    seed = 23L, inputs = list(list(10000))),
  bootstrap_ci = list(
    f = function(x, B) {
      n <- length(x); m <- numeric(B)
      for (b in seq_len(B)) m[b] <- mean(x[sample.int(n, replace = TRUE)])
      c(mean(m), sqrt(sum((m - mean(m))^2) / (B - 1)))
    },
    seed = 24L, inputs = list(list(x50, 300))),
  permutation_test = list(
    f = function(x, y, B) {
      obs <- mean(x) - mean(y); z <- c(x, y); nx <- length(x); cnt <- 0L
      for (b in seq_len(B)) {
        p <- sample(z)
        d <- mean(p[1:nx]) - mean(p[(nx + 1):length(z)])
        if (abs(d) >= abs(obs)) cnt <- cnt + 1L
      }
      cnt / B
    },
    seed = 25L, inputs = list(list(x50[1:15], y50[1:15], 200))),
  random_walk_hits = list(
    f = function(n, bound) {
      pos <- 0; hits <- 0L
      for (i in seq_len(n)) {
        pos <- pos + (if (runif(1) < 0.5) -1 else 1)
        if (abs(pos) >= bound) { hits <- hits + 1L; pos <- 0 }
      }
      hits
    },
    seed = 26L, inputs = list(list(5000, 10)))
)
