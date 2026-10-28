# Phase 2, third engine with reflective constructs: aw_boot_pls() against
# seminr::bootstrap_model() on the full ECSI model of seminr's mobi data with
# all seven constructs reflective, which seminr estimates by consistent PLS
# (PLSc). Same model, same seed; the compiled engine must reproduce seminr's
# bootstrap arrays, including any resamples seminr leaves out.
# Usage (from the repository root, with ARWAD_GOOSE set):
#   Rscript bench/phase2/pls_plsc_bench.R
# Writes bench/phase2/pls_plsc_timing.csv; REPORT.md interprets it.

suppressPackageStartupMessages({
  library(arwad)
  library(bench)
  library(seminr)
})
options(arwad.cache_dir = file.path(tempdir(), "arwad-bench-cache"))
stopifnot(aw_toolchain()$ok)

mm <- constructs(
  reflective("Image", multi_items("IMAG", 1:5)),
  reflective("Expectation", multi_items("CUEX", 1:3)),
  reflective("Quality", multi_items("PERQ", 1:7)),
  reflective("Value", multi_items("PERV", 1:2)),
  reflective("Satisfaction", multi_items("CUSA", 1:3)),
  reflective("Complaints", single_item("CUSCO")),
  reflective("Loyalty", multi_items("CUSL", 1:3)))
sm <- relationships(
  paths(from = "Image", to = c("Expectation", "Satisfaction", "Loyalty")),
  paths(from = "Expectation", to = c("Quality", "Value", "Satisfaction")),
  paths(from = "Quality", to = c("Value", "Satisfaction")),
  paths(from = "Value", to = "Satisfaction"),
  paths(from = "Satisfaction", to = c("Complaints", "Loyalty")),
  paths(from = "Complaints", to = "Loyalty"))
# The Primer's maxIt (3,000); bootstrap_model() estimates the resamples with
# seminr's default 300 whatever the model says, and so does aw_boot_pls().
model <- suppressMessages(estimate_pls(mobi, mm, sm, maxIt = 3000L))
B <- 1000L
seed <- 123L
cores <- parallel::detectCores()
seminr_boot <- function(nc, nb = B) suppressWarnings(suppressMessages(bootstrap_model(model, nboot = nb, cores = nc, seed = seed)))
arwad_boot <- function(nc, nb = B) suppressMessages(aw_boot_pls(model, nboot = nb, seed = seed, cores = nc))

t0 <- proc.time()[["elapsed"]]; first <- arwad_boot(1L); first_s <- proc.time()[["elapsed"]] - t0
stopifnot(first$native)
ref <- seminr_boot(NULL)
ref1 <- seminr_boot(1L)
exact <- c("boot_paths", "boot_loadings", "boot_weights", "boot_total_paths", "boots")
same <- vapply(exact, function(f) identical(first[[f]], ref[[f]], num.eq = FALSE) && identical(first[[f]], ref1[[f]], num.eq = FALSE), NA)
ok <- !is.na(ref$boot_HTMT)
htmt_rel <- max(abs(first$boot_HTMT[ok] - ref$boot_HTMT[ok]) / ref$boot_HTMT[ok])
# HTMT distances in units in the last place (the spacing of doubles at seminr's value).
htmt_ulps <- table(abs(first$boot_HTMT[ok] - ref$boot_HTMT[ok]) / 2^(floor(log2(ref$boot_HTMT[ok])) - 52))

bm <- bench::mark(
  arwad = arwad_boot(1L),
  arwad_all_cores = arwad_boot(cores),
  seminr_all_cores = seminr_boot(NULL),
  seminr_one_core = seminr_boot(1L),
  check = FALSE, min_iterations = 3, max_iterations = 3, time_unit = "ms", filter_gc = FALSE)
med <- as.numeric(bm$median)
res <- data.frame(contender = as.character(bm$expression), replicates = B, median_ms = signif(med, 4),
                  arwad_speedup = round(med / med[1], 2))

# The Primer's setting, 10,000 resamples: one round, seminr first.
ts <- system.time(bigs <- seminr_boot(NULL, 10000L))[["elapsed"]]
t1 <- system.time(big <- arwad_boot(1L, 10000L))[["elapsed"]]
tc <- system.time(bigc <- arwad_boot(cores, 10000L))[["elapsed"]]
same10 <- all(vapply(exact, function(f) identical(big[[f]], bigs[[f]], num.eq = FALSE) && identical(bigc[[f]], bigs[[f]], num.eq = FALSE), NA))
t10 <- round(c(arwad = t1, arwad_all_cores = tc, seminr_all_cores = ts) * 1000)
res <- rbind(res, data.frame(contender = names(t10), replicates = 10000L, median_ms = unname(t10),
                             arwad_speedup = round(unname(t10) / t10[["arwad"]], 2)))
print(res, row.names = FALSE)
cat(sprintf(paste0("\nFull ECSI model, all constructs reflective (consistent PLS): 7 constructs, 24 indicators, n = %d, maxIt = 3000; ",
                   "cores = %d; first call (build) %.2f s\n",
                   "resamples kept by seminr: %d of %d, %d of 10,000\n",
                   "identical to seminr (paths, loadings, weights, total effects, boots): %s; at 10,000 resamples: %s\n",
                   "HTMT: largest relative difference %.2e; values by distance in units in the last place: %s\n"),
            nrow(mobi), cores, first_s, ref$boots, B, bigs$boots, paste(names(same), same, collapse = ", "), same10, htmt_rel,
            paste(names(htmt_ulps), htmt_ulps, sep = ": ", collapse = ", ")))
cat(R.version.string, "| seminr", as.character(packageVersion("seminr")), "| Goose", aw_toolchain()$version, "|",
    utils::sessionInfo()$running, "\n")
write.csv(res, file.path("bench", "phase2", "pls_plsc_timing.csv"), row.names = FALSE)
