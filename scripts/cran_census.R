# CRAN census for R-Goose compatibility planning.
# Reproduce with: Rscript scripts/cran_census.R
# Writes research/cran_census_<date>.csv and prints the summary used in docs/COMPATIBILITY.md.

db <- tools::CRAN_package_db()
db <- db[!duplicated(db$Package), ]
today <- format(Sys.Date())

has <- function(field, pattern) grepl(pattern, ifelse(is.na(field), "", field))

summary_tbl <- data.frame(
  metric = c(
    "packages",
    "needs_compilation_yes",
    "needs_compilation_no",
    "linking_to_rcpp",
    "linking_to_rcpparmadillo",
    "linking_to_cpp11",
    "licence_mentions_gpl",
    "licence_mentions_mit"
  ),
  value = c(
    nrow(db),
    sum(db$NeedsCompilation %in% "yes"),
    sum(db$NeedsCompilation %in% "no"),
    sum(has(db$LinkingTo, "\\bRcpp\\b")),
    sum(has(db$LinkingTo, "\\bRcppArmadillo\\b")),
    sum(has(db$LinkingTo, "\\bcpp11\\b")),
    sum(has(db$License, "GPL")),
    sum(has(db$License, "MIT"))
  )
)
summary_tbl$share <- round(100 * summary_tbl$value / nrow(db), 1)

# Reverse dependencies (Depends, Imports, LinkingTo): how many CRAN packages need each package.
deps <- tools::package_dependencies(db$Package, db = db,
                                    which = c("Depends", "Imports", "LinkingTo"),
                                    recursive = FALSE)
rev_counts <- sort(table(unlist(deps, use.names = FALSE)), decreasing = TRUE)
base_pkgs <- rownames(installed.packages(priority = "base"))
top <- rev_counts[!names(rev_counts) %in% c(base_pkgs, "R")]
top_tbl <- data.frame(package = names(top)[1:30], reverse_dependencies = as.integer(top[1:30]))

dir.create("research", showWarnings = FALSE)
write.csv(summary_tbl, file.path("research", paste0("cran_census_", today, ".csv")), row.names = FALSE)
write.csv(top_tbl, file.path("research", paste0("cran_top_reverse_deps_", today, ".csv")), row.names = FALSE)

cat("CRAN census,", today, "\n")
print(summary_tbl, row.names = FALSE)
cat("\nTop 30 non-base packages by direct reverse dependencies\n")
print(top_tbl, row.names = FALSE)
