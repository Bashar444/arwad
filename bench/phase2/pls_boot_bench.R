# Phase 2, third engine: aw_boot_pls() against seminr::bootstrap_model(), the
# reference implementation of the PLS-SEM bootstrap in R. Same model, same
# seed; the compiled engine must reproduce seminr's bootstrap arrays.
# Usage (from the repository root, with ARWAD_GOOSE set):
#   Rscript bench/phase2/pls_boot_bench.R
# Writes bench/phase2/pls_boot_timing.csv; REPORT.md interprets it.

suppressPackageStartupMessages({
  library(arwad)
  library(bench)
  library(seminr)
})
options(arwad.cache_dir = file.path(tempdir(), "arwad-bench-cache"))
stopifnot(aw_toolchain()$ok)

# The European Customer Satisfaction Index model on seminr's mobile phone
# data (Tenenhaus et al., 2005): 7 constructs, 24 indicators, 250 cases.
mm <- constructs(
  composite("Image", multi_items("IMAG", 1:5)), composite("Expectation", multi_items("CUEX", 1:3)),
  composite("Quality", multi_items("PERQ", 1:7)), composite("Value", multi_items("PERV", 1:2)),
  composite("Satisfaction", multi_items("CUSA", 1:3)), composite("Complaints", single_item("CUSCO")),
  composite("Loyalty", multi_items("CUSL", 1:3)))
sm <- relationships(
  paths(from = "Image", to = c("Expectation", "Satisfaction", "Loyalty")),
  paths(from = "Expectation", to = c("Quality", "Value", "Satisfaction")),
  paths(from = "Quality", to = c("Value", "Satisfaction")),
  paths(from = "Value", to = "Satisfaction"),
  paths(from = "Satisfaction", to = c("Complaints", "Loyalty")),
  paths(from = "Complaints", to = "Loyalty"))
model <- suppressMessages(estimate_pls(mobi, mm, sm))
B <- 1000L
seed <- 123L
cores <- parallel::detectCores()

same_algorithm_in_r <- compiler::cmpfun(function(model, B, seed) {
  s <- arwad:::aw_pls_spec(model)
  idx <- matrix(0L, nrow(s$X), B)
  for (b in seq_len(B)) {
    set.seed(seed + b)
    idx[, b] <- sample.int(nrow(s$X), replace = TRUE)
  }
  arwad:::aw_pls_call(arwad:::aw_pls_kernel, s, idx)
})
seminr_boot <- function(nc, nb = B) suppressMessages(bootstrap_model(model, nboot = nb, cores = nc, seed = seed))

t0 <- proc.time()[["elapsed"]]; first <- aw_boot_pls(model, nboot = B, seed = seed); first_s <- proc.time()[["elapsed"]] - t0
ref <- seminr_boot(NULL)
ref1 <- seminr_boot(1L)
exact <- c("boot_paths", "boot_loadings", "boot_weights", "boot_total_paths")
same <- vapply(exact, function(f) identical(first[[f]], ref[[f]], num.eq = FALSE) && identical(first[[f]], ref1[[f]], num.eq = FALSE), NA)
ok <- !is.na(ref$boot_HTMT)
htmt_rel <- max(abs(first$boot_HTMT[ok] - ref$boot_HTMT[ok]) / ref$boot_HTMT[ok])
htmt_exact <- mean(first$boot_HTMT[ok] == ref$boot_HTMT[ok])
# HTMT distances in units in the last place (the spacing of doubles at seminr's value).
htmt_ulps <- table(abs(first$boot_HTMT[ok] - ref$boot_HTMT[ok]) / 2^(floor(log2(ref$boot_HTMT[ok])) - 52))

two <- aw_boot_pls(model, nboot = B, seed = seed, cores = cores)
same <- c(same, all_cores = all(vapply(exact, function(f) identical(two[[f]], first[[f]], num.eq = FALSE), NA)))

bm <- bench::mark(
  arwad = aw_boot_pls(model, nboot = B, seed = seed),
  arwad_all_cores = aw_boot_pls(model, nboot = B, seed = seed, cores = cores),
  seminr_all_cores = seminr_boot(NULL),
  seminr_one_core = seminr_boot(1L),
  same_algorithm_in_r = same_algorithm_in_r(model, B, seed),
  check = FALSE, min_iterations = 3, max_iterations = 5, time_unit = "ms", filter_gc = FALSE)
med <- as.numeric(bm$median)
res <- data.frame(contender = as.character(bm$expression), replicates = B, median_ms = signif(med, 4),
                  arwad_speedup = round(med / med[1], 2))

# The Primer's setting: 10,000 resamples, three rounds (seminr first in each,
# on a machine that has rested). seminr's time varied from 212 to 655 s on
# the laptop, so the table keeps its median and its fastest run; headline
# ratios use seminr's fastest run against Arwad's median.
r10 <- t(vapply(1:3, function(k) {
  ts <- system.time(bigs <- seminr_boot(NULL, 10000L))[["elapsed"]]
  t1 <- system.time(big <- aw_boot_pls(model, nboot = 10000L, seed = seed))[["elapsed"]]
  tc <- system.time(bigc <- aw_boot_pls(model, nboot = 10000L, seed = seed, cores = cores))[["elapsed"]]
  stopifnot(all(vapply(exact, function(f) identical(big[[f]], bigs[[f]], num.eq = FALSE) &&
                         identical(bigc[[f]], bigs[[f]], num.eq = FALSE), NA)))
  c(seminr = ts, arwad = t1, arwad_all_cores = tc)
}, numeric(3)))
print(r10)
same10 <- TRUE
m10 <- round(apply(r10, 2, stats::median) * 1000)
res <- rbind(res, data.frame(contender = c("arwad", "arwad_all_cores", "seminr_all_cores", "seminr_all_cores_fastest"),
                             replicates = 10000L, median_ms = c(m10[["arwad"]], m10[["arwad_all_cores"]], m10[["seminr"]], min(r10[, "seminr"]) * 1000),
                             arwad_speedup = round(c(m10[["arwad"]], m10[["arwad_all_cores"]], m10[["seminr"]], min(r10[, "seminr"]) * 1000) / m10[["arwad"]], 2)))
print(res, row.names = FALSE)
cat(sprintf(paste0("\nECSI model: 7 constructs, 24 indicators, n = 250; cores = %d (seminr's default and arwad_all_cores); first call (build) %.2f s\n",
                   "identical to seminr (paths, loadings, weights, total effects): %s; at 10,000 resamples: %s\n",
                   "HTMT: %.1f%% of values identical, largest relative difference %.2e; by units in the last place: %s\n"),
            cores, first_s, paste(names(same), same, collapse = ", "), same10, 100 * htmt_exact, htmt_rel,
            paste(names(htmt_ulps), htmt_ulps, sep = ": ", collapse = ", ")))
cat(R.version.string, "| seminr", as.character(packageVersion("seminr")), "| Goose", aw_toolchain()$version, "|",
    utils::sessionInfo()$running, "\n")
write.csv(res, file.path("bench", "phase2", "pls_boot_timing.csv"), row.names = FALSE)
