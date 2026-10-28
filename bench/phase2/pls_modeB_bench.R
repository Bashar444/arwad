# Phase 2, third engine with formative constructs: aw_boot_pls() against
# seminr::bootstrap_model() on the extended corporate reputation model of
# Hair, Hult, Ringle and Sarstedt's Primer, whose four driver constructs
# (QUAL, PERF, CSOR, ATTR) are Mode B. Same model, same seed; the compiled
# engine must reproduce seminr's bootstrap arrays.
# Usage (from the repository root, with ARWAD_GOOSE set):
#   Rscript bench/phase2/pls_modeB_bench.R
# Writes bench/phase2/pls_modeB_timing.csv; REPORT.md interprets it.

suppressPackageStartupMessages({
  library(arwad)
  library(bench)
  library(seminr)
})
options(arwad.cache_dir = file.path(tempdir(), "arwad-bench-cache"))
stopifnot(aw_toolchain()$ok)

mm <- constructs(
  composite("QUAL", multi_items("qual_", 1:8), weights = mode_B),
  composite("PERF", multi_items("perf_", 1:5), weights = mode_B),
  composite("CSOR", multi_items("csor_", 1:5), weights = mode_B),
  composite("ATTR", multi_items("attr_", 1:3), weights = mode_B),
  composite("COMP", multi_items("comp_", 1:3)), composite("LIKE", multi_items("like_", 1:3)),
  composite("CUSA", single_item("cusa")), composite("CUSL", multi_items("cusl_", 1:3)))
sm <- relationships(
  paths(from = c("QUAL", "PERF", "CSOR", "ATTR"), to = c("COMP", "LIKE")),
  paths(from = c("COMP", "LIKE"), to = c("CUSA", "CUSL")),
  paths(from = "CUSA", to = "CUSL"))
# The Primer's maxIt (3,000).
model <- suppressMessages(estimate_pls(corp_rep_data, mm, sm, maxIt = 3000L))
B <- 1000L
seed <- 123L
cores <- parallel::detectCores()
seminr_boot <- function(nc, nb = B) suppressMessages(bootstrap_model(model, nboot = nb, cores = nc, seed = seed))

t0 <- proc.time()[["elapsed"]]; first <- aw_boot_pls(model, nboot = B, seed = seed); first_s <- proc.time()[["elapsed"]] - t0
stopifnot(first$native)
ref <- seminr_boot(NULL)
ref1 <- seminr_boot(1L)
exact <- c("boot_paths", "boot_loadings", "boot_weights", "boot_total_paths")
same <- vapply(exact, function(f) identical(first[[f]], ref[[f]], num.eq = FALSE) && identical(first[[f]], ref1[[f]], num.eq = FALSE), NA)
ok <- !is.na(ref$boot_HTMT)
htmt_rel <- max(abs(first$boot_HTMT[ok] - ref$boot_HTMT[ok]) / ref$boot_HTMT[ok])
# HTMT distances in units in the last place (the spacing of doubles at seminr's value).
htmt_ulps <- table(abs(first$boot_HTMT[ok] - ref$boot_HTMT[ok]) / 2^(floor(log2(ref$boot_HTMT[ok])) - 52))

bm <- bench::mark(
  arwad = aw_boot_pls(model, nboot = B, seed = seed),
  arwad_all_cores = aw_boot_pls(model, nboot = B, seed = seed, cores = cores),
  seminr_all_cores = seminr_boot(NULL),
  seminr_one_core = seminr_boot(1L),
  check = FALSE, min_iterations = 3, max_iterations = 3, time_unit = "ms", filter_gc = FALSE)
med <- as.numeric(bm$median)
res <- data.frame(contender = as.character(bm$expression), replicates = B, median_ms = signif(med, 4),
                  arwad_speedup = round(med / med[1], 2))

# The Primer's setting, 10,000 resamples: one round, seminr first.
ts <- system.time(bigs <- seminr_boot(NULL, 10000L))[["elapsed"]]
t1 <- system.time(big <- aw_boot_pls(model, nboot = 10000L, seed = seed))[["elapsed"]]
tc <- system.time(bigc <- aw_boot_pls(model, nboot = 10000L, seed = seed, cores = cores))[["elapsed"]]
same10 <- all(vapply(exact, function(f) identical(big[[f]], bigs[[f]], num.eq = FALSE) && identical(bigc[[f]], bigs[[f]], num.eq = FALSE), NA))
t10 <- round(c(arwad = t1, arwad_all_cores = tc, seminr_all_cores = ts) * 1000)
res <- rbind(res, data.frame(contender = names(t10), replicates = 10000L, median_ms = unname(t10),
                             arwad_speedup = round(unname(t10) / t10[["arwad"]], 2)))
print(res, row.names = FALSE)
cat(sprintf(paste0("\nExtended corporate reputation model (Mode B drivers): 8 constructs, 31 indicators, n = %d, maxIt = 3000; ",
                   "cores = %d; first call (build) %.2f s\n",
                   "identical to seminr (paths, loadings, weights, total effects): %s; at 10,000 resamples: %s\n",
                   "HTMT: largest relative difference %.2e; values by distance in units in the last place: %s\n"),
            nrow(corp_rep_data), cores, first_s, paste(names(same), same, collapse = ", "), same10, htmt_rel,
            paste(names(htmt_ulps), htmt_ulps, sep = ": ", collapse = ", ")))
cat(R.version.string, "| seminr", as.character(packageVersion("seminr")), "| Goose", aw_toolchain()$version, "|",
    utils::sessionInfo()$running, "\n")
write.csv(res, file.path("bench", "phase2", "pls_modeB_timing.csv"), row.names = FALSE)
