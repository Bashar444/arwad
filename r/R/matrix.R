# Matrices (slice 2b): a column-major vector plus its dimensions. Where GNU R
# signals an error or a warning (non-conformable operands, a subscript out of
# bounds, data that do not fill a matrix exactly) the call is left to GNU R.

# Dimensions of an elementwise result: those of the matrix operand. Two
# matrices must have equal dimensions, and a vector operand must be non-empty
# and no longer than the matrix.
cx_conform <- function(cx, a, b, e) {
  if (a$kind != "m" && b$kind != "m") return(NULL)
  if (a$kind == "m" && b$kind == "m") {
    cx_emit(cx, sprintf("if %s != %s || %s != %s { %s }", a$nr, b$nr, a$nc, b$nc,
                        cx_bail(cx, "non-conformable arrays", e)))
    return(list(nr = a$nr, nc = a$nc))
  }
  m <- if (a$kind == "m") a else b
  o <- if (a$kind == "m") b else a
  if (o$kind == "v") {
    cx_emit(cx, sprintf("if %s.len == 0 || %s.len > %s.len { %s }", o$g, o$g, m$g,
                        cx_bail(cx, "a vector of a length the matrix does not match", e)))
  }
  list(nr = m$nr, nc = m$nc)
}

# A row or column subscript as a 1-based i64; anything but a whole number
# within the extent is left to GNU R.
cx_mat_index <- function(cx, v, extent, e) {
  if (v$type %in% c("null", "exit")) aw_unsupported("a subscript without a value", e)
  if (v$kind != "s") aw_unsupported("matrix subscripts that are vectors are planned for a later slice", e)
  if (v$type == "lgl") aw_unsupported("logical matrix subscripts are planned for a later slice", e)
  t <- cx_tmp(cx)
  b <- cx_bail(cx, "a matrix subscript that is NA or out of bounds", e)
  if (v$type == "int") {
    cx_emit(cx, sprintf("if %s == na_i || %s < 1 || %s > %s { %s }", v$g, v$g, v$g, extent, b))
    cx_emit(cx, sprintf("let %s: i64 = %s;", t, v$g))
  } else {
    cx_emit(cx, sprintf("if !(%s >= 1.0 && %s < %s as f64 + 1.0) { %s }", v$g, v$g, extent, b))
    cx_emit(cx, sprintf("let %s: i64 = %s as i64;", t, v$g))
  }
  t
}

cx_is_empty <- function(a) identical(a, quote(expr = ))

# m[i, j], m[i, ] and m[, j] (the last two drop to vectors, as R's default).
cx_mat_read <- function(cx, a, e) {
  x <- aw_gen(cx, a[[1L]])
  if (x$kind != "m") aw_unsupported("x[i, j] of a value that is not a matrix", e)
  ei <- cx_is_empty(a[[2L]])
  ej <- cx_is_empty(a[[3L]])
  i <- if (!ei) cx_mat_index(cx, aw_gen(cx, a[[2L]]), x$nr, e)
  j <- if (!ej) cx_mat_index(cx, aw_gen(cx, a[[3L]]), x$nc, e)
  t <- cx_tmp(cx)
  if (!ei && !ej) {
    cx_emit(cx, sprintf("let %s: %s = %s[(%s - 1) * %s + %s - 1];", t, aw_g[[x$type]], x$g, j, x$nr, i))
    return(aw_val(t, x$type))
  }
  k <- cx_tmp(cx)
  n <- if (ei) x$nr else x$nc
  src <- if (ei) sprintf("%s[(%s - 1) * %s + %s]", x$g, j, x$nr, k) else sprintf("%s[%s * %s + %s - 1]", x$g, k, x$nr, i)
  cx_emit(cx, sprintf("var %s: %s[>..] = [];", t, aw_g[[x$type]]))
  cx_emit(cx, sprintf("%s.resize(%s, %s);", t, n, aw_zero[[x$type]]))
  cx_emit(cx, sprintf("for %s in 0..%s { %s[%s] = %s; }", k, n, t, k, src))
  aw_val(t, x$type, "v")
}

# m[i, j] <- v for one value.
cx_mat_write <- function(cx, nm, tgt, v, e) {
  var <- get0(nm, envir = cx$vars, inherits = FALSE)
  if (var$kind != "m") aw_unsupported("x[i, j] <- v on a value that is not a matrix", e)
  if (v$kind != "s") aw_unsupported("assigning a vector into m[i, j] is planned for a later slice", e)
  cx_scalar(v, e)
  if (aw_rank[[v$type]] > aw_rank[[var$type]])
    aw_unsupported(sprintf("assigning a %s into '%s' would change it from %s to %s; subset v0 keeps one type per variable",
                           aw_tname[[v$type]], nm, aw_tname[[var$type]], aw_tname[[v$type]]), e)
  cv <- cx_as(cx, v, var$type)
  i <- cx_mat_index(cx, aw_gen(cx, tgt[[3L]]), var$nr, e)
  j <- cx_mat_index(cx, aw_gen(cx, tgt[[4L]]), var$nc, e)
  cx_emit(cx, sprintf("%s[(%s - 1) * %s + %s - 1] = %s;", var$g, j, var$nr, i, cv$g))
  v
}

# matrix(data, nrow, ncol), by column. GNU R takes over when the data do not
# fill the matrix a whole number of times (R warns) or are empty.
cx_matrix <- function(cx, args, e) {
  data <- if (is.null(args$data)) aw_val("na_i", "lgl") else aw_gen(cx, args$data)
  if (data$type %in% c("null", "exit")) aw_unsupported("matrix() of no value", e)
  ld <- cx_tmp(cx)
  cx_emit(cx, sprintf("let %s: i64 = %s;", ld, cx_len(data)))
  given <- function(nm) if (!is.null(args[[nm]])) cx_count(cx, aw_gen(cx, args[[nm]]), e)
  nr <- given("nrow")
  nc <- given("ncol")
  b <- cx_bail(cx, "data that do not fill the matrix a whole number of times (R warns)", e)
  if (is.null(nr) && is.null(nc)) {
    nr <- ld
    nc <- "1"
  } else if (is.null(nc)) {
    nc <- cx_tmp(cx)
    cx_emit(cx, sprintf("if %s == 0 { %s }", nr, b))
    cx_emit(cx, sprintf("let %s: i64 = (%s + %s - 1) / %s;", nc, ld, nr, nr))
  } else if (is.null(nr)) {
    nr <- cx_tmp(cx)
    cx_emit(cx, sprintf("if %s == 0 { %s }", nc, b))
    cx_emit(cx, sprintf("let %s: i64 = (%s + %s - 1) / %s;", nr, ld, nc, nc))
  }
  tot <- cx_tmp(cx)
  cx_emit(cx, sprintf("let %s: i64 = %s * %s;", tot, nr, nc))
  cx_emit(cx, sprintf("if %s == 0 || (%s > 1 && (%s == 0 || %s %% %s != 0)) { %s }", ld, ld, tot, tot, ld, b))
  t <- cx_tmp(cx)
  k <- cx_tmp(cx)
  cx_emit(cx, sprintf("var %s: %s[>..] = [];", t, aw_g[[data$type]]))
  cx_emit(cx, sprintf("%s.resize(%s, %s);", t, tot, aw_zero[[data$type]]))
  src <- if (data$kind == "s") data$g else sprintf("%s[%s %% %s]", data$g, k, ld)
  cx_emit(cx, sprintf("for %s in 0..%s { %s[%s] = %s; }", k, tot, t, k, src))
  aw_val(t, data$type, "m", nr, nc)
}

# nrow(), ncol() and dim() of a matrix (of a vector they are NULL in R).
cx_dims <- function(cx, fn, v, e) {
  if (v$kind != "m") aw_unsupported(sprintf("%s() of a value that is not a matrix (R gives NULL)", fn), e)
  t <- cx_tmp(cx)
  if (fn == "dim") {
    cx_emit(cx, sprintf("var %s: i32[>..] = [];", t))
    cx_emit(cx, sprintf("%s.resize(2, 0);", t))
    cx_emit(cx, sprintf("%s[0] = %s as i32;", t, v$nr))
    cx_emit(cx, sprintf("%s[1] = %s as i32;", t, v$nc))
    return(aw_val(t, "int", "v"))
  }
  cx_emit(cx, sprintf("let %s: i32 = %s as i32;", t, if (fn == "nrow") v$nr else v$nc))
  aw_val(t, "int")
}

# t(): a matrix transposed; a vector or a scalar becomes one row.
cx_transpose <- function(cx, v, e) {
  if (v$type %in% c("null", "exit")) aw_unsupported("t() of no value", e)
  if (v$kind != "m") {
    arr <- if (v$kind == "v") v$g else cx_concat(cx, list(v), v$type, e)
    t <- cx_tmp(cx)
    cx_emit(cx, sprintf("var %s: %s[>..] = [];", t, aw_g[[v$type]]))
    cx_emit(cx, sprintf("%s.append(%s);", t, arr))
    return(aw_val(t, v$type, "m", "1", paste0(t, ".len")))
  }
  t <- cx_tmp(cx)
  i <- cx_tmp(cx)
  j <- cx_tmp(cx)
  cx_emit(cx, sprintf("var %s: %s[>..] = [];", t, aw_g[[v$type]]))
  cx_emit(cx, sprintf("%s.resize(%s.len, %s);", t, v$g, aw_zero[[v$type]]))
  cx_emit(cx, sprintf("for %s in 0..%s { for %s in 0..%s { %s[%s + %s * %s] = %s[%s + %s * %s]; } }",
                      i, v$nr, j, v$nc, t, j, i, v$nc, v$g, i, j, v$nr))
  aw_val(t, v$type, "m", v$nc, v$nr)
}
