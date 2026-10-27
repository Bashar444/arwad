# aw_compile() and the dispatcher behind every compiled function.
#
# A compiled function keeps the original's arguments. On each call it reads
# the arguments' types, finds or builds the native unit for that signature,
# and calls it. Three things send a call to GNU R instead: the function is
# outside the subset (decided once, at aw_compile()), the signature cannot be
# compiled (decided once per signature), or the native code met a case it
# does not model and bailed out (decided per call; the call is re-run in R,
# which is sound because compiled functions have no side effects).

#' Compile an R function to native code
#'
#' Checks that `f` uses only the compilable subset (see `spec/subset-v0.md` in
#' the Arwad repository) and returns a function with the same arguments. The
#' first call with a new combination of argument types compiles a native unit
#' through Goose and the C compiler R uses for packages; later calls with the
#' same types reuse it, also across sessions through an on-disk cache.
#'
#' Results match GNU R. Whenever the native code meets a case it does not
#' model (an `NA` condition, integer overflow, `sqrt()` of a negative number,
#' a zero index), the call is re-run in GNU R, so errors, warnings and results
#' are exactly R's. Functions outside the subset are returned unchanged, with
#' the reason in `attr(result, "arwad_fallback")`; primitives such as `sum`
#' are returned as they are, being native code already. A function or an
#' argument signature that runs in GNU R instead of native code says so once,
#' in a message with the reason; `options(arwad.quiet = TRUE)` turns these
#' messages off.
#'
#' Arguments are evaluated when the compiled function is called (R evaluates
#' them lazily), and long-running compiled loops cannot be interrupted.
#'
#' @param f A function.
#' @param name A label for messages and [aw_explain()]; by default the
#'   expression passed as `f`.
#' @return A function of class `arwad_function`, or `f` itself with an
#'   `arwad_fallback` attribute.
#' @seealso [aw_explain()], [aw_toolchain()]
#' @export
#' @examples
#' sum_sq <- function(x) {
#'   s <- 0
#'   for (i in seq_along(x)) s <- s + x[i]^2
#'   s
#' }
#' g <- aw_compile(sum_sq)
#' \donttest{
#' old <- options(arwad.cache_dir = tempfile("arwad"))
#' g(c(1, 2, 3))
#' aw_explain(g)
#' options(old)
#' }
#' # Outside the subset: returned unchanged, with the reason.
#' h <- aw_compile(function(x) paste(x))
#' attr(h, "arwad_fallback")
aw_compile <- function(f, name = NULL) {
  if (is.null(name)) name <- paste(deparse(substitute(f), width.cutoff = 60L)[1L])
  if (inherits(f, "arwad_function") || is.primitive(f)) return(f)
  info <- tryCatch(aw_check(f), arwad_unsupported = function(e) e)
  if (inherits(info, "condition")) {
    attr(f, "arwad_fallback") <- conditionMessage(info)
    aw_note_fallback(name, NULL, conditionMessage(info))
    return(f)
  }
  st <- new.env(parent = emptyenv())
  st$f <- f
  st$name <- name
  st$info <- info
  st$specs <- new.env(parent = emptyenv())
  g <- function() NULL
  formals(g) <- formals(f)
  body(g) <- as.call(c(list(aw_dispatch, st), lapply(info$formals, as.name)))
  environment(g) <- environment(f)
  structure(g, class = c("arwad_function", "function"), arwad_state = st)
}

aw_tcode <- c(double = "dbl", integer = "int", logical = "lgl")

# Native units are built at run time, so their routines cannot be registered
# with the package; calling through an alias keeps R CMD check from trying to
# resolve a symbol that exists only after a build.
aw_dotcall <- .Call

# The signature key of one call: a type and a kind ("s" scalar, "v" vector)
# per argument. A key starting with "!" names an argument that cannot be
# compiled.
aw_signature <- function(st, args) {
  if (length(args) == 0L) return("()")
  parts <- character(length(args))
  fm <- st$info$formals
  for (i in seq_along(args)) {
    a <- args[[i]]
    t <- aw_tcode[typeof(a)]
    if (is.na(t)) return(sprintf("!argument '%s' is of type %s", fm[i], typeof(a)))
    n <- length(a)
    if (n > .Machine$integer.max) return(sprintf("!argument '%s' is a long vector", fm[i]))
    at <- attributes(a)
    if (!is.null(at)) {
      if (identical(names(at), "dim") && length(at$dim) == 2L) {
        parts[i] <- paste0(t, "[,]")
        next
      }
      return(sprintf("!argument '%s' has attributes (%s)", fm[i], paste(names(at), collapse = ", ")))
    }
    parts[i] <- paste0(t, if (n != 1L || fm[i] %in% st$info$vec) "[]" else "")
  }
  paste(parts, collapse = ",")
}

aw_parse_key <- function(key) {
  lapply(strsplit(gsub("[,]", "[m]", key, fixed = TRUE), ",", fixed = TRUE)[[1L]], function(p) {
    kind <- if (endsWith(p, "[m]")) "m" else if (endsWith(p, "[]")) "v" else "s"
    list(type = sub("\\[.*$", "", p), kind = kind)
  })
}

# Says, once, that a function or one of its signatures runs in GNU R instead
# of native code, and why: a silent fallback once hid that an engine was not
# compiled at all. options(arwad.quiet = TRUE) turns these messages off.
aw_note_fallback <- function(name, signature, reason) {
  if (isTRUE(getOption("arwad.quiet"))) return(invisible())
  what <- if (is.null(signature)) sprintf("'%s'", name) else sprintf("'%s' for (%s)", name, signature)
  message(sprintf("arwad: %s runs in GNU R, not as native code: %s", what, reason))
}

aw_specialise <- function(st, key) {
  sp <- new.env(parent = emptyenv())
  sp$key <- key
  sp$ok <- FALSE
  sp$calls <- 0L
  sp$bailouts <- integer()
  assign(key, sp, envir = st$specs)
  if (startsWith(key, "!")) {
    sp$reason <- substring(key, 2L)
    aw_note_fallback(st$name, NULL, sp$reason)
    return(sp)
  }
  types <- if (key == "()") list() else aw_parse_key(key)
  code <- tryCatch(aw_codegen(st$info, st$f, types, st$name), arwad_unsupported = function(e) e)
  if (inherits(code, "condition")) {
    sp$reason <- conditionMessage(code)
    aw_note_fallback(st$name, key, sp$reason)
    return(sp)
  }
  sp$signature <- code$signature
  sp$bails <- code$bails
  tc <- aw_toolchain()
  if (!tc$ok) {
    sp$reason <- tc$reason
    if (!isTRUE(aw_state$toolchain_noted)) {
      aw_state$toolchain_noted <- TRUE
      aw_note_fallback(st$name, NULL, paste(tc$reason, "(said once per session; every compiled function runs in GNU R)"))
    }
    return(sp)
  }
  if (isTRUE(getOption("arwad.verbose"))) message("arwad: compiling ", st$name, " for (", code$signature, ")")
  b <- aw_build(code, tc)
  sp$goose <- b$goose
  if (!b$ok) {
    sp$reason <- b$reason
    aw_note_fallback(st$name, code$signature, sp$reason)
    return(sp)
  }
  sp$sym <- aw_load(b$lib, b$hash)
  sp$hash <- b$hash
  sp$cached <- b$cached
  sp$seconds <- b$seconds
  sp$method <- b$method
  sp$ok <- TRUE
  sp
}

aw_dispatch <- function(st, ...) {
  # A function that draws random numbers: keep the seed, so that a call the
  # native code hands back to GNU R starts from the same stream.
  seed <- if (st$info$rng) get0(".Random.seed", envir = globalenv(), inherits = FALSE)
  # Fast path: the native unit of the last native call checks the argument
  # types itself and returns -1 when they do not fit.
  sp <- st$last
  if (!is.null(sp)) {
    res <- aw_dotcall(sp$sym, list(...))
    s <- res[[1L]]
    if (s >= 0L) {
      sp$calls <- sp$calls + 1L
      if (s == 0L) return(res[[2L]])
      if (s == 1L) return(invisible(res[[2L]]))
      return(aw_bailout(st, sp, s, list(...), seed))
    }
  }
  args <- list(...)
  key <- aw_signature(st, args)
  sp <- get0(key, envir = st$specs, inherits = FALSE)
  if (is.null(sp)) sp <- aw_specialise(st, key)
  sp$calls <- sp$calls + 1L
  if (!sp$ok) {
    names(args) <- st$info$formals
    return(do.call(st$f, args))
  }
  # Matrix arguments are checked here, in R (only a dim attribute), not in C.
  if (!grepl("[,]", key, fixed = TRUE)) st$last <- sp
  res <- aw_dotcall(sp$sym, args)
  s <- res[[1L]]
  if (s == 0L) return(res[[2L]])
  if (s == 1L) return(invisible(res[[2L]]))
  aw_bailout(st, sp, s, args, seed)
}

# The native code met a case it does not model: count it, restore the random
# seed if the function draws random numbers, and run the call in GNU R.
aw_bailout <- function(st, sp, s, args, seed = NULL) {
  why <- sp$bails[s - 1L]
  sp$bailouts[why] <- if (is.na(sp$bailouts[why])) 1L else sp$bailouts[why] + 1L
  if (st$info$rng) {
    if (is.null(seed)) {
      if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) rm(".Random.seed", envir = globalenv())
    } else {
      assign(".Random.seed", seed, envir = globalenv())
    }
  }
  names(args) <- st$info$formals
  do.call(st$f, args)
}

#' Explain how a compiled function runs
#'
#' Lists each argument signature a compiled function has met: whether it
#' runs natively or in GNU R and why, how often it was called, and how often
#' the native code handed a call back to GNU R (a bailout), by reason.
#'
#' @param g A function returned by [aw_compile()].
#' @return A data frame with one row per signature, invisibly.
#' @export
aw_explain <- function(g) {
  if (!inherits(g, "arwad_function")) {
    why <- attr(g, "arwad_fallback")
    cat("Not compiled: ", if (is.null(why)) "not created by aw_compile()" else why, "\n", sep = "")
    return(invisible(NULL))
  }
  st <- attr(g, "arwad_state")
  specs <- mget(ls(st$specs, sorted = TRUE), envir = st$specs)
  cat("arwad function ", st$name, ": in the compilable subset\n", sep = "")
  if (length(specs) == 0L) cat("  not called yet\n")
  rows <- lapply(specs, function(sp) {
    nb <- sum(sp$bailouts)
    if (sp$ok) {
      how <- sprintf("native (%s)", if (isTRUE(sp$cached)) "from cache" else sprintf("built in %.1f s, %s", sp$seconds, sp$method))
    } else {
      how <- paste("GNU R:", sp$reason)
    }
    cat(sprintf("  (%s): %s\n    %d call(s), %d bailout(s)\n", if (is.null(sp$signature)) sp$key else sp$signature,
                how, sp$calls, nb))
    for (r in names(sp$bailouts)) cat(sprintf("      %d x %s\n", sp$bailouts[[r]], r))
    data.frame(signature = sp$key, native = sp$ok, reason = if (sp$ok) NA_character_ else sp$reason,
               calls = sp$calls, bailouts = nb, stringsAsFactors = FALSE)
  })
  invisible(do.call(rbind, c(list(data.frame(signature = character(), native = logical(), reason = character(),
                                             calls = integer(), bailouts = integer())), rows)))
}

#' Show the Goose code generated for a compiled function
#'
#' @param g A function returned by [aw_compile()].
#' @param signature Which signature, as listed by [aw_explain()]; by default
#'   the first one compiled.
#' @return The Goose source as a single string, invisibly; it is also printed.
#' @export
aw_source <- function(g, signature = NULL) {
  st <- attr(g, "arwad_state")
  if (is.null(st)) stop("not a function returned by aw_compile()")
  keys <- ls(st$specs, sorted = TRUE)
  keys <- keys[vapply(keys, function(k) !is.null(get(k, envir = st$specs)$goose), logical(1))]
  if (!is.null(signature)) keys <- intersect(keys, signature)
  if (length(keys) == 0L) stop("no generated code yet: call the function first")
  src <- get(keys[1L], envir = st$specs)$goose
  cat(src, "\n", sep = "")
  invisible(src)
}

#' @export
print.arwad_function <- function(x, ...) {
  st <- attr(x, "arwad_state")
  cat("<arwad function ", st$name, ">\n", sep = "")
  print(st$f, ...)
  invisible(x)
}
