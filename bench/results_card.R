# Draws the results card of the README (docs/assets/results-light.svg and
# results-dark.svg) from the benchmark CSV files, so the picture always shows
# the measured numbers. Rerun after any benchmark:
#   Rscript bench/results_card.R

read_speedup <- function(file, contender, replicates = NULL) {
  d <- utils::read.csv(file.path("bench", "phase2", file))
  if (!is.null(replicates)) d <- d[d$replicates == replicates, ]
  d$arwad_speedup[d$contender == contender]
}
# Ratio of two contenders' times in one benchmark file.
ratio <- function(file, slow, fast, replicates) {
  d <- utils::read.csv(file.path("bench", "phase2", file))
  d <- d[d$replicates == replicates, ]
  d$median_ms[d$contender == slow] / d$median_ms[d$contender == fast]
}
rows <- list(
  list(group = "Regression bootstrap (OLS), 2,000 resamples", note = "vs the lm() loop most researchers write",
       x = read_speedup("ols_boot_timing.csv", "lm_formula_loop"), today = TRUE),
  list(group = NULL, note = "vs the same algorithm in plain R: compilation alone",
       x = read_speedup("ols_boot_timing.csv", "same_algorithm_in_r"), today = FALSE),
  list(group = "Logistic regression bootstrap (GLM), 1,000 resamples", note = "vs the glm() loop most researchers write",
       x = read_speedup("glm_boot_timing.csv", "glm_formula_loop"), today = TRUE),
  list(group = NULL, note = "vs the same algorithm in plain R: compilation alone",
       x = read_speedup("glm_boot_timing.csv", "same_algorithm_in_r"), today = FALSE),
  list(group = "PLS-SEM bootstrap, ECSI model, 10,000 resamples", note = "both on 4 cores, vs seminr::bootstrap_model() (its fastest of three runs)",
       x = ratio("pls_boot_timing.csv", "seminr_all_cores_fastest", "arwad_all_cores", 10000L), today = TRUE),
  list(group = NULL, note = "Arwad on 1 core, vs seminr::bootstrap_model() on 4 cores (its fastest run)",
       x = ratio("pls_boot_timing.csv", "seminr_all_cores_fastest", "arwad", 10000L), today = TRUE),
  list(group = NULL, note = "1,000 resamples on 1 core, vs the same algorithm in plain R",
       x = read_speedup("pls_boot_timing.csv", "same_algorithm_in_r", 1000L), today = FALSE))

themes <- list(
  light = c(bg = "#FFFFFF", border = "#CBD5E1", ink = "#0F172A", muted = "#475569", grid = "#E2E8F0",
            today = "#15803D", alone = "#1E3A5F", gold = "#A16207", band = "#FEFCE8"),
  dark = c(bg = "#0F172A", border = "#334155", ink = "#F1F5F9", muted = "#94A3B8", grid = "#1E293B",
           today = "#22C55E", alone = "#9DB9DC", gold = "#E3B341", band = "#1C1A12"))
sans <- "'Atkinson Hyperlegible', 'IBM Plex Sans', -apple-system, 'Segoe UI', Helvetica, Arial, sans-serif"
mono <- "'JetBrains Mono', ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"
esc <- function(s) gsub("<", "&lt;", gsub("&", "&amp;", s, fixed = TRUE), fixed = TRUE)
fmt <- function(x) sprintf("%.1f×", x)

card <- function(th) {
  W <- 960
  x0 <- 40
  bar0 <- 40
  barW <- 760
  scale <- barW / max(vapply(rows, function(r) r$x, 0))
  y <- 150
  body <- character()
  for (r in rows) {
    if (!is.null(r$group)) {
      y <- y + 30
      body <- c(body, sprintf('<text x="%d" y="%d" font-family="%s" font-size="17" font-weight="700" fill="%s">%s</text>',
                              x0, y, sans, th[["ink"]], esc(r$group)))
      y <- y + 6
    }
    w <- max(4, round(r$x * scale))
    col <- if (r$today) th[["today"]] else th[["alone"]]
    body <- c(body,
      sprintf('<text x="%d" y="%d" font-family="%s" font-size="14" fill="%s">%s</text>', bar0, y + 16, sans, th[["muted"]], esc(r$note)),
      sprintf('<rect x="%d" y="%d" width="%d" height="20" rx="4" fill="%s"/>', bar0, y + 24, w, col),
      sprintf('<text x="%d" y="%d" font-family="%s" font-size="18" font-weight="700" fill="%s">%s</text>',
              bar0 + w + 10, y + 40, mono, col, fmt(r$x)))
    y <- y + 50
  }
  y <- y + 14
  H <- y + 112
  head <- c(
    sprintf('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" role="img" aria-labelledby="t d">', W, H, W, H),
    '<title id="t">Arwad, Phase 2 results</title>',
    sprintf('<desc id="d">%s</desc>', esc(paste0("Times faster than R: ", paste(vapply(rows, function(r) paste(fmt(r$x), r$note), ""), collapse = "; "),
                                                  ". Results bit-identical to R and seminr (HTMT within four units in the last place)."))),
    sprintf('<rect x="0.5" y="0.5" width="%d" height="%d" rx="14" fill="%s" stroke="%s"/>', W - 1, H - 1, th[["bg"]], th[["border"]]),
    sprintf('<text x="%d" y="48" font-family="%s" font-size="14" font-weight="700" letter-spacing="2" fill="%s">ARWAD · R, COMPILED · PHASE 2 RESULTS</text>', x0, mono, th[["gold"]]),
    sprintf('<text x="%d" y="86" font-family="%s" font-size="28" font-weight="700" fill="%s">The same answers as R, bit for bit, from native code</text>', x0, sans, th[["ink"]]),
    sprintf('<text x="%d" y="116" font-family="%s" font-size="15" fill="%s">Times faster on one laptop (Intel i7-7600U), same seed for every contender, identical results.</text>', x0, sans, th[["muted"]]),
    sprintf('<text x="%d" y="138" font-family="%s" font-size="15" fill="%s">Green: against the code researchers use today. Blue: against the same algorithm in GNU R.</text>', x0, sans, th[["muted"]]))
  foot <- c(
    sprintf('<rect x="%d" y="%d" width="%d" height="64" rx="8" fill="%s"/>', x0, y, W - 2 * x0, th[["band"]]),
    sprintf('<rect x="%d" y="%d" width="5" height="64" rx="2" fill="%s"/>', x0, y, th[["gold"]]),
    sprintf('<text x="%d" y="%d" font-family="%s" font-size="15" font-weight="700" fill="%s">Bit-identical to GNU R and seminr (HTMT: within 4 ulp), checked on Linux, macOS and Windows</text>', x0 + 20, y + 26, sans, th[["ink"]]),
    sprintf('<text x="%d" y="%d" font-family="%s" font-size="14" fill="%s">201-function corpus · .lm.fit() on 55 designs · glm.fit() on 165 fits · seminr on 79 PLS-SEM models · bench/phase2/REPORT.md</text>', x0 + 20, y + 48, sans, th[["muted"]]),
    "</svg>")
  c(head, body, foot)
}
for (nm in names(themes)) writeLines(card(themes[[nm]]), file.path("docs", "assets", sprintf("results-%s.svg", nm)), useBytes = TRUE)
cat("wrote docs/assets/results-light.svg and results-dark.svg\n")
