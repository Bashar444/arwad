# Compiler slice 1 benchmark: aw_compile() against GNU R's byte-compiled
# closures (R's JIT compiles loops anyway, so this is the fair baseline).
# Usage (from the repository root, with ARWAD_GOOSE set):
#   Rscript bench/phase1/slice1_bench.R
# Writes bench/phase1/slice1_timing.csv; REPORT.md interprets it.

suppressPackageStartupMessages({
  library(arwad)
  library(bench)
})
options(arwad.cache_dir = file.path(tempdir(), "arwad-bench-cache"))
stopifnot(aw_toolchain()$ok)

set.seed(20261026)
x1e6 <- rnorm(1e6)

cases <- list(
  sum_sq = list(f = function(x) { s <- 0; for (i in seq_along(x)) s <- s + x[i]^2; s },
                args = list(x1e6)),
  cumsum_loop = list(f = function(x) { out <- numeric(length(x)); acc <- 0; for (i in seq_along(x)) { acc <- acc + x[i]; out[i] <- acc }; out },
                     args = list(x1e6)),
  prime_count = list(f = function(n) { count <- 0L; for (k in 2:n) { is_p <- TRUE; d <- 2L; while (d * d <= k) { if (k %% d == 0L) { is_p <- FALSE; break }; d <- d + 1L }; if (is_p) count <- count + 1L }; count },
                     args = list(200000L)),
  nested_loops = list(f = function(n) { s <- 0; for (i in seq_len(n)) for (j in seq_len(i)) s <- s + 1 / (i * j); s },
                      args = list(2000L)),
  trapezoid = list(f = function(a, b, n) { h <- (b - a) / n; s <- 0.5 * (exp(-a * a) + exp(-b * b)); for (i in seq_len(n - 1)) { x <- a + i * h; s <- s + exp(-x * x) }; s * h },
                   args = list(0, 1, 1e6)),
  clamp_one_call = list(f = function(x, lo, hi) { if (x < lo) lo else if (x > hi) hi else x },
                        args = list(0.5, 0, 1))
)

# One-off setup in a fresh cache: learning R's compiler commands and building
# the Goose runtime object, timed with a trivial function.
t0 <- proc.time()[["elapsed"]]
invisible(aw_compile(function(x) x + 1)(1))
cat(sprintf("one-off setup (fresh cache): %.2f s\n", proc.time()[["elapsed"]] - t0))

rows <- list()
for (nm in names(cases)) {
  cs <- cases[[nm]]
  fr <- compiler::cmpfun(cs$f)
  ga <- aw_compile(cs$f, name = nm)
  t0 <- proc.time()[["elapsed"]]
  first <- do.call(ga, cs$args)
  build_s <- proc.time()[["elapsed"]] - t0
  same <- identical(first, do.call(fr, cs$args), num.eq = FALSE)
  utils::capture.output(ex <- aw_explain(ga))
  native <- isTRUE(ex$native[1]) && sum(ex$bailouts) == 0
  bm <- bench::mark(R = do.call(fr, cs$args), arwad = do.call(ga, cs$args),
                    check = FALSE, min_iterations = 5, max_iterations = 2000, time_unit = "ms",
                    filter_gc = FALSE)
  med <- as.numeric(bm$median)
  rows[[nm]] <- data.frame(case = nm, identical = same, native = native, first_call_s = round(build_s, 2),
                           r_median_ms = signif(med[1], 4), arwad_median_ms = signif(med[2], 4),
                           speedup = round(med[1] / med[2], 2),
                           r_mem_alloc = format(bm$mem_alloc[1]), arwad_mem_alloc = format(bm$mem_alloc[2]))
}
res <- do.call(rbind, rows)
print(res, row.names = FALSE)
cat("\n", R.version.string, "| Goose", aw_toolchain()$version, "|", utils::sessionInfo()$running, "\n")
write.csv(res, file.path("bench", "phase1", "slice1_timing.csv"), row.names = FALSE)
