/* R <-> Goose bridge for the Phase 0.4 proof of concept.
 *
 * R's vectors are handed to the exported Goose functions as slices that point
 * at R's own memory (no copies). Outputs are allocated by R and filled in by
 * Goose. Inputs are validated here first, because a failed bounds check inside
 * Goose aborts the process, and that must never take R down with it.
 */
#include <stdint.h>
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include "arwad_kernels.h"

static int aw_ready = 0;

static void aw_ensure_init(void)
{
    if (!aw_ready) {
        static char arg0[] = "R";
        static char *argv[] = {arg0, NULL};
        goose_init(1, argv);
        aw_ready = 1;
    }
}

static sl_f64 as_f64(SEXP x) { sl_f64 s = {REAL(x), (int64_t) XLENGTH(x)}; return s; }
static sl_i32 as_i32(SEXP x) { sl_i32 s = {INTEGER(x), (int64_t) XLENGTH(x)}; return s; }

static void check_design(SEXP X, SEXP y)
{
    if (!isReal(X) || !isMatrix(X)) error("X must be a double matrix");
    if (!isReal(y)) error("y must be a double vector");
    if (XLENGTH(y) != nrows(X)) error("length(y) must equal nrow(X)");
    if (ncols(X) < 1 || nrows(X) <= ncols(X)) error("X must have more rows than columns");
}

/* .Call("aw_ols_call", X, y) -> coefficient vector */
SEXP aw_ols_call(SEXP X, SEXP y)
{
    check_design(X, y);
    int64_t n = nrows(X), k = ncols(X);
    aw_ensure_init();
    SEXP beta = PROTECT(allocVector(REALSXP, (R_xlen_t) k));
    aw_ols(as_f64(X), as_f64(y), n, k, as_f64(beta));
    UNPROTECT(1);
    return beta;
}

/* .Call("aw_boot_ols_call", X, y, idx) -> k x B matrix of bootstrap coefficients.
 * idx: integer matrix n x B of 1-based row indices. */
SEXP aw_boot_ols_call(SEXP X, SEXP y, SEXP idx)
{
    check_design(X, y);
    if (!isInteger(idx) || !isMatrix(idx)) error("idx must be an integer matrix");
    int64_t n = nrows(X), k = ncols(X), reps = ncols(idx);
    if (nrows(idx) != n) error("nrow(idx) must equal nrow(X)");
    const int *ip = INTEGER(idx);
    R_xlen_t total = XLENGTH(idx);
    for (R_xlen_t t = 0; t < total; t++)
        if (ip[t] == NA_INTEGER || ip[t] < 1 || ip[t] > n) error("idx contains an out-of-range index");
    aw_ensure_init();
    SEXP out = PROTECT(allocMatrix(REALSXP, (int) k, (int) reps));
    aw_boot_ols(as_f64(X), as_f64(y), as_i32(idx), n, k, reps, as_f64(out));
    UNPROTECT(1);
    return out;
}

static const R_CallMethodDef call_methods[] = {
    {"aw_ols_call", (DL_FUNC) &aw_ols_call, 2},
    {"aw_boot_ols_call", (DL_FUNC) &aw_boot_ols_call, 3},
    {NULL, NULL, 0}
};

void R_init_arwadpoc(DllInfo *dll)
{
    R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
}
