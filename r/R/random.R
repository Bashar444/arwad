# Random numbers: runif() and rnorm() draw from GNU R's own generators
# (Rf_runif and Rf_rnorm in R's C API, so unif_rand() and norm_rand() under
# whatever RNGkind() is set), between GetRNGstate() and PutRNGstate() in the
# unit's shim. The stream is therefore R's, bit for bit. When the native code
# bails out, the dispatcher restores .Random.seed before GNU R re-runs the
# call (ADR-0005).

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
