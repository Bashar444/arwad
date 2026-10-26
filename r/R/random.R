# Random numbers: runif() and rnorm() draw from GNU R's own generators
# (Rf_runif and Rf_rnorm in R's C API, so unif_rand() and norm_rand() under
# whatever RNGkind() is set), between GetRNGstate() and PutRNGstate() in the
# unit's shim. The stream is therefore R's, bit for bit. When the native code
# bails out, the dispatcher restores .Random.seed before GNU R re-runs the
# call (ADR-0005).

# sample(x, size, replace) and sample.int(n, size, replace): indices come
# from R's own R_unif_index() (honouring RNGkind(sample.kind = ...)); with
# replacement (or fewer than two draws) each is drawn directly, without
# replacement from a shrinking pool, as R documents. A single number given
# to sample() means 1:x in R; that case and R's errors are left to GNU R.
cx_sample <- function(cx, fn, a, e) {
  pn <- if (fn == "sample") c("x", "size", "replace") else c("n", "size", "replace")
  m <- aw_match_args(a, pn)
  if (is.null(m[[pn[1L]]])) aw_unsupported(sprintf("%s() without its first argument", fn), e)
  xv <- aw_gen(cx, m[[pn[1L]]])
  if (xv$type %in% c("null", "exit")) aw_unsupported("a population without a value", e)
  sz <- if (!is.null(m$size)) aw_gen(cx, m$size)
  rp <- if (is.null(m$replace)) "0" else cx_lgl(cx, cx_scalarize(cx, aw_gen(cx, m$replace), e), e)
  cx_emit(cx, sprintf("if %s == na_i { %s }", rp, cx_bail(cx, "an NA replace argument (R errors)", e)))
  pop <- NULL
  if (fn == "sample" && xv$kind != "s") {
    cx_emit(cx, sprintf("if %s.len == 1 { %s }", xv$g, cx_bail(cx, "sample() of a single number (R samples 1:x)", e)))
    n <- paste0(xv$g, ".len")
    pop <- xv
  } else {
    if (fn == "sample") {
      if (xv$type == "lgl") aw_unsupported("sample() of a single logical value", e)
      ok <- if (xv$type == "dbl") sprintf("%s >= 1.0", xv$g) else sprintf("%s != na_i && %s >= 1", xv$g, xv$g)
      cx_emit(cx, sprintf("if !(%s) { %s }", ok, cx_bail(cx, "sample() of a number below 1 or not finite", e)))
    }
    n <- cx_count(cx, xv, e)
  }
  k <- if (is.null(sz)) n else cx_count(cx, sz, e)
  cx_emit(cx, sprintf("if (%s == 0 && %s > %s) || (%s == 0 && %s > 0) { %s }", rp, k, n, n, k,
                      cx_bail(cx, "a sample larger than the population without replacement (R errors)", e)))
  cx$rng <- TRUE
  t <- cx_tmp(cx); i <- cx_tmp(cx); pool <- cx_tmp(cx); left <- cx_tmp(cx); j <- cx_tmp(cx)
  cx_emit(cx, sprintf("var %s: i32[>..] = [];", t))
  cx_emit(cx, sprintf("%s.resize(%s, 0);", t, k))
  cx_open(cx, sprintf("if %s != 0 || %s < 2", rp, k))
  cx_emit(cx, sprintf("for %s in 0..%s { %s[%s] = (aw_r_unif_index(%s as f64) + 1.0) as i32; }", i, k, t, i, n))
  cx_close(cx, "} else {")
  cx$ind <- cx$ind + 1L
  cx_emit(cx, sprintf("var %s: i32[>..] = [];", pool))
  cx_emit(cx, sprintf("%s.resize(%s, 0);", pool, n))
  cx_emit(cx, sprintf("for %s in 0..%s { %s[%s] = %s as i32; }", i, n, pool, i, i))
  cx_emit(cx, sprintf("var %s: i64 = %s;", left, n))
  cx_open(cx, sprintf("for %s in 0..%s", i, k))
  cx_emit(cx, sprintf("let %s: i64 = aw_r_unif_index(%s as f64) as i64;", j, left))
  cx_emit(cx, sprintf("%s[%s] = %s[%s] + 1;", t, i, pool, j))
  cx_emit(cx, sprintf("%s -= 1;", left))
  cx_emit(cx, sprintf("%s[%s] = %s[%s];", pool, j, pool, left))
  cx_close(cx)
  cx_close(cx)
  idx <- aw_val(t, "int", "v")
  if (is.null(pop)) idx else cx_read_gather(cx, pop, idx, e)
}

cx_random <- function(cx, fn, a, e) {
  pn <- if (fn == "runif") c("n", "min", "max") else c("n", "mean", "sd")
  m <- aw_match_args(a, pn)
  if (is.null(m$n)) aw_unsupported(sprintf("%s() without n", fn), e)
  nv <- aw_gen(cx, m$n)
  if (nv$type %in% c("null", "exit")) aw_unsupported("a count without a value", e)
  defaults <- if (fn == "runif") c("0x0p+0", "0x1p+0") else c("0x0p+0", "0x1p+0")
  ps <- lapply(2:3, function(k) {
    if (is.null(m[[pn[k]]])) return(aw_val(defaults[k - 1L], "dbl"))
    v <- aw_gen(cx, m[[pn[k]]])
    if (v$type %in% c("null", "exit")) aw_unsupported("a parameter without a value", e)
    v
  })
  draw <- if (fn == "runif") "aw_r_runif" else "aw_r_rnorm"
  cx$rng <- TRUE
  nan <- cx_bail(cx, "a random draw that is NaN (R warns: NAs produced)", e)
  # A literal count of one with scalar parameters gives a scalar.
  if ((identical(m$n, 1) || identical(m$n, 1L)) && all(vapply(ps, function(p) p$kind == "s", logical(1)))) {
    t <- cx_tmp(cx)
    cx_emit(cx, sprintf("let %s: f64 = %s(%s, %s);", t, draw, cx_as(cx, ps[[1L]], "dbl")$g, cx_as(cx, ps[[2L]], "dbl")$g))
    cx_emit(cx, sprintf("if aw_isnan(%s) { %s }", t, nan))
    return(aw_val(t, "dbl"))
  }
  cnt <- if (nv$kind != "s") paste0(nv$g, ".len") else cx_count(cx, nv, e)
  for (p in ps) {
    if (p$kind != "s") cx_emit(cx, sprintf("if %s.len == 0 { %s }", p$g, cx_bail(cx, "an empty parameter vector (R warns)", e)))
  }
  t <- cx_tmp(cx)
  k <- cx_tmp(cx)
  cx_emit(cx, sprintf("var %s: f64[>..] = [];", t))
  cx_emit(cx, sprintf("%s.resize(%s, 0.0);", t, cnt))
  cx_open(cx, sprintf("for %s in 0..%s", k, cnt))
  args <- vapply(ps, function(p) {
    el <- if (p$kind == "s") p else aw_val(sprintf("%s[%s %% %s.len]", p$g, k, p$g), p$type)
    if (el$type == "dbl") return(el$g)
    x <- cx_tmp(cx)
    cx_emit(cx, sprintf("let %s: i32 = %s;", x, el$g))
    cx_as(cx, aw_val(x, el$type), "dbl")$g
  }, "")
  cx_emit(cx, sprintf("%s[%s] = %s(%s, %s);", t, k, draw, args[1L], args[2L]))
  cx_emit(cx, sprintf("if aw_isnan(%s[%s]) { %s }", t, k, nan))
  cx_close(cx)
  aw_val(t, "dbl", "v")
}
