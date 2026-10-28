# Quick timing of aw_boot_pls() on the machine it runs on, for CI: the same
# 100 resamples of the ECSI model by the compiled engine, by seminr on one
# core, and by the engine's algorithm run in GNU R. Prints a Markdown table
# (CI appends it to the job summary). The full benchmark is pls_boot_bench.R.
# Usage (from the repository root, with ARWAD_GOOSE set):
#   Rscript bench/phase2/pls_quick.R

suppressPackageStartupMessages({
  library(arwad)
  library(seminr)
})
stopifnot(aw_toolchain()$ok)
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
B <- 100L
invisible(aw_boot_pls(model, nboot = 2L, seed = 1L)) # builds the engine (not timed)
t_native <- system.time(got <- aw_boot_pls(model, nboot = B, seed = 123L))[["elapsed"]]
t_seminr <- system.time(want <- suppressMessages(bootstrap_model(model, nboot = B, cores = 1L, seed = 123L)))[["elapsed"]]
s <- arwad:::aw_pls_spec(model)
idx <- matrix(0L, nrow(s$X), B)
for (b in seq_len(B)) {
  set.seed(123L + b)
  idx[, b] <- sample.int(nrow(s$X), replace = TRUE)
}
t_r <- system.time(arwad:::aw_pls_call(arwad:::aw_pls_kernel, s, idx))[["elapsed"]]
invisible(utils::capture.output(info <- aw_explain(arwad:::aw_pls_unit())))
same <- all(vapply(c("boot_paths", "boot_loadings", "boot_weights", "boot_total_paths"),
                   function(f) identical(got[[f]], want[[f]], num.eq = FALSE), NA))
cat(sprintf(paste0("### PLS-SEM engine on %s (%s)\n\n",
                   "| %d resamples of the ECSI model | Seconds | aw_boot_pls() is |\n|---|---|---|\n",
                   "| aw_boot_pls(), native code | %.2f | |\n",
                   "| seminr::bootstrap_model(cores = 1) | %.2f | %.1f times faster |\n",
                   "| same algorithm run by GNU R | %.2f | %.1f times faster |\n\n",
                   "Native calls %d, bailouts to GNU R %d; bootstrap arrays identical to seminr: %s.\n\n"),
            R.version$platform, R.version.string, B, t_native, t_seminr, t_seminr / t_native, t_r, t_r / t_native,
            sum(info$calls), sum(info$bailouts), same))
