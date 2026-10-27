# Temporary diagnostic (to be removed): how GNU R rounds cov() and cor() on
# 64-bit ARM, found by compiling candidate C implementations with R's own
# default flags and comparing them with stats::cov() and stats::cor().
test_that("arm64 diagnostic: candidate cov() and cor() implementations", {
  skip_if_not(Sys.info()[["machine"]] %in% c("arm64", "aarch64"), "64-bit ARM only")
  dir <- tempfile("diag")
  dir.create(dir)
  src <- file.path(dir, "d.c")
  writeLines(c(
    "#include <math.h>",
    "typedef long double LD;",
    "static LD m_corr(const double *x, int n) { LD s = 0; for (int i = 0; i < n; i++) s += x[i]; LD t = s / n;",
    "  LD u = 0; for (int i = 0; i < n; i++) u += (x[i] - t); return t + u / n; }",
    "static LD m_plain(const double *x, int n) { LD s = 0; for (int i = 0; i < n; i++) s += x[i]; return s / n; }",
    "void d_cov(double *x, double *y, int *n, int *v, double *out) {",
    "  int N = *n, V = *v; LD mx, my, s = 0, sx = 0, sy = 0;",
    "  if (V == 1 || V == 3 || V == 5) { mx = (double) m_plain(x, N); my = (double) m_plain(y, N); }",
    "  else { mx = (double) m_corr(x, N); my = (double) m_corr(y, N); }",
    "  if (V <= 1) {",
    "    for (int k = 0; k < N; k++) s += (x[k] - mx) * (y[k] - my);",
    "    for (int k = 0; k < N; k++) sx += (x[k] - mx) * (x[k] - mx);",
    "    for (int k = 0; k < N; k++) sy += (y[k] - my) * (y[k] - my);",
    "  } else if (V <= 3) {",
    "    for (int k = 0; k < N; k++) { double a = x[k] - mx, b = y[k] - my; volatile double p = a * b; s += p; }",
    "    for (int k = 0; k < N; k++) { double a = x[k] - mx; volatile double p = a * a; sx += p; }",
    "    for (int k = 0; k < N; k++) { double b = y[k] - my; volatile double p = b * b; sy += p; }",
    "  } else {",
    "    for (int k = 0; k < N; k++) s = fma(x[k] - mx, y[k] - my, s);",
    "    for (int k = 0; k < N; k++) sx = fma(x[k] - mx, x[k] - mx, sx);",
    "    for (int k = 0; k < N; k++) sy = fma(y[k] - my, y[k] - my, sy);",
    "  }",
    "  out[0] = (double) (s / (N - 1));",
    "  double r = out[0] / ((double) sqrtl(sx / (N - 1)) * (double) sqrtl(sy / (N - 1)));",
    "  out[1] = r > 1 ? 1 : (r < -1 ? -1 : r);",
    "}"), src)
  r <- file.path(R.home("bin"), "R")
  out <- system2(r, c("CMD", "SHLIB", shQuote(src)), stdout = TRUE, stderr = TRUE)
  dll <- file.path(dir, paste0("d", .Platform$dynlib.ext))
  if (!file.exists(dll)) fail(paste("diagnostic build failed:", paste(out, collapse = " | ")))
  dyn.load(dll)
  set.seed(7)
  hits <- matrix(0L, 6L, 2L, dimnames = list(c("default/corrected", "default/plain", "unfused/corrected", "unfused/plain",
                                                "fma/corrected", "fma/plain"), c("cov", "cor")))
  for (t in seq_len(300L)) {
    n <- sample(c(2:9, 40L, 300L), 1L)
    x <- (if (t %% 3L == 0L) 1e8 else stats::runif(1L, -5, 5)) + stats::rnorm(n, 0, 10^stats::runif(1L, -3, 2))
    y <- if (t %% 4L == 0L) -2 * x + 3 else 0.4 * x + stats::rnorm(n, 0, 10^stats::runif(1L, -3, 2))
    for (v in 0:5) {
      o <- .C("d_cov", as.double(x), as.double(y), as.integer(n), as.integer(v), out = double(2))$out
      hits[v + 1L, 1L] <- hits[v + 1L, 1L] + identical(o[1L], stats::cov(x, y))
      hits[v + 1L, 2L] <- hits[v + 1L, 2L] + identical(o[2L], stats::cor(x, y))
    }
  }
  fail(paste0("arm64 diagnostic (of 300): ", paste(sprintf("%s cov=%d cor=%d", rownames(hits), hits[, 1L], hits[, 2L]), collapse = "; "),
              " | ", R.version.string, " | CFLAGS ", paste(system2(r, c("CMD", "config", "CFLAGS"), stdout = TRUE), collapse = " ")))
})
