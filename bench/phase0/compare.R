# Compare the Goose kernel's output with the GNU R reference.
# Usage (from the repository root): Rscript bench/phase0/compare.R bench/phase0/goose_O2_run1.txt

args <- commandArgs(trailingOnly = TRUE)
goose_file <- if (length(args)) args[1] else file.path("bench", "phase0", "goose_O2_run1.txt")
ref <- read.csv(file.path("bench", "phase0", "reference.csv"), colClasses = c("character", rep("numeric", 3)))

lines <- readLines(goose_file)
coef_lines <- grep("^coef ", lines, value = TRUE)
g <- do.call(rbind, lapply(strsplit(coef_lines, " "), function(f) as.numeric(f[3:5])))
colnames(g) <- c("beta", "boot_mean", "boot_sd")

rel_err <- function(a, b) max(abs(a - b) / pmax(abs(b), 1e-300))
abs_err <- function(a, b) max(abs(a - b))
result <- data.frame(
  quantity = c("beta", "boot_mean", "boot_sd"),
  max_abs_error = c(abs_err(g[, 1], ref$beta), abs_err(g[, 2], ref$boot_mean), abs_err(g[, 3], ref$boot_sd)),
  max_rel_error = c(rel_err(g[, 1], ref$beta), rel_err(g[, 2], ref$boot_mean), rel_err(g[, 3], ref$boot_sd))
)
result$passes_1e9 <- result$max_rel_error <= 1e-9
print(result, row.names = FALSE, digits = 3)
cat("checksum line:", grep("checksum", lines, value = TRUE), "\n")
if (!all(result$passes_1e9)) quit(status = 1)
