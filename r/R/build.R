# Native build: Goose writes standalone C for one compiled unit, and R's own
# package toolchain (R CMD SHLIB) links it with the unit's shim into a shared
# library. Libraries are cached by a hash of everything that determines them:
# the generated sources, the runtime header, the Goose and R versions and the
# compiler flags. Each unit is its own library with its own copy of the Goose
# runtime, as Goose compiles whole programs.

aw_state <- new.env(parent = emptyenv())

# -ffp-contract=off: no fused multiply-add, so each operation rounds as R's do.
aw_makevars <- c("PKG_CFLAGS = -ffp-contract=off", "PKG_LIBS = -lm")

#' Find the Goose toolchain
#'
#' Looks for the `goose` executable in `getOption("arwad.goose")`, then the
#' `ARWAD_GOOSE` environment variable, then the `PATH`. The C compiler is the
#' one R uses to build packages (Rtools on Windows).
#'
#' @param refresh Look again instead of using the result cached for the session.
#' @return A list with `ok`, `goose` (the path), `version`, and `reason` when
#'   `ok` is `FALSE`.
#' @export
#' @examples
#' aw_toolchain()$ok
aw_toolchain <- function(refresh = FALSE) {
  if (!refresh && !is.null(aw_state$toolchain)) return(aw_state$toolchain)
  goose <- getOption("arwad.goose", Sys.getenv("ARWAD_GOOSE", ""))
  if (!nzchar(goose)) goose <- unname(Sys.which("goose"))
  tc <- list(ok = FALSE, goose = goose, version = NA_character_, reason = NULL)
  if (!nzchar(goose) || !file.exists(goose)) {
    tc$reason <- "Goose not found: set options(arwad.goose = <path to goose>) or the ARWAD_GOOSE environment variable"
  } else {
    v <- tryCatch(suppressWarnings(system2(goose, "version", stdout = TRUE, stderr = TRUE)),
                  error = function(e) character())
    if (length(v) == 0L || !is.null(attr(v, "status"))) {
      tc$reason <- paste("Goose did not run:", goose)
    } else {
      tc$ok <- TRUE
      tc$version <- v[1L]
    }
  }
  aw_state$toolchain <- tc
  tc
}

aw_cache_dir <- function() {
  getOption("arwad.cache_dir", tools::R_user_dir("arwad", "cache"))
}

#' Remove cached native libraries
#'
#' Deletes the libraries arwad has built (by default in
#' `tools::R_user_dir("arwad", "cache")`, or `getOption("arwad.cache_dir")`).
#' Libraries already loaded in this session stay loaded.
#'
#' @return The number of cached units removed, invisibly.
#' @export
aw_cache_clear <- function() {
  root <- aw_cache_dir()
  units <- list.dirs(root, recursive = FALSE)
  unlink(units, recursive = TRUE)
  invisible(length(units))
}

aw_hash <- function(text) {
  f <- tempfile()
  on.exit(unlink(f))
  writeLines(text, f, useBytes = TRUE)
  substr(unname(tools::md5sum(f)), 1L, 16L)
}

aw_run <- function(cmd, args, dir) {
  owd <- setwd(dir)
  on.exit(setwd(owd))
  out <- suppressWarnings(system2(cmd, args, stdout = TRUE, stderr = TRUE))
  status <- attr(out, "status")
  list(ok = is.null(status) || identical(as.integer(status), 0L), out = out)
}

aw_tail_lines <- function(out, n = 8L) {
  out <- out[nzchar(trimws(out))]
  keep <- grep("error", out, ignore.case = TRUE, value = TRUE)
  if (length(keep) == 0L) keep <- utils::tail(out, n)
  paste(utils::head(keep, n), collapse = "\n")
}

# Builds (or finds in the cache) the library for one generated unit.
aw_build <- function(code, tc) {
  rt <- system.file("runtime", "aw_rt.h", package = "arwad", mustWork = TRUE)
  key <- c(code$goose, code$shim, readLines(rt), tc$version, R.version.string,
           R.version$platform, aw_makevars, as.character(utils::packageVersion("arwad")))
  h <- aw_hash(key)
  goose <- gsub("@H@", h, code$goose, fixed = TRUE)
  shim <- gsub("@H@", h, code$shim, fixed = TRUE)
  root <- aw_cache_dir()
  dir <- file.path(root, h)
  lib <- paste0("aw_", h, .Platform$dynlib.ext)
  if (file.exists(file.path(dir, lib))) {
    return(list(ok = TRUE, lib = file.path(dir, lib), hash = h, cached = TRUE, seconds = 0, goose = goose))
  }
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  tmp <- file.path(root, paste0(h, ".tmp", Sys.getpid()))
  unlink(tmp, recursive = TRUE)
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  writeLines(goose, file.path(tmp, "unit.goose"), useBytes = TRUE)
  writeLines(shim, file.path(tmp, "shim.c"), useBytes = TRUE)
  writeLines(aw_makevars, file.path(tmp, "Makevars"))
  file.copy(rt, tmp)
  t0 <- proc.time()[["elapsed"]]
  g <- aw_run(tc$goose, c("-O2", "--standalone", "--header", "unit.h", "--include", "aw_rt.h",
                          "-o", "unit.c", "unit.goose"), tmp)
  if (!g$ok) return(list(ok = FALSE, reason = paste0("Goose could not compile the generated unit:\n", aw_tail_lines(g$out))))
  r <- aw_run(file.path(R.home("bin"), "R"), c("CMD", "SHLIB", "-o", lib, "shim.c", "unit.c"), tmp)
  if (!r$ok || !file.exists(file.path(tmp, lib))) {
    return(list(ok = FALSE, reason = paste0("the C build failed (R CMD SHLIB):\n", aw_tail_lines(r$out))))
  }
  unlink(list.files(tmp, pattern = "\\.(o|obj)$", full.names = TRUE))
  secs <- proc.time()[["elapsed"]] - t0
  if (!file.rename(tmp, dir) && !file.exists(file.path(dir, lib))) {
    return(list(ok = FALSE, reason = paste("could not move the built unit into the cache:", dir)))
  }
  list(ok = TRUE, lib = file.path(dir, lib), hash = h, cached = FALSE, seconds = secs, goose = goose)
}

aw_load <- function(lib, h) {
  name <- paste0("aw_", h)
  dll <- getLoadedDLLs()[[name]]
  if (is.null(dll)) dll <- dyn.load(lib, local = TRUE, now = TRUE)
  getNativeSymbolInfo(paste0("aw_call_", h), PACKAGE = dll)
}
