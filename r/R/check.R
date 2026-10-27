# Static check: does a function use only the compilable subset?
#
# The front end walks the language object R's own parser produced (body(f)),
# so Arwad accepts exactly what R parses. The walk also records what code
# generation needs: the formals used as vectors, the formals that are
# reassigned, and the local variables. Every rejection carries a reason that
# aw_compile() stores on the returned function.

aw_unsupported <- function(msg, expr = NULL) {
  if (!is.null(expr)) msg <- paste0(msg, ": ", aw_deparse(expr))
  cond <- structure(class = c("arwad_unsupported", "error", "condition"),
                    list(message = msg, call = NULL))
  stop(cond)
}

aw_deparse <- function(e) {
  s <- paste(trimws(deparse(e, width.cutoff = 60L)), collapse = " ")
  if (nchar(s) > 70L) paste0(substr(s, 1L, 67L), "...") else s
}

# Names a compiled body may call, with their accepted argument counts.
aw_arity <- list(
  "{" = c(0L, Inf), "(" = 1L, "<-" = 2L, "=" = 2L, "if" = 2:3, "for" = 3L,
  "while" = 2L, "repeat" = 1L, "break" = 0L, "next" = 0L, "return" = 0:1,
  "+" = 1:2, "-" = 1:2, "*" = 2L, "/" = 2L, "^" = 2L, "%%" = 2L, "%/%" = 2L,
  "==" = 2L, "!=" = 2L, "<" = 2L, "<=" = 2L, ">" = 2L, ">=" = 2L,
  "!" = 1L, "&" = 2L, "|" = 2L, "&&" = 2L, "||" = 2L,
  "[" = 2:3, "[[" = 2:3, ":" = 2L, "seq_len" = 1L, "seq_along" = 1L,
  "matrix" = 1:3, "nrow" = 1L, "ncol" = 1L, "dim" = 1L, "t" = 1L,
  "%*%" = 2L, "crossprod" = 1:2, "solve" = 1:2,
  "floor" = 1L, "ceiling" = 1L, "runif" = 1:3, "rnorm" = 1:3,
  "sample" = 1:3, "sample.int" = 1:3, "$" = 2L, ".lm.fit" = 2:3, "drop" = 1L,
  "length" = 1L, "numeric" = 0:1, "integer" = 0:1, "logical" = 0:1,
  "sqrt" = 1L, "exp" = 1L, "log" = 1L, "abs" = 1L, "sum" = 1L, "is.na" = 1L,
  "c" = c(1L, Inf), "mean" = 1L, "min" = c(1L, Inf), "max" = c(1L, Inf)
)

# Argument names R users write for these, accepted when given by name.
aw_argnames <- list(numeric = "length", integer = "length", logical = "length",
                    seq_len = "length.out", seq_along = "along.with",
                    matrix = c("data", "nrow", "ncol"), crossprod = c("x", "y"),
                    solve = c("a", "b"), runif = c("n", "min", "max"), rnorm = c("n", "mean", "sd"),
                    sample = c("x", "size", "replace"), sample.int = c("n", "size", "replace"),
                    .lm.fit = c("x", "y", "tol"))

# Compiled functions that do not live in base, by their package.
aw_home <- c(runif = "stats", rnorm = "stats", .lm.fit = "stats")

# The parts of a .lm.fit() result that compile, taken directly
# (.lm.fit(x, y)$coefficients) or from a variable (fit <- .lm.fit(x, y);
# fit$rank). Other lists and `$` are outside the subset.
aw_lmfit_fields <- c("coefficients", "residuals", "rank", "pivot")

# Arguments of a call in the order of `formals`, matching exact names first
# and then positions, as R does (partial names are not accepted).
aw_match_args <- function(args, formals) {
  out <- vector("list", length(formals))
  names(out) <- formals
  an <- names(args)
  if (is.null(an)) an <- rep("", length(args))
  for (k in which(nzchar(an))) out[an[k]] <- list(args[[k]])
  free <- setdiff(formals, an[nzchar(an)])
  pos <- which(!nzchar(an))
  for (j in seq_along(pos)) out[free[j]] <- list(args[[pos[j]]])
  out
}

# Friendlier reasons for common calls outside the subset.
aw_planned <- c(
  "<<-" = "superassignment `<<-` changes the enclosing environment",
  "function" = "functions defined inside the function (closures)",
  "tcrossprod" = "tcrossprod() is planned for a later slice", "diag" = "diag() is planned for a later slice",
  "seq" = "seq() is planned for slice 2",
  "set.seed" ="set.seed() inside a compiled function changes global state; call it before",
  "print" = "output is a side effect outside the subset", "cat" = "output is a side effect outside the subset",
  "message" = "output is a side effect outside the subset",
  "stop" = "signalling conditions is planned for slice 2", "warning" = "signalling conditions is planned for slice 2",
  "tryCatch" = "condition handling is outside the subset", "on.exit" = "on.exit() is outside the subset",
  "sapply" = "apply-family functions are outside the subset", "vapply" = "apply-family functions are outside the subset",
  "lapply" = "apply-family functions are outside the subset", "eval" = "computing on the language is outside the subset",
  "quote" = "computing on the language is outside the subset", "list" = "lists are outside subset v0"
)

aw_check <- function(f) {
  if (!is.function(f)) aw_unsupported("not a function")
  if (is.primitive(f)) aw_unsupported("primitive functions are already native code")
  fm <- formals(f)
  nms <- names(fm)
  if ("..." %in% nms) aw_unsupported("`...` in the arguments")
  for (nm in nms) {
    if (!identical(fm[[nm]], quote(expr = )) && !aw_is_const(fm[[nm]]))
      aw_unsupported(sprintf("default of argument '%s' is not a constant", nm), fm[[nm]])
  }
  b <- body(f)
  s <- new.env(parent = emptyenv())
  s$env <- environment(f)
  s$formals <- nms
  s$targets <- aw_targets(b)
  s$vec <- character()
  s$reassigned <- character()
  s$subassigned <- character()
  s$calls <- character()
  s$consts <- character()
  s$loop <- 0L
  aw_walk(b, nms, s)
  for (nm in unique(s$calls)) {
    home <- if (nm %in% names(aw_home)) asNamespace(aw_home[[nm]]) else baseenv()
    if (!identical(get0(nm, envir = s$env, mode = "function"), get(nm, envir = home, mode = "function")))
      aw_unsupported(sprintf("`%s` is redefined where the function was created", nm))
  }
  for (nm in unique(s$consts)) {
    if (!identical(get0(nm, envir = s$env), get(nm, envir = baseenv())))
      aw_unsupported(sprintf("`%s` is redefined where the function was created", nm))
  }
  list(formals = nms, vec = unique(s$vec), reassigned = unique(s$reassigned),
       subassigned = unique(s$subassigned),
       rng = any(c("runif", "rnorm", "sample", "sample.int") %in% s$calls))
}

aw_is_const <- function(e) {
  if (is.call(e) && identical(e[[1L]], as.name("-")) && length(e) == 2L) e <- e[[2L]]
  is.atomic(e) && length(e) == 1L && typeof(e) %in% c("double", "integer", "logical")
}

# Every name the body assigns, anywhere (assignment targets and loop variables).
aw_targets <- function(e) {
  if (!is.call(e)) return(character())
  out <- character()
  fn <- e[[1L]]
  if (is.symbol(fn)) {
    nm <- as.character(fn)
    if (nm %in% c("<-", "=") && length(e) == 3L) {
      t <- e[[2L]]
      if (is.symbol(t)) out <- as.character(t)
    } else if (nm == "for" && length(e) == 4L && is.symbol(e[[2L]])) {
      out <- as.character(e[[2L]])
    }
  }
  for (a in as.list(e)[-1L]) if (!missing(a)) out <- c(out, aw_targets(a))
  unique(out)
}

aw_has_break <- function(e) {
  if (!is.call(e) || !is.symbol(e[[1L]])) return(FALSE)
  nm <- as.character(e[[1L]])
  if (nm == "break") return(TRUE)
  if (nm %in% c("for", "while", "repeat", "function")) return(FALSE)
  any(vapply(as.list(e)[-1L], function(a) !missing(a) && aw_has_break(a), logical(1)))
}

# Walks one expression. `defs` holds the names definitely assigned at this
# point; the result is the set after the expression.
aw_walk <- function(e, defs, s, in_for_seq = FALSE) {
  if (missing(e)) aw_unsupported("an empty argument")
  if (is.symbol(e)) {
    nm <- as.character(e)
    if (!nzchar(nm)) aw_unsupported("an empty argument")
    if (nm %in% defs) return(defs)
    if (nm %in% c("pi", "T", "F")) {
      s$consts <- c(s$consts, nm)
      return(defs)
    }
    if (nm %in% s$targets)
      aw_unsupported(sprintf("variable '%s' may be used before it is assigned (R would look it up outside the function)", nm))
    aw_unsupported(sprintf("free variable '%s' (subset v0 compiles self-contained functions)", nm))
  }
  if (is.atomic(e)) {
    if (length(e) != 1L || !(typeof(e) %in% c("double", "integer", "logical")))
      aw_unsupported(sprintf("a %s constant", typeof(e)), e)
    return(defs)
  }
  if (!is.call(e)) aw_unsupported("an unsupported expression", e)
  fn <- e[[1L]]
  if (!is.symbol(fn)) aw_unsupported("a call of a computed function", e)
  nm <- as.character(fn)
  args <- as.list(e)[-1L]
  if (!(nm %in% names(aw_arity))) {
    why <- aw_planned[nm]
    if (is.na(why)) why <- sprintf("call to `%s` is not in subset v0", nm)
    aw_unsupported(why, e)
  }
  n <- length(args)
  ar <- aw_arity[[nm]]
  if (!(n %in% ar) && !(length(ar) == 2L && is.infinite(ar[2L]) && n >= ar[1L])) {
    if (nm %in% c("[", "[[") && n > 3L) aw_unsupported("arrays of more than two dimensions are outside subset v0", e)
    if (nm == "log" && n == 2L) aw_unsupported("log() with a base is planned for slice 2", e)
    if (nm == "sum" && n > 1L) aw_unsupported("sum() of several arguments or with na.rm is planned for slice 2", e)
    aw_unsupported(sprintf("`%s` with %d argument(s)", nm, n), e)
  }
  an <- names(args)
  if (!is.null(an) && any(nzchar(an))) {
    ok <- an[nzchar(an)] %in% aw_argnames[[nm]]
    if (!all(ok) || anyDuplicated(an[nzchar(an)])) aw_unsupported("a named argument", e)
  }
  s$calls <- c(s$calls, nm)

  switch(nm,
    "{" = {
      for (a in args) defs <- aw_walk(a, defs, s)
      defs
    },
    "<-" = , "=" = {
      tgt <- args[[1L]]
      defs <- aw_walk(args[[2L]], defs, s)
      if (is.symbol(tgt)) {
        t <- as.character(tgt)
        if (t %in% s$formals) s$reassigned <- c(s$reassigned, t)
        return(union(defs, t))
      }
      if (is.call(tgt) && is.symbol(tgt[[1L]]) && as.character(tgt[[1L]]) %in% c("[", "[[")) {
        if (!(length(tgt) %in% 3:4) || !is.symbol(tgt[[2L]]))
          aw_unsupported("this form of sub-assignment", e)
        if (length(tgt) == 4L && (identical(tgt[[3L]], quote(expr = )) || identical(tgt[[4L]], quote(expr = ))))
          aw_unsupported("assigning a row or column of a matrix is planned for a later slice", e)
        x <- as.character(tgt[[2L]])
        if (!(x %in% defs)) aw_unsupported(sprintf("sub-assignment into '%s' before it is assigned", x), e)
        s$vec <- c(s$vec, x)
        s$subassigned <- c(s$subassigned, x)
        s$calls <- c(s$calls, paste0(as.character(tgt[[1L]]), "<-"))
        for (k in 3:length(tgt)) defs <- aw_walk(tgt[[k]], defs, s)
        return(defs)
      }
      aw_unsupported("replacement functions such as names(x) <- v", e)
    },
    "if" = {
      defs <- aw_walk(args[[1L]], defs, s)
      d1 <- aw_walk(args[[2L]], defs, s)
      if (n == 3L) intersect(d1, aw_walk(args[[3L]], defs, s)) else defs
    },
    "for" = {
      v <- args[[1L]]
      sq <- args[[2L]]
      if (!is.symbol(v)) aw_unsupported("a for loop without a variable", e)
      ok_seq <- is.symbol(sq) || (is.call(sq) && is.symbol(sq[[1L]]) &&
                                    as.character(sq[[1L]]) %in% c(":", "seq_len", "seq_along"))
      if (!ok_seq)
        aw_unsupported("for loops run over seq_len(), seq_along(), a:b or a vector variable in subset v0", sq)
      if (is.symbol(sq)) s$vec <- c(s$vec, as.character(sq))
      if (is.call(sq) && identical(sq[[1L]], as.name("seq_along")) && is.symbol(sq[[2L]]))
        s$vec <- c(s$vec, as.character(sq[[2L]]))
      defs <- aw_walk(sq, defs, s, in_for_seq = TRUE)
      vn <- as.character(v)
      if (vn %in% s$formals) s$reassigned <- c(s$reassigned, vn)
      s$loop <- s$loop + 1L
      aw_walk(args[[3L]], union(defs, vn), s)
      s$loop <- s$loop - 1L
      defs
    },
    "while" = {
      defs <- aw_walk(args[[1L]], defs, s)
      s$loop <- s$loop + 1L
      aw_walk(args[[2L]], defs, s)
      s$loop <- s$loop - 1L
      defs
    },
    "repeat" = {
      # The body runs at least once, so names assigned before its first
      # statement that can break are assigned after the loop too.
      body <- args[[1L]]
      stmts <- if (is.call(body) && identical(body[[1L]], as.name("{"))) as.list(body)[-1L] else list(body)
      s$loop <- s$loop + 1L
      d <- defs
      exit <- NULL
      for (st in stmts) {
        if (is.null(exit) && aw_has_break(st)) exit <- d
        d <- aw_walk(st, d, s)
      }
      s$loop <- s$loop - 1L
      if (is.null(exit)) d else exit
    },
    "break" = , "next" = {
      if (s$loop < 1L) aw_unsupported(sprintf("`%s` outside a loop", nm))
      defs
    },
    "&&" = , "||" = {
      defs <- aw_walk(args[[1L]], defs, s)
      aw_walk(args[[2L]], defs, s)
      defs
    },
    "$" = {
      inner <- args[[1L]]
      if (!is.symbol(inner) && !(is.call(inner) && identical(inner[[1L]], as.name(".lm.fit"))))
        aw_unsupported("lists and `$` are outside subset v0 (except the result of .lm.fit())", e)
      if (!is.symbol(args[[2L]]) || !(as.character(args[[2L]]) %in% aw_lmfit_fields))
        aw_unsupported("only $coefficients, $residuals, $rank and $pivot of .lm.fit() are compiled", e)
      aw_walk(inner, defs, s)
    },
    "[" = , "[[" = {
      if (!is.symbol(args[[1L]])) aw_unsupported("indexing a computed value is planned for slice 2", e)
      s$vec <- c(s$vec, as.character(args[[1L]]))
      empty <- logical(n)
      for (k in seq_len(n)) empty[k] <- identical(args[[k]], quote(expr = ))
      if (n == 3L && nm == "[" && sum(empty) == 1L) {
        for (k in which(!empty)) defs <- aw_walk(args[[k]], defs, s)
        return(defs)
      }
      for (k in seq_along(args)) defs <- aw_walk(args[[k]], defs, s)
      defs
    },
    {
      for (a in args) defs <- aw_walk(a, defs, s)
      defs
    }
  )
}
