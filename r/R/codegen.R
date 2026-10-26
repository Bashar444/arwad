# Code generation: one pass over the body that infers types and writes Goose.
#
# A value is a scalar (Goose f64 or i32) or a vector (a grow-only array, or a
# read-only slice of R's own memory for an argument the body never changes).
# Each variable keeps one type for the whole function. Every R operation is
# lowered to typed temporaries so that R's semantics stay explicit: NA
# propagation, integer overflow, three-valued logic, 1-based indexing.
# Wherever GNU R would signal an error or a warning, or do something the fast
# path does not model, the generated code returns a bailout code and the
# dispatcher re-runs the call in GNU R (ADR-0005).

aw_g <- c(dbl = "f64", int = "i32", lgl = "i32")
aw_zero <- c(dbl = "0.0", int = "0", lgl = "0")
aw_na <- c(dbl = "na_real", int = "na_i", lgl = "na_i")
aw_rank <- c(lgl = 1L, int = 2L, dbl = 3L)
aw_tname <- c(dbl = "double", int = "integer", lgl = "logical")
aw_big <- "4503599627370496.0" # 2^52: beyond it doubles are not all integers

aw_val <- function(g, type, kind = "s") list(g = g, type = type, kind = kind)

aw_tdesc <- function(v) paste(aw_tname[[v$type]], if (v$kind == "s") "scalar" else "vector")

cx_emit <- function(cx, ...) {
  cx$lines <- c(cx$lines, paste0(strrep("    ", cx$ind), ...))
}

cx_open <- function(cx, head) {
  cx_emit(cx, head, " {")
  cx$ind <- cx$ind + 1L
}

cx_close <- function(cx, tail = "}") {
  cx$ind <- cx$ind - 1L
  cx_emit(cx, tail)
}

cx_tmp <- function(cx) {
  cx$n <- cx$n + 1L
  paste0("t", cx$n)
}

# Registers a bailout reason and returns the Goose statement that takes it.
cx_bail <- function(cx, reason, e = NULL) {
  if (!is.null(e)) reason <- paste0(reason, " in ", aw_deparse(e))
  cx$bails <- c(cx$bails, reason)
  sprintf("return %d;", length(cx$bails) + 1L)
}

cx_var_new <- function(cx, nm, type, kind, init = NULL) {
  cx$nv <- cx$nv + 1L
  g <- paste0("v", cx$nv, "_", gsub("[^A-Za-z0-9]", "_", nm))
  if (kind == "s") {
    cx$decls <- c(cx$decls, sprintf("var %s: %s = %s;", g, aw_g[[type]],
                                    if (is.null(init)) aw_zero[[type]] else init))
  } else {
    cx$decls <- c(cx$decls, sprintf("var %s: %s[>..] = [];", g, aw_g[[type]]))
  }
  v <- list(g = g, type = type, kind = kind, ro = FALSE)
  assign(nm, v, envir = cx$vars)
  v
}

cx_scalar <- function(v, e) {
  if (v$type %in% c("null", "exit")) aw_unsupported("an expression without a value used as a value", e)
  if (v$kind != "s") aw_unsupported("vectorised operations are planned for slice 2", e)
  v
}

# Widening conversion of a scalar (logical -> integer -> double), as R coerces.
cx_as <- function(cx, v, type) {
  if (v$type == type) return(v)
  if (type == "dbl") {
    t <- cx_tmp(cx)
    cx_emit(cx, sprintf("let %s: f64 = if %s == na_i { na_real } else { %s };", t, v$g, v$g))
    return(aw_val(t, "dbl"))
  }
  aw_val(v$g, type)
}

# Any scalar as an R logical in an i32: 1, 0 or NA.
cx_lgl <- function(cx, v, e) {
  cx_scalar(v, e)
  if (v$type == "lgl") return(v$g)
  t <- cx_tmp(cx)
  if (v$type == "int") {
    cx_emit(cx, sprintf("let %s: i32 = if %s == na_i { na_i } else if %s != 0 { 1 } else { 0 };", t, v$g, v$g))
  } else {
    cx_emit(cx, sprintf("let %s: i32 = if aw_isnan(%s) { na_i } else if %s != 0.0 { 1 } else { 0 };", t, v$g, v$g))
  }
  t
}

cx_cond <- function(cx, e) {
  l <- cx_lgl(cx, aw_gen(cx, e), e)
  cx_emit(cx, sprintf("if %s == na_i { %s }", l, cx_bail(cx, "an NA condition", e)))
  l
}

# A count for numeric(n) or seq_len(n): a non-negative whole number.
cx_count <- function(cx, v, e) {
  cx_scalar(v, e)
  t <- cx_tmp(cx)
  b <- cx_bail(cx, "a length that is NA, negative, fractional or too large", e)
  if (v$type == "dbl") {
    cx_emit(cx, sprintf("if !(%s >= 0.0 && %s <= 2147483647.0 && aw_c_floor(%s) == %s) { %s }", v$g, v$g, v$g, v$g, b))
    cx_emit(cx, sprintf("let %s: i64 = %s as i64;", t, v$g))
  } else {
    cx_emit(cx, sprintf("if %s == na_i || %s < 0 { %s }", v$g, v$g, b))
    cx_emit(cx, sprintf("let %s: i64 = %s;", t, v$g))
  }
  t
}

# An end of a:b as an i64; GNU R takes over unless it is a whole number in
# integer range (only then is a:b an integer sequence).
cx_colon_end <- function(cx, v, e) {
  cx_scalar(v, e)
  t <- cx_tmp(cx)
  b <- cx_bail(cx, "an end of a:b that is NA, fractional or beyond integer range", e)
  if (v$type == "dbl") {
    cx_emit(cx, sprintf("if !(aw_c_fabs(%s) <= 2147483647.0 && aw_c_floor(%s) == %s) { %s }", v$g, v$g, v$g, b))
    cx_emit(cx, sprintf("let %s: i64 = %s as i64;", t, v$g))
  } else {
    cx_emit(cx, sprintf("if %s == na_i { %s }", v$g, b))
    cx_emit(cx, sprintf("let %s: i64 = %s;", t, v$g))
  }
  t
}

cx_assign <- function(cx, nm, v, e) {
  if (v$type %in% c("null", "exit")) aw_unsupported(sprintf("assigning no value to '%s'", nm), e)
  var <- get0(nm, envir = cx$vars, inherits = FALSE)
  if (is.null(var)) {
    var <- cx_var_new(cx, nm, v$type, v$kind)
  } else if (var$type != v$type || var$kind != v$kind) {
    aw_unsupported(sprintf("variable '%s' changes from %s to %s; subset v0 keeps one type per variable",
                           nm, aw_tdesc(var), aw_tdesc(v)), e)
  }
  if (v$kind == "s") {
    cx_emit(cx, sprintf("%s = %s;", var$g, v$g))
  } else if (v$g != var$g) {
    cx_emit(cx, sprintf("%s.clear();", var$g))
    cx_emit(cx, sprintf("%s.append(%s);", var$g, v$g))
  }
  var
}

# numeric(n), integer(n), logical(n): into a variable, or into a fresh array.
cx_ctor <- function(cx, e, into = NULL) {
  type <- c(numeric = "dbl", integer = "int", logical = "lgl")[[as.character(e[[1L]])]]
  n <- if (length(e) == 2L) aw_gen(cx, e[[2L]]) else aw_val("0", "int")
  cnt <- cx_count(cx, n, e)
  if (is.null(into)) {
    g <- cx_tmp(cx)
    cx_emit(cx, sprintf("var %s: %s[>..] = [];", g, aw_g[[type]]))
  } else {
    var <- get0(into, envir = cx$vars, inherits = FALSE)
    if (is.null(var)) {
      var <- cx_var_new(cx, into, type, "v")
    } else if (var$type != type || var$kind != "v") {
      aw_unsupported(sprintf("variable '%s' changes from %s to a %s vector; subset v0 keeps one type per variable",
                             into, aw_tdesc(var), aw_tname[[type]]), e)
    }
    g <- var$g
    cx_emit(cx, sprintf("%s.clear();", g))
  }
  cx_emit(cx, sprintf("%s.resize(%s, %s);", g, cnt, aw_zero[[type]]))
  aw_val(g, type, "v")
}

cx_index_read <- function(cx, x, i, strict, e) {
  cx_scalar(i, e)
  if (i$type == "lgl") aw_unsupported("logical indices are planned for slice 2", e)
  type <- x$type
  len <- if (x$kind == "v") paste0(x$g, ".len") else "1"
  elt <- function(k) if (x$kind == "v") sprintf("%s[%s - 1]", x$g, k) else x$g
  t <- cx_tmp(cx)
  k <- cx_tmp(cx)
  if (strict) {
    b <- cx_bail(cx, "an index that is NA, zero, negative or out of range", e)
    cx_emit(cx, sprintf("var %s: %s = %s;", t, aw_g[[type]], aw_zero[[type]]))
    if (i$type == "int") {
      cx_emit(cx, sprintf("if %s == na_i || %s < 1 || %s > %s { %s }", i$g, i$g, i$g, len, b))
      cx_emit(cx, sprintf("let %s: i64 = %s;", k, i$g))
    } else {
      cx_emit(cx, sprintf("if !(%s >= 1.0 && %s < %s) { %s }", i$g, i$g, aw_big, b))
      cx_emit(cx, sprintf("let %s: i64 = %s as i64;", k, i$g))
      cx_emit(cx, sprintf("if %s > %s { %s }", k, len, b))
    }
    cx_emit(cx, sprintf("%s = %s;", t, elt(k)))
  } else {
    b <- cx_bail(cx, "a zero or negative index", e)
    cx_emit(cx, sprintf("var %s: %s = %s;", t, aw_g[[type]], aw_na[[type]]))
    if (i$type == "int") {
      cx_open(cx, sprintf("if %s != na_i", i$g))
      cx_emit(cx, sprintf("if %s < 1 { %s }", i$g, b))
      cx_emit(cx, sprintf("let %s: i64 = %s;", k, i$g))
      cx_emit(cx, sprintf("if %s <= %s { %s = %s; }", k, len, t, elt(k)))
      cx_close(cx)
    } else {
      cx_open(cx, sprintf("if !aw_isnan(%s)", i$g))
      cx_emit(cx, sprintf("if %s < 1.0 { %s }", i$g, b))
      cx_open(cx, sprintf("if %s < %s", i$g, aw_big))
      cx_emit(cx, sprintf("let %s: i64 = %s as i64;", k, i$g))
      cx_emit(cx, sprintf("if %s <= %s { %s = %s; }", k, len, t, elt(k)))
      cx_close(cx)
      cx_close(cx)
    }
  }
  aw_val(t, type)
}

cx_index_write <- function(cx, nm, i, v, e) {
  var <- get0(nm, envir = cx$vars, inherits = FALSE)
  if (var$kind != "v") aw_unsupported(sprintf("sub-assignment into the scalar '%s' is planned for slice 2", nm), e)
  cx_scalar(i, e)
  if (i$type == "lgl") aw_unsupported("logical indices are planned for slice 2", e)
  if (v$kind != "s") aw_unsupported("assigning a vector into x[i] is planned for slice 2", e)
  cx_scalar(v, e)
  if (aw_rank[[v$type]] > aw_rank[[var$type]])
    aw_unsupported(sprintf("assigning a %s into '%s' would change it from %s to %s; subset v0 keeps one type per variable",
                           aw_tname[[v$type]], nm, aw_tname[[var$type]], aw_tname[[v$type]]), e)
  cv <- cx_as(cx, v, var$type)
  k <- cx_tmp(cx)
  b <- cx_bail(cx, "a sub-assignment index that is NA, zero, negative or very large", e)
  if (i$type == "int") {
    cx_emit(cx, sprintf("if %s == na_i || %s < 1 { %s }", i$g, i$g, b))
    cx_emit(cx, sprintf("let %s: i64 = %s;", k, i$g))
  } else {
    cx_emit(cx, sprintf("if !(%s >= 1.0 && %s < 2147483648.0) { %s }", i$g, i$g, b))
    cx_emit(cx, sprintf("let %s: i64 = %s as i64;", k, i$g))
  }
  cx_emit(cx, sprintf("if %s > %s.len { %s.resize(%s, %s); }", k, var$g, var$g, k, aw_na[[var$type]]))
  cx_emit(cx, sprintf("%s[%s - 1] = %s;", var$g, k, cv$g))
  v
}

cx_arith <- function(cx, op, a, b, e) {
  cx_scalar(a, e)
  cx_scalar(b, e)
  ints <- a$type != "dbl" && b$type != "dbl"
  t <- cx_tmp(cx)
  if (ints && op %in% c("+", "-", "*")) {
    w <- cx_tmp(cx)
    cx_emit(cx, sprintf("var %s: i32 = na_i;", t))
    cx_open(cx, sprintf("if %s != na_i && %s != na_i", a$g, b$g))
    cx_emit(cx, sprintf("let %s: i64 = (%s as i64) %s %s;", w, a$g, op, b$g))
    cx_emit(cx, sprintf("if %s > 2147483647 || %s < -2147483647 { %s }", w, w, cx_bail(cx, "integer overflow", e)))
    cx_emit(cx, sprintf("%s = %s as i32;", t, w))
    cx_close(cx)
    return(aw_val(t, "int"))
  }
  if (op %in% c("%%", "%/%")) {
    if (ints) {
      cx_emit(cx, sprintf("var %s: i32 = na_i;", t))
      cx_open(cx, sprintf("if %s != na_i && %s != na_i && %s != 0", a$g, b$g, b$g))
      x <- a$g
      y <- b$g
    } else {
      da <- cx_as(cx, a, "dbl")$g
      db <- cx_as(cx, b, "dbl")$g
      ok <- sprintf("aw_c_fabs(%s) <= %s && aw_c_fabs(%s) <= %s && aw_c_floor(%s) == %s && aw_c_floor(%s) == %s && %s != 0.0",
                    da, aw_big, db, aw_big, da, da, db, db, db)
      cx_emit(cx, sprintf("if !(%s) { %s }", ok, cx_bail(cx, "%% or %/% of doubles that are not whole numbers below 2^52", e)))
      cx_emit(cx, sprintf("var %s: f64 = 0.0;", t))
      cx_open(cx, "if true")
      x <- paste0("(", da, " as i64)")
      y <- paste0("(", db, " as i64)")
    }
    xi <- cx_tmp(cx); yi <- cx_tmp(cx); q <- cx_tmp(cx); r <- cx_tmp(cx)
    cx_emit(cx, sprintf("let %s: i64 = %s;", xi, x))
    cx_emit(cx, sprintf("let %s: i64 = %s;", yi, y))
    cx_emit(cx, sprintf("var %s: i64 = %s / %s;", q, xi, yi))
    cx_emit(cx, sprintf("var %s: i64 = %s - %s * %s;", r, xi, q, yi))
    cx_emit(cx, sprintf("if %s != 0 && ((%s < 0) != (%s < 0)) { %s = %s - 1; %s = %s + %s; }", r, r, yi, q, q, r, r, yi))
    res <- if (op == "%%") r else q
    cx_emit(cx, sprintf("%s = %s%s;", t, res, if (ints) " as i32" else ""))
    cx_close(cx)
    return(aw_val(t, if (ints) "int" else "dbl"))
  }
  if (op == "^" && ints) {
    # R: 1L ^ y and x ^ 0L are 1, then NA if either is NA.
    cx_emit(cx, sprintf("let %s: f64 = if %s == 1 || %s == 0 { 1.0 } else if %s == na_i || %s == na_i { na_real } else { aw_r_pow(%s, %s) };",
                        t, a$g, b$g, a$g, b$g, a$g, b$g))
    return(aw_val(t, "dbl"))
  }
  da <- cx_as(cx, a, "dbl")$g
  db <- cx_as(cx, b, "dbl")$g
  if (op == "^") {
    cx_emit(cx, sprintf("let %s: f64 = aw_r_pow(%s, %s);", t, da, db))
  } else {
    cx_emit(cx, sprintf("let %s: f64 = %s %s %s;", t, da, op, db))
  }
  aw_val(t, "dbl")
}

cx_compare <- function(cx, op, a, b, e) {
  cx_scalar(a, e)
  cx_scalar(b, e)
  t <- cx_tmp(cx)
  if (a$type == "dbl" || b$type == "dbl") {
    x <- cx_as(cx, a, "dbl")$g
    y <- cx_as(cx, b, "dbl")$g
    cx_emit(cx, sprintf("let %s: i32 = if aw_isnan(%s) || aw_isnan(%s) { na_i } else if %s %s %s { 1 } else { 0 };", t, x, y, x, op, y))
  } else {
    cx_emit(cx, sprintf("let %s: i32 = if %s == na_i || %s == na_i { na_i } else if %s %s %s { 1 } else { 0 };", t, a$g, b$g, a$g, op, b$g))
  }
  aw_val(t, "lgl")
}

cx_math <- function(cx, fn, v, e) {
  cx_scalar(v, e)
  t <- cx_tmp(cx)
  if (fn == "abs") {
    if (v$type == "dbl") {
      cx_emit(cx, sprintf("let %s: f64 = aw_c_fabs(%s);", t, v$g))
      return(aw_val(t, "dbl"))
    }
    cx_emit(cx, sprintf("let %s: i32 = if %s == na_i { na_i } else if %s < 0 { -%s } else { %s };", t, v$g, v$g, v$g, v$g))
    return(aw_val(t, "int"))
  }
  x <- cx_as(cx, v, "dbl")$g
  cx_emit(cx, sprintf("let %s: f64 = if aw_isnan(%s) { %s } else { aw_c_%s(%s) };", t, x, x, fn, x))
  cx_emit(cx, sprintf("if aw_isnan(%s) && !aw_isnan(%s) { %s }", t, x, cx_bail(cx, "NaNs produced (R warns)", e)))
  aw_val(t, "dbl")
}

cx_sum <- function(cx, v, e) {
  if (v$type %in% c("null", "exit")) aw_unsupported("sum() of no value", e)
  t <- cx_tmp(cx)
  if (v$kind == "s") {
    if (v$type == "dbl") {
      cx_emit(cx, sprintf("let %s: f64 = 0.0 + %s;", t, v$g))
      return(aw_val(t, "dbl"))
    }
    return(aw_val(v$g, "int"))
  }
  if (v$type == "dbl") {
    cx_emit(cx, sprintf("let %s: f64 = aw_rsum(%s);", t, v$g))
    return(aw_val(t, "dbl"))
  }
  acc <- cx_tmp(cx); k <- cx_tmp(cx); na <- cx_tmp(cx)
  cx_emit(cx, sprintf("var %s: i64 = 0;", acc))
  cx_emit(cx, sprintf("var %s: bool = false;", na))
  cx_open(cx, sprintf("for %s in 0..%s.len", k, v$g))
  cx_emit(cx, sprintf("if %s[%s] == na_i { %s = true; break; }", v$g, k, na))
  cx_emit(cx, sprintf("%s += %s[%s];", acc, v$g, k))
  cx_close(cx)
  cx_emit(cx, sprintf("if !%s && (%s > 2147483647 || %s < -2147483647) { %s }", na, acc, acc,
                      cx_bail(cx, "integer overflow in sum() (R warns)", e)))
  cx_emit(cx, sprintf("let %s: i32 = if %s { na_i } else { %s as i32 };", t, na, acc))
  aw_val(t, "int")
}

cx_return <- function(cx, v, visible) {
  if (v$type == "exit") return(invisible())
  if (v$type == "null") {
    cx_emit(cx, "aw_ret_null();")
  } else {
    cx_emit(cx, sprintf("aw_ret_%s%s(%s);", v$type, if (v$kind == "s") "1" else "", v$g))
  }
  cx_emit(cx, if (visible) "return 0;" else "return 1;")
}

cx_head <- function(e) if (is.call(e) && is.symbol(e[[1L]])) as.character(e[[1L]]) else ""

# The function's value: emitted at each tail so that each branch hands back
# its own value and visibility, as R does.
aw_tail <- function(cx, e) {
  h <- cx_head(e)
  if (h == "{") {
    st <- as.list(e)[-1L]
    if (length(st) == 0L) return(cx_return(cx, aw_val("", "null"), TRUE))
    for (s in st[-length(st)]) aw_gen(cx, s, want = FALSE)
    return(aw_tail(cx, st[[length(st)]]))
  }
  if (h == "if") {
    l <- cx_cond(cx, e[[2L]])
    cx_open(cx, sprintf("if %s != 0", l))
    aw_tail(cx, e[[3L]])
    cx_close(cx, "} else {")
    cx$ind <- cx$ind + 1L
    if (length(e) == 4L) aw_tail(cx, e[[4L]]) else cx_return(cx, aw_val("", "null"), FALSE)
    cx_close(cx)
    return(invisible())
  }
  if (h %in% c("<-", "=", "for", "while", "repeat")) {
    return(cx_return(cx, aw_gen(cx, e, want = FALSE), FALSE))
  }
  cx_return(cx, aw_gen(cx, e), TRUE)
}

aw_gen <- function(cx, e, want = TRUE) {
  if (is.symbol(e)) {
    nm <- as.character(e)
    v <- get0(nm, envir = cx$vars, inherits = FALSE)
    if (!is.null(v)) return(aw_val(v$g, v$type, v$kind))
    if (nm == "pi") return(aw_val(sprintf("%a", pi), "dbl"))
    if (nm == "T") return(aw_val("1", "lgl"))
    if (nm == "F") return(aw_val("0", "lgl"))
    aw_unsupported(sprintf("internal: unknown name '%s'", nm))
  }
  if (is.atomic(e)) {
    t <- cx_tmp(cx)
    switch(typeof(e),
      double = {
        g <- if (is.nan(e)) "r_nan" else if (is.na(e)) "na_real" else if (is.infinite(e)) "r_inf" else sprintf("%a", e)
        cx_emit(cx, sprintf("let %s: f64 = %s;", t, g))
        return(aw_val(t, "dbl"))
      },
      integer = {
        cx_emit(cx, sprintf("let %s: i32 = %s;", t, if (is.na(e)) "na_i" else as.character(e)))
        return(aw_val(t, "int"))
      },
      logical = {
        cx_emit(cx, sprintf("let %s: i32 = %s;", t, if (is.na(e)) "na_i" else if (e) "1" else "0"))
        return(aw_val(t, "lgl"))
      }
    )
  }
  nm <- as.character(e[[1L]])
  a <- as.list(e)[-1L]
  switch(nm,
    "{" = {
      if (length(a) == 0L) return(aw_val("", "null"))
      for (s in a[-length(a)]) aw_gen(cx, s, want = FALSE)
      aw_gen(cx, a[[length(a)]], want)
    },
    "(" = aw_gen(cx, a[[1L]]),
    "<-" = , "=" = {
      tgt <- a[[1L]]
      if (is.symbol(tgt)) {
        t <- as.character(tgt)
        if (cx_head(a[[2L]]) %in% c("numeric", "integer", "logical")) {
          return(cx_ctor(cx, a[[2L]], into = t))
        }
        var <- cx_assign(cx, t, aw_gen(cx, a[[2L]]), e)
        return(aw_val(var$g, var$type, var$kind))
      }
      v <- aw_gen(cx, a[[2L]])
      i <- aw_gen(cx, tgt[[3L]])
      cx_index_write(cx, as.character(tgt[[2L]]), i, v, e)
    },
    "if" = {
      if (want && length(a) == 2L) aw_unsupported("the value of an if without else", e)
      l <- cx_cond(cx, a[[1L]])
      if (!want) {
        cx_open(cx, sprintf("if %s != 0", l))
        aw_gen(cx, a[[2L]], want = FALSE)
        if (length(a) == 3L) {
          cx_close(cx, "} else {")
          cx$ind <- cx$ind + 1L
          aw_gen(cx, a[[3L]], want = FALSE)
        }
        cx_close(cx)
        return(aw_val("", "null"))
      }
      t <- cx_tmp(cx)
      put <- function(v) {
        if (v$type == "exit") return(invisible())
        cx_scalar(v, e)
        cx_emit(cx, sprintf("%s = %s;", t, v$g))
      }
      cx_open(cx, sprintf("if %s != 0", l))
      va <- aw_gen(cx, a[[2L]])
      put(va)
      cx_close(cx, "} else {")
      cx$ind <- cx$ind + 1L
      vb <- aw_gen(cx, a[[3L]])
      put(vb)
      cx_close(cx)
      types <- setdiff(c(va$type, vb$type), "exit")
      if (length(types) == 0L) return(aw_val("", "exit"))
      if (length(types) == 2L) aw_unsupported("if branches of different types are planned for slice 2", e)
      cx$decls <- c(cx$decls, sprintf("var %s: %s = %s;", t, aw_g[[types]], aw_zero[[types]]))
      aw_val(t, types)
    },
    "for" = {
      vn <- as.character(a[[1L]])
      sq <- a[[2L]]
      k <- cx_tmp(cx)
      sh <- cx_head(sq)
      if (is.symbol(sq)) {
        x <- aw_gen(cx, sq)
        if (x$kind == "v") {
          src <- x$g
          if (!isTRUE(get0(as.character(sq), envir = cx$vars, inherits = FALSE)$ro)) {
            src <- cx_tmp(cx) # R iterates over the vector as it was when the loop began
            cx_emit(cx, sprintf("var %s: %s[>..] = [];", src, aw_g[[x$type]]))
            cx_emit(cx, sprintf("%s.append(%s);", src, x$g))
          }
          cx_open(cx, sprintf("for %s in 0..%s.len", k, src))
          cx_assign(cx, vn, aw_val(sprintf("%s[%s]", src, k), x$type), e)
        } else {
          cx_open(cx, sprintf("for %s in 0..1", k))
          cx_assign(cx, vn, aw_val(x$g, x$type), e)
        }
      } else if (sh == ":") {
        fr <- cx_colon_end(cx, aw_gen(cx, sq[[2L]]), sq)
        to <- cx_colon_end(cx, aw_gen(cx, sq[[3L]]), sq)
        cnt <- cx_tmp(cx); step <- cx_tmp(cx)
        cx_emit(cx, sprintf("let %s: i64 = if %s <= %s { %s - %s + 1 } else { %s - %s + 1 };", cnt, fr, to, to, fr, fr, to))
        cx_emit(cx, sprintf("let %s: i64 = if %s <= %s { 1 } else { -1 };", step, fr, to))
        cx_open(cx, sprintf("for %s in 0..%s", k, cnt))
        cx_assign(cx, vn, aw_val(sprintf("(%s + %s * %s) as i32", fr, step, k), "int"), e)
      } else {
        if (sh == "seq_len") {
          cnt <- cx_count(cx, aw_gen(cx, sq[[2L]]), sq)
        } else {
          x <- aw_gen(cx, sq[[2L]])
          cnt <- if (x$kind == "v") paste0(x$g, ".len") else "1"
        }
        cx_open(cx, sprintf("for %s in 0..%s", k, cnt))
        cx_assign(cx, vn, aw_val(sprintf("(%s + 1) as i32", k), "int"), e)
      }
      aw_gen(cx, a[[3L]], want = FALSE)
      cx_close(cx)
      aw_val("", "null")
    },
    "while" = {
      cx_open(cx, "loop")
      l <- cx_cond(cx, a[[1L]])
      cx_emit(cx, sprintf("if %s == 0 { break; }", l))
      aw_gen(cx, a[[2L]], want = FALSE)
      cx_close(cx)
      aw_val("", "null")
    },
    "repeat" = {
      cx_open(cx, "loop")
      aw_gen(cx, a[[1L]], want = FALSE)
      cx_close(cx)
      aw_val("", "null")
    },
    "break" = {
      cx_emit(cx, "break;")
      aw_val("", "exit")
    },
    "next" = {
      cx_emit(cx, "continue;")
      aw_val("", "exit")
    },
    "return" = {
      v <- if (length(a) == 0L) aw_val("", "null") else aw_gen(cx, a[[1L]])
      cx_return(cx, v, TRUE)
      aw_val("", "exit")
    },
    "+" = , "-" = {
      if (length(a) == 2L) return(cx_arith(cx, nm, aw_gen(cx, a[[1L]]), aw_gen(cx, a[[2L]]), e))
      v <- cx_scalar(aw_gen(cx, a[[1L]]), e)
      if (nm == "+") return(aw_val(v$g, if (v$type == "lgl") "int" else v$type))
      t <- cx_tmp(cx)
      if (v$type == "dbl") {
        cx_emit(cx, sprintf("let %s: f64 = -%s;", t, v$g))
        return(aw_val(t, "dbl"))
      }
      cx_emit(cx, sprintf("let %s: i32 = if %s == na_i { na_i } else { -%s };", t, v$g, v$g))
      aw_val(t, "int")
    },
    "*" = , "/" = , "^" = , "%%" = , "%/%" = cx_arith(cx, nm, aw_gen(cx, a[[1L]]), aw_gen(cx, a[[2L]]), e),
    "==" = , "!=" = , "<" = , "<=" = , ">" = , ">=" = cx_compare(cx, nm, aw_gen(cx, a[[1L]]), aw_gen(cx, a[[2L]]), e),
    "!" = {
      l <- cx_lgl(cx, aw_gen(cx, a[[1L]]), e)
      t <- cx_tmp(cx)
      cx_emit(cx, sprintf("let %s: i32 = if %s == na_i { na_i } else if %s == 0 { 1 } else { 0 };", t, l, l))
      aw_val(t, "lgl")
    },
    "&" = , "|" = {
      x <- cx_lgl(cx, aw_gen(cx, a[[1L]]), e)
      y <- cx_lgl(cx, aw_gen(cx, a[[2L]]), e)
      t <- cx_tmp(cx)
      if (nm == "&") {
        cx_emit(cx, sprintf("let %s: i32 = if %s == 0 || %s == 0 { 0 } else if %s == na_i || %s == na_i { na_i } else { 1 };", t, x, y, x, y))
      } else {
        cx_emit(cx, sprintf("let %s: i32 = if %s == 1 || %s == 1 { 1 } else if %s == na_i || %s == na_i { na_i } else { 0 };", t, x, y, x, y))
      }
      aw_val(t, "lgl")
    },
    "&&" = , "||" = {
      # The right operand is evaluated only when the left does not decide.
      t <- cx_tmp(cx)
      x <- cx_lgl(cx, aw_gen(cx, a[[1L]]), e)
      stop_at <- if (nm == "&&") "0" else "1"
      cx$decls <- c(cx$decls, sprintf("var %s: i32 = 0;", t))
      cx_emit(cx, sprintf("%s = %s;", t, stop_at))
      cx_open(cx, sprintf("if %s != %s", x, stop_at))
      y <- cx_lgl(cx, aw_gen(cx, a[[2L]]), e)
      other <- if (nm == "&&") "1" else "0"
      cx_emit(cx, sprintf("%s = if %s == %s { %s } else if %s == na_i || %s == na_i { na_i } else { %s };",
                          t, y, stop_at, stop_at, x, y, other))
      cx_close(cx)
      aw_val(t, "lgl")
    },
    "[" = , "[[" = cx_index_read(cx, aw_gen(cx, a[[1L]]), aw_gen(cx, a[[2L]]), nm == "[[", e),
    "length" = {
      v <- aw_gen(cx, a[[1L]])
      if (v$type %in% c("null", "exit")) aw_unsupported("length() of no value", e)
      t <- cx_tmp(cx)
      cx_emit(cx, sprintf("let %s: i32 = %s;", t, if (v$kind == "v") paste0(v$g, ".len as i32") else "1"))
      aw_val(t, "int")
    },
    "numeric" = , "integer" = , "logical" = cx_ctor(cx, e),
    "sqrt" = , "exp" = , "log" = , "abs" = cx_math(cx, nm, aw_gen(cx, a[[1L]]), e),
    "sum" = cx_sum(cx, aw_gen(cx, a[[1L]]), e),
    "is.na" = {
      v <- cx_scalar(aw_gen(cx, a[[1L]]), e)
      t <- cx_tmp(cx)
      test <- if (v$type == "dbl") sprintf("aw_isnan(%s)", v$g) else sprintf("%s == na_i", v$g)
      cx_emit(cx, sprintf("let %s: i32 = if %s { 1 } else { 0 };", t, test))
      aw_val(t, "lgl")
    },
    aw_unsupported(sprintf("internal: no code generation for `%s`", nm), e)
  )
}

aw_rt_externs <- c(
  "extern fn aw_ret_dbl(x: const f64[:]);",
  "extern fn aw_ret_int(x: const i32[:]);",
  "extern fn aw_ret_lgl(x: const i32[:]);",
  "extern fn aw_ret_dbl1(x: f64);",
  "extern fn aw_ret_int1(x: i32);",
  "extern fn aw_ret_lgl1(x: i32);",
  "extern fn aw_ret_null();",
  "extern fn aw_rsum(x: const f64[:]) -> f64;",
  'extern "R_pow" fn aw_r_pow(x: f64, y: f64) -> f64;',
  'extern "sqrt" fn aw_c_sqrt(x: f64) -> f64;',
  'extern "exp" fn aw_c_exp(x: f64) -> f64;',
  'extern "log" fn aw_c_log(x: f64) -> f64;',
  'extern "fabs" fn aw_c_fabs(x: f64) -> f64;',
  'extern "floor" fn aw_c_floor(x: f64) -> f64;'
)

# Generates the Goose unit and its C shim for one signature. `types` is a list
# with one list(type, kind) per formal. The symbol suffix @H@ is replaced by
# the content hash when the unit is built.
aw_codegen <- function(info, f, types, label) {
  cx <- new.env(parent = emptyenv())
  cx$lines <- character()
  cx$decls <- character()
  cx$ind <- 1L
  cx$n <- 0L
  cx$nv <- 0L
  cx$bails <- character()
  cx$vars <- new.env(parent = emptyenv())
  params <- character()
  copies <- character()
  sig <- character()
  for (i in seq_along(info$formals)) {
    nm <- info$formals[i]
    ty <- types[[i]]
    sig <- c(sig, paste0(nm, ": ", aw_tdesc(ty)))
    if (ty$kind == "s") {
      params <- c(params, sprintf("p%d: %s", i, aw_g[[ty$type]]))
      cx_var_new(cx, nm, ty$type, "s", init = paste0("p", i))
    } else {
      params <- c(params, sprintf("p%d: const %s[:]", i, aw_g[[ty$type]]))
      if (nm %in% c(info$reassigned, info$subassigned)) {
        v <- cx_var_new(cx, nm, ty$type, "v")
        copies <- c(copies, sprintf("    %s.append(p%d);", v$g, i))
      } else {
        assign(nm, list(g = paste0("p", i), type = ty$type, kind = "v", ro = TRUE), envir = cx$vars)
      }
    }
  }
  aw_tail(cx, body(f))
  params <- c(params, "na_real: f64", "r_nan: f64", "r_inf: f64")
  sig_txt <- if (length(sig)) paste(sig, collapse = ", ") else "no arguments"
  goose <- c(
    sprintf("// Generated by arwad %s for %s (%s). Do not edit.", utils::packageVersion("arwad"), label, sig_txt),
    "",
    aw_rt_externs,
    "",
    "fn aw_isnan(x: f64) -> bool { x != x }",
    "",
    sprintf('export "aw_entry_@H@" fn aw_entry(%s) -> i32 {', paste(params, collapse = ", ")),
    "    let na_i: i32 = -2147483647 - 1;",
    paste0("    ", cx$decls),
    copies,
    cx$lines,
    "}"
  )
  list(goose = paste(goose, collapse = "\n"), shim = aw_shim(info, types),
       bails = cx$bails, signature = sig_txt)
}

aw_sexp <- c(dbl = "REALSXP", int = "INTSXP", lgl = "LGLSXP")
aw_cptr <- c(dbl = "REAL", int = "INTEGER", lgl = "LOGICAL")

aw_shim <- function(info, types) {
  n <- length(info$formals)
  get <- character()
  pass <- character()
  for (i in seq_len(n)) {
    ty <- types[[i]]
    get <- c(get, sprintf("    SEXP a%d = VECTOR_ELT(args, %d);", i, i - 1L),
             sprintf("    aw_check_arg(a%d, %s, %d);", i, aw_sexp[[ty$type]], as.integer(ty$kind == "s")))
    if (ty$kind == "s") {
      pass <- c(pass, sprintf("%s(a%d)[0]", aw_cptr[[ty$type]], i))
    } else {
      sl <- if (ty$type == "dbl") "sl_f64" else "sl_i32"
      get <- c(get, sprintf("    %s s%d = {%s(a%d), (int64_t) XLENGTH(a%d)};", sl, i, aw_cptr[[ty$type]], i, i))
      pass <- c(pass, sprintf("s%d", i))
    }
  }
  pass <- c(pass, "NA_REAL", "R_NaN", "R_PosInf")
  paste(c(
    "/* Generated by arwad. Do not edit. */",
    "#include <stdint.h>",
    "#include <stdlib.h>",
    "#include <string.h>",
    "#include <R.h>",
    "#include <Rinternals.h>",
    '#include "unit.h"',
    "",
    "int aw_res_take(void **buf, int64_t *len);",
    "static int aw_ready = 0;",
    "",
    "static void aw_check_arg(SEXP a, SEXPTYPE type, int scalar)",
    "{",
    "    if (TYPEOF(a) != type || (scalar && XLENGTH(a) != 1))",
    '        error("arwad: an argument does not match the compiled signature");',
    "}",
    "",
    "SEXP aw_call_@H@(SEXP args)",
    "{",
    "    if (!aw_ready) {",
    '        static char arg0[] = "R";',
    "        static char *argv[] = {arg0, NULL};",
    "        goose_init(1, argv);",
    "        aw_ready = 1;",
    "    }",
    sprintf('    if (XLENGTH(args) != %d) error("arwad: wrong number of arguments");', n),
    get,
    sprintf("    int32_t st = aw_entry_@H@(%s);", paste(pass, collapse = ", ")),
    "    void *buf = NULL;",
    "    int64_t len = 0;",
    "    int rt = aw_res_take(&buf, &len);",
    '    if (rt < 0) error("arwad: out of memory while returning the result");',
    "    SEXP out = PROTECT(allocVector(VECSXP, 2));",
    "    SET_VECTOR_ELT(out, 0, ScalarInteger(st));",
    "    if (st <= 1 && rt >= 1 && rt <= 3) {",
    "        SEXPTYPE type = rt == 1 ? REALSXP : (rt == 2 ? INTSXP : LGLSXP);",
    "        SEXP v = allocVector(type, (R_xlen_t) len);",
    "        SET_VECTOR_ELT(out, 1, v);",
    "        if (len > 0) {",
    "            if (rt == 1) memcpy(REAL(v), buf, (size_t) len * sizeof(double));",
    "            else memcpy(rt == 2 ? INTEGER(v) : LOGICAL(v), buf, (size_t) len * sizeof(int));",
    "        }",
    "    }",
    "    free(buf);",
    "    UNPROTECT(1);",
    "    return out;",
    "}"
  ), collapse = "\n")
}
