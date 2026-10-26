# Equivalence corpus, compiler slice 2b: matrices.
#
# Matrix arguments (with only a dim attribute), matrix(), m[i, j], rows and
# columns, t(), dimensions, and elementwise arithmetic that keeps dimensions.
# Same rules as slice1.R: native, and bit for bit equal to GNU R.

set.seed(20261028)
A <- matrix(stats::rnorm(12), 3, 4)
B <- matrix(stats::rnorm(12), 3, 4)
I3 <- matrix(sample(-9:9, 9, TRUE), 3, 3)
L <- matrix(c(TRUE, FALSE, NA, TRUE), 2, 2)

list(
  mat_elementwise = list(
    f = function(a, b) a * b + 2 * a - b / 3,
    inputs = list(list(A, B), list(I3, I3), list(A, 1.5))),
  mat_index_loop = list(
    f = function(m) { s <- 0; for (i in seq_len(nrow(m))) for (j in seq_len(ncol(m))) s <- s + m[i, j] * i - j; s },
    inputs = list(list(A), list(I3))),
  mat_build = list(
    f = function(n) { m <- matrix(0, n, n); for (i in seq_len(n)) for (j in seq_len(n)) m[i, j] <- 1 / (i + j - 1); m },
    inputs = list(list(4), list(1L))),
  mat_rows_cols = list(
    f = function(m, i, j) c(sum(m[i, ]), sum(m[, j]), m[i, j]),
    inputs = list(list(A, 2, 3), list(I3, 1L, 3L))),
  mat_transpose = list(
    f = function(m) t(m) * 2,
    inputs = list(list(A), list(I3), list(L))),
  mat_from_vec = list(
    f = function(x, r) matrix(x, nrow = r),
    inputs = list(list(as.numeric(1:12), 3), list(1:6, 2L), list(c(TRUE, NA), 2))),
  mat_fill = list(
    f = function(v, r, c) matrix(v, r, c),
    inputs = list(list(0.5, 2, 3), list(NA_real_, 1, 1), list(1:2, 4, 2))),
  mat_dims = list(
    f = function(m) c(nrow(m), ncol(m), length(m), dim(m)),
    inputs = list(list(A), list(I3))),
  mat_col_means = list(
    f = function(m) { out <- numeric(ncol(m)); for (j in seq_len(ncol(m))) out[j] <- mean(m[, j]); out },
    inputs = list(list(A), list(I3))),
  mat_vec_loop = list(
    f = function(m, v) {
      out <- numeric(nrow(m))
      for (i in seq_len(nrow(m))) { s <- 0; for (j in seq_len(ncol(m))) s <- s + m[i, j] * v[j]; out[i] <- s }
      out
    },
    inputs = list(list(A, c(1, -1, 2, 0.5)), list(I3, c(1L, 2L, 3L)))),
  mat_logical = list(
    f = function(m) sum(m > 0) + sum(is.na(m)),
    inputs = list(list(A), list(L), list(I3))),
  mat_vector_ops = list(
    f = function(m, v) m - v,
    inputs = list(list(A, c(1, 2, 3)), list(A, 0.5), list(I3, 1:9)))
)
