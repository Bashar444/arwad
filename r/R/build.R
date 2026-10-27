# Native build: Goose writes standalone C for one compiled unit, and R's own
# package toolchain (R CMD SHLIB) links it with the unit's shim into a shared
# library. Libraries are cached by a hash of everything that determines them:
# the generated sources, the runtime header, the Goose and R versions and the
# compiler flags. Each unit is its own library with its own copy of the Goose
# runtime, as Goose compiles whole programs.

aw_state <- new.env(parent = emptyenv())

# -ffp-contract=off: no fused multiply-add, so each operation rounds as R's do.
# -fno-math-errno: sqrt() is always the processor's correctly rounded square
# root; with errno, GCC may call the C library's instead, and on Windows that
# one rounds some results to the neighbouring double.
# R's own LAPACK and BLAS, as packages link them, for %*%, crossprod() and solve().
aw_makevars <- c("PKG_CFLAGS = -ffp-contract=off -fno-math-errno", "PKG_LIBS = $(LAPACK_LIBS) $(BLAS_LIBS) -lm")

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

# Extra compile and link flags for every unit and the Goose runtime, such as
# "-fsanitize=address -fno-omit-frame-pointer" for the AddressSanitizer run.
aw_extra_cflags <- function() Sys.getenv("ARWAD_EXTRA_CFLAGS", getOption("arwad.cflags", ""))

aw_run <- function(cmd, args, dir) {
  owd <- setwd(dir)
  on.exit(setwd(owd))
  # A sanitizer runtime preloaded into R is not for the compilers R starts.
  env <- if (.Platform$OS.type == "unix" && nzchar(Sys.getenv("LD_PRELOAD"))) "LD_PRELOAD=" else character()
  out <- tryCatch(suppressWarnings(system2(cmd, args, stdout = TRUE, stderr = TRUE, env = env)),
                  error = function(e) structure(conditionMessage(e), status = 127L))
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
           R.version$platform, aw_makevars, aw_extra_cflags(), as.character(utils::packageVersion("arwad")))
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
  method <- "direct"
  built <- aw_build_direct(tmp, lib, tc)
  if (!isTRUE(built$ok)) {
    if (!is.null(built$reason)) return(built)
    method <- "R CMD SHLIB"
    built <- aw_build_shlib(tmp, lib, tc)
    if (!built$ok) return(built)
  }
  unlink(list.files(tmp, pattern = "\\.(o|obj)$", full.names = TRUE))
  secs <- proc.time()[["elapsed"]] - t0
  if (!file.rename(tmp, dir) && !file.exists(file.path(dir, lib))) {
    return(list(ok = FALSE, reason = paste("could not move the built unit into the cache:", dir)))
  }
  list(ok = TRUE, lib = file.path(dir, lib), hash = h, cached = FALSE, seconds = secs, goose = goose,
       method = method)
}

aw_goose_fail <- function(g) {
  list(ok = FALSE, reason = paste0("Goose could not compile the generated unit:\n", aw_tail_lines(g$out)))
}

# The portable path: a standalone unit (runtime included) through R CMD SHLIB.
aw_build_shlib <- function(tmp, lib, tc) {
  g <- aw_run(tc$goose, c("-O2", "--standalone", "--header", "unit.h", "--include", "aw_rt.h",
                          "-o", "unit.c", "unit.goose"), tmp)
  if (!g$ok) return(aw_goose_fail(g))
  r <- aw_run(file.path(R.home("bin"), "R"), c("CMD", "SHLIB", "-o", lib, "shim.c", "unit.c"), tmp)
  if (!r$ok || !file.exists(file.path(tmp, lib))) {
    return(list(ok = FALSE, reason = paste0("the C build failed (R CMD SHLIB):\n", aw_tail_lines(r$out))))
  }
  list(ok = TRUE)
}

# The fast path: R's own compile and link commands, called directly, with the
# Goose runtime compiled once per toolchain. Returns list(ok = FALSE) without
# a reason when the portable path should be tried instead.
aw_build_direct <- function(tmp, lib, tc) {
  if (identical(getOption("arwad.build"), "shlib")) return(list(ok = FALSE))
  cc <- aw_cc()
  if (!is.list(cc)) return(list(ok = FALSE))
  rto <- aw_runtime_obj(tc, cc)
  if (is.null(rto)) return(list(ok = FALSE))
  g <- aw_run(tc$goose, c("-O2", "--header", "unit.h", "--include", "aw_rt.h", "-o", "unit.c", "unit.goose"), tmp)
  if (!g$ok) return(aw_goose_fail(g))
  if (!aw_cmd(paste(cc$compile, "-c shim.c unit.c"), tmp)$ok) return(list(ok = FALSE))
  link <- gsub("@OUT@", lib, cc$link, fixed = TRUE)
  link <- gsub("@OBJ@", paste0('shim.o unit.o "', rto, '"'), link, fixed = TRUE)
  list(ok = aw_cmd(link, tmp)$ok && file.exists(file.path(tmp, lib)))
}

# R's compile and link commands for a shared library, read once from a dry run
# of R CMD SHLIB (which prints them without running them) and cached on disk.
aw_cc <- function() {
  if (!is.null(aw_state$cc)) return(aw_state$cc)
  root <- aw_cache_dir()
  rds <- file.path(root, paste0("cc-", aw_hash(c(R.version.string, R.home(), R.version$platform, aw_makevars)), ".rds"))
  cc <- if (file.exists(rds)) tryCatch(readRDS(rds), error = function(e) NULL)
  if (is.null(cc)) {
    cc <- aw_cc_probe()
    if (is.list(cc)) {
      dir.create(root, recursive = TRUE, showWarnings = FALSE)
      saveRDS(cc, rds)
    }
  }
  extra <- aw_extra_cflags()
  if (is.list(cc) && nzchar(extra)) {
    cc$compile <- paste(cc$compile, extra)
    cc$link <- paste(cc$link, extra)
  }
  aw_state$cc <- cc
  cc
}

aw_cc_probe <- function() {
  dir <- tempfile("arwad-probe")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE))
  writeLines("int aw_probe(void) { return 0; }", file.path(dir, "probe.c"))
  writeLines(aw_makevars, file.path(dir, "Makevars"))
  lib <- paste0("probe", .Platform$dynlib.ext)
  out <- aw_run(file.path(R.home("bin"), "R"), c("CMD", "SHLIB", "-n", "-o", lib, "probe.c"), dir)$out
  comp <- grep("-c probe.c -o probe.o", out, fixed = TRUE, value = TRUE)
  if (length(comp) == 0L) return(FALSE)
  comp <- trimws(sub("-c probe.c -o probe.o", "", comp[1L], fixed = TRUE))
  if (.Platform$OS.type == "windows") {
    # R's Windows rule builds an export list around the link; this is its core.
    link <- sprintf('%s -shared -o @OUT@ @OBJ@ -L"%s" -lRlapack -lRblas -lR', sub(" .*", "", comp), R.home("bin"))
  } else {
    # R's rule wraps the link in `if test ...; then echo <link>; <link>; fi`.
    link <- trimws(grep(paste("-o", lib), out, fixed = TRUE, value = TRUE))
    link <- sub("[;\\[:space:]]+$", "", sub("^echo[[:space:]]+", "", link))
    if (length(link) == 0L) return(FALSE)
    link <- sub(paste("-o", lib), "-o @OUT@", link[1L], fixed = TRUE)
    link <- sub("probe.o", "@OBJ@", link, fixed = TRUE)
  }
  # Trust the commands only once they have built the probe.
  ok <- aw_cmd(paste(comp, "-c probe.c"), dir)$ok &&
    aw_cmd(gsub("@OBJ@", "probe.o", gsub("@OUT@", lib, link, fixed = TRUE), fixed = TRUE), dir)$ok &&
    file.exists(file.path(dir, lib))
  if (!ok) return(FALSE)
  list(compile = comp, link = link)
}

# The Goose runtime as one object file, shared by every unit built with the
# same Goose version and compile command.
aw_runtime_obj <- function(tc, cc) {
  dir <- file.path(aw_cache_dir(), paste0("rt-", aw_hash(c(tc$version, cc$compile))))
  obj <- file.path(dir, "runtime.o")
  if (file.exists(obj)) return(obj)
  tmp <- paste0(dir, ".tmp", Sys.getpid())
  unlink(tmp, recursive = TRUE)
  dir.create(tmp, recursive = TRUE)
  on.exit(unlink(tmp, recursive = TRUE))
  if (!aw_run(tc$goose, c("--emit-runtime", "runtime.c"), tmp)$ok) return(NULL)
  if (!aw_cmd(paste(cc$compile, "-c runtime.c"), tmp)$ok || !file.exists(file.path(tmp, "runtime.o"))) return(NULL)
  if (!file.rename(tmp, dir) && !file.exists(obj)) return(NULL)
  obj
}

# Runs one command line from R's make rules; on Windows with Rtools first on
# the PATH, as R CMD SHLIB has it.
aw_cmd <- function(cmdline, dir) {
  first <- sub(" .*", "", cmdline)
  rest <- substring(cmdline, nchar(first) + 2L)
  if (.Platform$OS.type == "windows") {
    env <- Sys.getenv()
    rt <- env[grep("^R_RTOOLS[0-9]+_PATH$", names(env))]
    if (length(rt) && nzchar(rt[[1L]])) {
      old <- Sys.getenv("PATH")
      Sys.setenv(PATH = paste(rt[[1L]], old, sep = ";"))
      on.exit(Sys.setenv(PATH = old))
    }
  }
  aw_run(first, rest, dir)
}

aw_load <- function(lib, h) {
  name <- paste0("aw_", h)
  dll <- getLoadedDLLs()[[name]]
  if (is.null(dll)) dll <- dyn.load(lib, local = TRUE, now = TRUE)
  getNativeSymbolInfo(paste0("aw_call_", h), PACKAGE = dll)
}
