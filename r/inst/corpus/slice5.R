# Equivalence corpus, part 5: finance and time series, numerical methods,
# linear algebra, rank statistics, integer algorithms and simulation. Same
# rules as slice1.R; seeded entries also match .Random.seed.

set.seed(20261030)
px <- 100 * cumprod(1 + stats::rnorm(60, 0.001, 0.02))
xs5 <- stats::rnorm(40)
e5 <- stats::rnorm(100)
A3 <- matrix(c(4, 1, 0.5, 1, 5, 1, 0.5, 1, 6), 3, 3)
b3 <- c(1, 2, 3)
Xl <- cbind(1, stats::rnorm(80))
yl <- as.numeric(stats::runif(80) < 1 / (1 + exp(-(0.5 + 1.2 * Xl[, 2]))))
P2 <- matrix(stats::rnorm(20), 10, 2)
two_groups <- c(stats::rnorm(20, 0), stats::rnorm(20, 5))

list(
  standard_error = list(
    f = function(x) sqrt(sum((x - mean(x))^2) / (length(x) - 1)) / sqrt(length(x)),
    inputs = list(list(xs5), list(px))),
  coefficient_of_variation = list(
    f = function(x) { m <- mean(x); sqrt(sum((x - m)^2) / (length(x) - 1)) / m },
    inputs = list(list(px))),
  jackknife_se = list(
    f = function(x) {
      n <- length(x); th <- numeric(n)
      for (i in seq_len(n)) th[i] <- (sum(x) - x[i]) / (n - 1)
      sqrt((n - 1) / n * sum((th - mean(th))^2))
    },
    inputs = list(list(xs5))),
  trimmed_sum = list(
    f = function(x, lo, hi) { s <- 0; for (v in x) if (v > lo && v < hi) s <- s + v; s },
    inputs = list(list(xs5, -1, 1))),
  simple_returns = list(
    f = function(p) (p[2:length(p)] - p[1:(length(p) - 1)]) / p[1:(length(p) - 1)],
    inputs = list(list(px))),
  log_returns = list(
    f = function(p) log(p[2:length(p)]) - log(p[1:(length(p) - 1)]),
    inputs = list(list(px))),
  max_drawdown = list(
    f = function(p) {
      peak <- p[1]; dd <- 0
      for (v in p) { if (v > peak) peak <- v; d <- (peak - v) / peak; if (d > dd) dd <- d }
      dd
    },
    inputs = list(list(px))),
  compound = list(
    f = function(P, r, n) { a <- P; for (i in seq_len(n)) a <- a * (1 + r); a },
    inputs = list(list(1000, 0.05, 30))),
  npv = list(
    f = function(cf, r) { s <- 0; for (t in seq_along(cf)) s <- s + cf[t] / (1 + r)^(t - 1); s },
    inputs = list(list(c(-100, 30, 40, 50), 0.08))),
  irr_bisection = list(
    f = function(cf) {
      lo <- -0.99; hi <- 1
      for (it in 1:100) {
        mid <- (lo + hi) / 2; s <- 0
        for (t in seq_along(cf)) s <- s + cf[t] / (1 + mid)^(t - 1)
        if (s > 0) lo <- mid else hi <- mid
      }
      (lo + hi) / 2
    },
    inputs = list(list(c(-100, 30, 40, 50)))),
  annuity_payment = list(
    f = function(P, r, n) P * r / (1 - (1 + r)^(-n)),
    inputs = list(list(200000, 0.004, 360))),
  garch11_variance = list(
    f = function(e, omega, a, b) {
      n <- length(e); h <- numeric(n); h[1] <- mean(e^2)
      for (t in 2:n) h[t] <- omega + a * e[t - 1]^2 + b * h[t - 1]
      h
    },
    inputs = list(list(e5, 0.05, 0.1, 0.85))),
  arma_residuals = list(
    f = function(x, phi, theta) {
      n <- length(x); e <- numeric(n)
      for (t in 2:n) e[t] <- x[t] - phi * x[t - 1] - theta * e[t - 1]
      e
    },
    inputs = list(list(e5, 0.5, 0.3))),
  autocorrelation = list(
    f = function(x, k) { n <- length(x); d <- x - mean(x); sum(d[1:(n - k)] * d[(k + 1):n]) / sum(d * d) },
    inputs = list(list(e5, 1), list(px, 3L))),
  holt_linear = list(
    f = function(x, a, b) {
      l <- x[1]; tr <- x[2] - x[1]; f <- numeric(length(x))
      for (t in 2:length(x)) {
        f[t] <- l + tr
        ln <- a * x[t] + (1 - a) * (l + tr)
        tr <- b * (ln - l) + (1 - b) * tr
        l <- ln
      }
      f
    },
    inputs = list(list(px, 0.4, 0.2))),
  euler_decay = list(
    f = function(y0, h, n) { y <- y0; for (i in seq_len(n)) y <- y + h * (-2 * y); y },
    inputs = list(list(1, 0.01, 100))),
  rk4_decay = list(
    f = function(y0, h, n) {
      y <- y0
      for (i in seq_len(n)) {
        k1 <- -2 * y; k2 <- -2 * (y + h / 2 * k1); k3 <- -2 * (y + h / 2 * k2); k4 <- -2 * (y + h * k3)
        y <- y + h / 6 * (k1 + 2 * k2 + 2 * k3 + k4)
      }
      y
    },
    inputs = list(list(1, 0.1, 10))),
  fixed_point = list(
    f = function(x0) { x <- x0; repeat { nx <- exp(-x); if (abs(nx - x) < 1e-14) break; x <- nx }; nx },
    inputs = list(list(0.5))),
  golden_section = list(
    f = function(a, b) {
      g <- (sqrt(5) - 1) / 2; c1 <- b - g * (b - a); d <- a + g * (b - a)
      for (i in 1:80) {
        if ((c1 - 2)^2 < (d - 2)^2) b <- d else a <- c1
        c1 <- b - g * (b - a); d <- a + g * (b - a)
      }
      (a + b) / 2
    },
    inputs = list(list(0, 5))),
  secant_root = list(
    f = function(x0, x1) {
      for (i in 1:30) {
        f0 <- x0^2 - 2; f1 <- x1^2 - 2
        if (f1 == f0) break
        x2 <- x1 - f1 * (x1 - x0) / (f1 - f0); x0 <- x1; x1 <- x2
      }
      x1
    },
    inputs = list(list(1, 2))),
  power_iteration = list(
    f = function(A, iters) {
      v <- matrix(0, nrow(A), 1); v[1, 1] <- 1; lam <- 0
      for (i in seq_len(iters)) { w <- A %*% v; lam <- sqrt(sum(w * w)); v <- w / lam }
      lam
    },
    inputs = list(list(A3, 50))),
  jacobi_solve = list(
    f = function(A, b, iters) {
      n <- length(b); x <- numeric(n)
      for (it in seq_len(iters)) {
        xn <- numeric(n)
        for (i in seq_len(n)) { s <- b[i]; for (j in seq_len(n)) if (j != i) s <- s - A[i, j] * x[j]; xn[i] <- s / A[i, i] }
        x <- xn
      }
      x
    },
    inputs = list(list(A3, b3, 40))),
  gauss_seidel = list(
    f = function(A, b, iters) {
      n <- length(b); x <- numeric(n)
      for (it in seq_len(iters)) for (i in seq_len(n)) {
        s <- b[i]; for (j in seq_len(n)) if (j != i) s <- s - A[i, j] * x[j]; x[i] <- s / A[i, i]
      }
      x
    },
    inputs = list(list(A3, b3, 25))),
  lu_determinant = list(
    f = function(A) {
      n <- nrow(A); U <- A; det <- 1
      for (k in seq_len(n)) {
        piv <- U[k, k]; det <- det * piv
        if (k < n) for (i in (k + 1):n) { f <- U[i, k] / piv; for (j in k:n) U[i, j] <- U[i, j] - f * U[k, j] }
      }
      det
    },
    inputs = list(list(A3))),
  outer_product = list(
    f = function(x, y) {
      m <- matrix(0, length(x), length(y))
      for (i in seq_along(x)) for (j in seq_along(y)) m[i, j] <- x[i] * y[j]
      m
    },
    inputs = list(list(b3, c(0.5, -1)))),
  identity_matrix = list(
    f = function(n) { m <- matrix(0, n, n); for (i in seq_len(n)) m[i, i] <- 1; m },
    inputs = list(list(4))),
  hat_diagonal = list(
    f = function(X) {
      H <- X %*% solve(crossprod(X)) %*% t(X); d <- numeric(nrow(X))
      for (i in seq_len(nrow(X))) d[i] <- H[i, i]
      d
    },
    inputs = list(list(Xl))),
  mahalanobis_loop = list(
    f = function(X, mu, S) {
      Si <- solve(S); n <- nrow(X); out <- numeric(n)
      for (i in seq_len(n)) { d <- X[i, ] - mu; out[i] <- sum(d * (Si %*% d)) }
      out
    },
    inputs = list(list(P2, c(0, 0), crossprod(P2) / 9))),
  quadratic_form = list(
    f = function(x, A) sum(x * (A %*% x)),
    inputs = list(list(b3, A3))),
  weighted_moments = list(
    f = function(x, w) { m <- sum(w * x) / sum(w); c(m, sum(w * (x - m)^2) / sum(w)) },
    inputs = list(list(xs5, abs(xs5)))),
  logit_irls = list(
    f = function(X, y, iters) {
      b <- matrix(0, ncol(X), 1)
      for (it in seq_len(iters)) {
        eta <- X %*% b; p <- 1 / (1 + exp(-eta)); W <- p * (1 - p); z <- eta + (y - p) / W
        XW <- X
        for (i in seq_len(nrow(X))) for (j in seq_len(ncol(X))) XW[i, j] <- X[i, j] * W[i]
        b <- solve(crossprod(XW, X), crossprod(XW, z))
      }
      b
    },
    inputs = list(list(Xl, yl, 8))),
  kmeans_1d = list(
    f = function(x, c1, c2) {
      for (it in 1:20) {
        s1 <- 0; n1 <- 0; s2 <- 0; n2 <- 0
        for (v in x) if (abs(v - c1) <= abs(v - c2)) { s1 <- s1 + v; n1 <- n1 + 1 } else { s2 <- s2 + v; n2 <- n2 + 1 }
        c1 <- s1 / n1; c2 <- s2 / n2
      }
      c(c1, c2)
    },
    inputs = list(list(two_groups, 0, 5))),
  histogram_counts = list(
    f = function(x, breaks) {
      k <- length(breaks) - 1L; cnt <- integer(k)
      for (v in x) for (b in seq_len(k)) if (v >= breaks[b] && v < breaks[b + 1L]) cnt[b] <- cnt[b] + 1L
      cnt
    },
    inputs = list(list(xs5, c(-3, -1, 0, 1, 3)))),
  quantile_sorted = list(
    f = function(xs, p) {
      n <- length(xs); h <- (n - 1) * p + 1; lo <- floor(h); hi <- ceiling(h)
      xs[lo] + (h - lo) * (xs[hi] - xs[lo])
    },
    inputs = list(list(sort(xs5), 0.25), list(sort(xs5), 0.9))),
  rank_simple = list(
    f = function(x) {
      n <- length(x); r <- numeric(n)
      for (i in seq_len(n)) { c1 <- 0; for (j in seq_len(n)) if (x[j] < x[i]) c1 <- c1 + 1; r[i] <- c1 + 1 }
      r
    },
    inputs = list(list(xs5))),
  spearman = list(
    f = function(x, y) {
      n <- length(x); rx <- numeric(n); ry <- numeric(n)
      for (i in seq_len(n)) {
        a <- 0; b <- 0
        for (j in seq_len(n)) { if (x[j] < x[i]) a <- a + 1; if (y[j] < y[i]) b <- b + 1 }
        rx[i] <- a + 1; ry[i] <- b + 1
      }
      1 - 6 * sum((rx - ry)^2) / (n * (n^2 - 1))
    },
    inputs = list(list(xs5, xs5^3 + stats::rnorm(40)))),
  sign_counts = list(
    f = function(x, m) c(sum(x > m), sum(x < m)),
    inputs = list(list(xs5, 0))),
  runs_count = list(
    f = function(x) { r <- 1L; for (i in 2:length(x)) if ((x[i] > 0) != (x[i - 1] > 0)) r <- r + 1L; r },
    inputs = list(list(xs5))),
  longest_run = list(
    f = function(b) { best <- 0L; cur <- 0L; for (v in b) { if (v) cur <- cur + 1L else cur <- 0L; if (cur > best) best <- cur }; best },
    inputs = list(list(c(TRUE, TRUE, FALSE, TRUE, TRUE, TRUE, FALSE)))),
  collatz_peak = list(
    f = function(n) { m <- n; while (n != 1) { if (n %% 2 == 0) n <- n / 2 else n <- 3 * n + 1; if (n > m) m <- n }; m },
    inputs = list(list(27), list(97))),
  fizzbuzz_count = list(
    f = function(n) { k <- 0L; for (i in seq_len(n)) if (i %% 3L == 0L || i %% 5L == 0L) k <- k + 1L; k },
    inputs = list(list(100L))),
  pascal_row = list(
    f = function(n) { row <- numeric(n + 1); row[1] <- 1; for (i in seq_len(n)) for (j in (i + 1):2) row[j] <- row[j] + row[j - 1]; row },
    inputs = list(list(10))),
  binomial_coefficient = list(
    f = function(n, k) { r <- 1; for (i in seq_len(k)) r <- r * (n - k + i) / i; r },
    inputs = list(list(10, 3), list(52, 5))),
  factorial_loop = list(
    f = function(n) { r <- 1; for (i in seq_len(n)) r <- r * i; r },
    inputs = list(list(10), list(170))),
  fibonacci_int = list(
    f = function(n) { a <- 0L; b <- 1L; for (i in seq_len(n)) { nx <- a + b; a <- b; b <- nx }; a },
    inputs = list(list(40L))),
  triangle_numbers = list(
    f = function(n) { out <- integer(n); s <- 0L; for (i in seq_len(n)) { s <- s + i; out[i] <- s }; out },
    inputs = list(list(100L))),
  prime_factor_count = list(
    f = function(n) { k <- 0L; d <- 2L; while (n > 1L) { if (n %% d == 0L) { n <- n %/% d; k <- k + 1L } else d <- d + 1L }; k },
    inputs = list(list(360L), list(97L))),
  perfect_numbers = list(
    f = function(lim) {
      cnt <- 0L
      for (n in 2:lim) {
        s <- 1L; d <- 2L
        while (d * d <= n) { if (n %% d == 0L) { s <- s + d; if (d * d != n) s <- s + n %/% d }; d <- d + 1L }
        if (s == n) cnt <- cnt + 1L
      }
      cnt
    },
    inputs = list(list(1000L))),
  vector_norms = list(
    f = function(x) c(sum(abs(x)), sqrt(sum(x^2)), max(abs(x))),
    inputs = list(list(xs5))),
  cosine_similarity = list(
    f = function(a, b) sum(a * b) / (sqrt(sum(a^2)) * sqrt(sum(b^2))),
    inputs = list(list(xs5, e5[1:40]))),
  distance_matrix = list(
    f = function(X) {
      n <- nrow(X); D <- matrix(0, n, n)
      for (i in seq_len(n)) for (j in seq_len(n)) D[i, j] <- sqrt(sum((X[i, ] - X[j, ])^2))
      D
    },
    inputs = list(list(P2))),
  nearest_neighbour = list(
    f = function(X, q) {
      best <- 0L; bd <- Inf
      for (i in seq_len(nrow(X))) { d <- sum((X[i, ] - q)^2); if (d < bd) { bd <- d; best <- i } }
      best
    },
    inputs = list(list(P2, c(0, 0)))),
  park_miller = list(
    f = function(seed, n) {
      s <- seed; out <- numeric(n)
      for (i in seq_len(n)) { s <- (16807 * s) %% 2147483647; out[i] <- s / 2147483647 }
      out
    },
    inputs = list(list(12345, 20))),
  dice_frequencies = list(
    f = function(n) { cnt <- numeric(6); for (i in seq_len(n)) { k <- floor(runif(1) * 6) + 1; cnt[k] <- cnt[k] + 1 }; cnt / n },
    seed = 31L, inputs = list(list(6000))),
  coupon_collector = list(
    f = function(n) {
      seen <- logical(n); cnt <- 0L; draws <- 0L
      while (cnt < n) { k <- floor(runif(1) * n) + 1; draws <- draws + 1L; if (!seen[k]) { seen[k] <- TRUE; cnt <- cnt + 1L } }
      draws
    },
    seed = 32L, inputs = list(list(20))),
  birthday_problem = list(
    f = function(B, k) {
      hits <- 0L
      for (b in seq_len(B)) {
        days <- logical(365); dup <- FALSE
        for (i in seq_len(k)) { d <- floor(runif(1) * 365) + 1; if (days[d]) dup <- TRUE; days[d] <- TRUE }
        if (dup) hits <- hits + 1L
      }
      hits / B
    },
    seed = 33L, inputs = list(list(200, 23))),
  metropolis_normal = list(
    f = function(n, s) {
      x <- numeric(n)
      for (i in 2:n) {
        prop <- x[i - 1] + rnorm(1, 0, s)
        if (log(runif(1)) < (x[i - 1]^2 - prop^2) / 2) x[i] <- prop else x[i] <- x[i - 1]
      }
      c(mean(x), sqrt(mean(x^2) - mean(x)^2))
    },
    seed = 34L, inputs = list(list(2000, 1))),
  ornstein_uhlenbeck = list(
    f = function(n, theta, mu, sigma, dt) {
      x <- numeric(n); x[1] <- mu
      for (i in 2:n) x[i] <- x[i - 1] + theta * (mu - x[i - 1]) * dt + sigma * sqrt(dt) * rnorm(1)
      x
    },
    seed = 35L, inputs = list(list(300, 0.7, 1.5, 0.3, 0.01)))
)
