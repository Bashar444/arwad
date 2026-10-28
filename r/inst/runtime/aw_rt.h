/* arwad runtime for compiled units.
 *
 * Included into the C that Goose generates (goose --include aw_rt.h), after
 * Goose's own type declarations, so the slice types sl_f64 and sl_i32 are in
 * scope. The generated code returns its result through the aw_ret_* calls,
 * which copy it out of Goose memory; the unit's shim then hands it to R.
 * Where R's own C routines give R's results (R_pow, the random number
 * generators, BLAS, LAPACK and LINPACK), the code below calls them, so that
 * the compiled operations return exactly what GNU R returns.
 */
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <float.h>

double R_pow(double x, double y);

/* x ^ y as R's arithmetic gives it: a square is x * x, any other power R_pow
 * (which can use long double powl and round a square differently). */
static double aw_pow(double x, double y) { return y == 2.0 ? x * x : R_pow(x, y); }
double Rf_runif(double a, double b);    /* R's runif() for one draw: unif_rand() */
double Rf_rnorm(double mu, double sigma); /* R's rnorm() for one draw: norm_rand() */
double R_unif_index(double dn);           /* R's index draw for sample(), by sample.kind */

static int aw_res_type = 0;   /* 0 none, 1 double, 2 integer, 3 logical, 4 NULL */
static void *aw_res_buf = NULL;
static int64_t aw_res_len = 0;
static int aw_res_oom = 0;
static int64_t aw_res_nr = -1, aw_res_nc = -1;   /* dimensions of a matrix result */

static void aw_res_set(int type, const void *data, int64_t len, size_t size)
{
    free(aw_res_buf);
    aw_res_buf = NULL;
    aw_res_nr = -1;
    aw_res_nc = -1;
    aw_res_type = type;
    aw_res_len = len;
    if (len > 0) {
        aw_res_buf = malloc((size_t) len * size);
        if (aw_res_buf == NULL) { aw_res_oom = 1; return; }
        memcpy(aw_res_buf, data, (size_t) len * size);
    }
}

static void aw_ret_dbl(sl_f64 x) { aw_res_set(1, x.data, x.len, sizeof(double)); }
static void aw_ret_int(sl_i32 x) { aw_res_set(2, x.data, x.len, sizeof(int32_t)); }
static void aw_ret_lgl(sl_i32 x) { aw_res_set(3, x.data, x.len, sizeof(int32_t)); }
static void aw_ret_dbl1(double x) { aw_res_set(1, &x, 1, sizeof(double)); }
static void aw_ret_int1(int32_t x) { aw_res_set(2, &x, 1, sizeof(int32_t)); }
static void aw_ret_lgl1(int32_t x) { aw_res_set(3, &x, 1, sizeof(int32_t)); }
static void aw_ret_null(void) { aw_res_set(4, NULL, 0, 1); }
static void aw_ret_dblm(sl_f64 x, int64_t nr, int64_t nc) { aw_ret_dbl(x); aw_res_nr = nr; aw_res_nc = nc; }
static void aw_ret_intm(sl_i32 x, int64_t nr, int64_t nc) { aw_ret_int(x); aw_res_nr = nr; aw_res_nc = nc; }
static void aw_ret_lglm(sl_i32 x, int64_t nr, int64_t nc) { aw_ret_lgl(x); aw_res_nr = nr; aw_res_nc = nc; }

/* sum() of doubles: one extended-precision accumulator, in order, as ?sum
 * documents; an accumulator beyond the double range gives +/-Inf. */
static double aw_rsum(sl_f64 x)
{
    long double s = 0.0;
    for (int64_t i = 0; i < x.len; i++) s += x.data[i];
    if (s > DBL_MAX) return INFINITY;
    if (s < -DBL_MAX) return -INFINITY;
    return (double) s;
}

/* R's NA_real_ is the NaN whose low 32 bits are 1954. */
static int aw_isna(double x)
{
    uint64_t u;
    memcpy(&u, &x, sizeof u);
    return isnan(x) && (uint32_t) (u & 0xFFFFFFFFu) == 1954u;
}

/* mean() of doubles: an extended-precision sum divided by n; when the sum is
 * not finite (it may only have overflowed), the sum of the terms x[i] / n
 * instead; then, when finite, a second pass adding the mean of the residuals.
 * Verified against GNU R on x86-64 and arm64, including NA and NaN data. */
static double aw_rmean_p(const double *x, int64_t n)
{
    long double s = 0.0;
    for (int64_t i = 0; i < n; i++) s += x[i];
    if (isfinite((double) s)) {
        s /= n;
    } else {
        long double t = 0.0;
        for (int64_t i = 0; i < n; i++) t += x[i] / n;
        s = t;
    }
    if (isfinite((double) s)) {
        long double t = 0.0;
        for (int64_t i = 0; i < n; i++) t += x[i] - s;
        s += t / n;
    }
    return (double) s;
}

static double aw_rmean(sl_f64 x) { return aw_rmean_p(x.data, x.len); }

/* colMeans() of a double matrix: per column, an extended-precision sum
 * divided by the number of rows before rounding. Non-finite data return 1
 * (left to GNU R, which also keeps track of NA versus NaN). */
static int32_t aw_colmeans(sl_f64 x, int64_t nr, int64_t nc, sl_f64 z)
{
    for (int64_t j = 0; j < nc; j++) {
        const double *c = x.data + j * nr;
        long double s = 0.0;
        for (int64_t i = 0; i < nr; i++) {
            if (!isfinite(c[i])) return 1;
            s += c[i];
        }
        z.data[j] = (double) (s / nr);
    }
    return 0;
}

/* cov(x, y) (cor = 0) and cor(x, y) (cor = 1) of two double vectors, as GNU
 * R computes them for vectors and for two matrices: the corrected two-pass
 * mean (Chan, Golub and LeVeque, 1983), then the cross-products of the
 * deviations summed in extended precision and divided by n - 1 before
 * rounding; a correlation divides that covariance by the two standard
 * deviations, each the extended-precision square root of its variance,
 * and is clamped to [-1, 1]. Verified by black-box comparison with GNU R.
 * Returns NaN where R gives NA, warns or errors (lengths differ, n < 2,
 * non-finite data, a zero standard deviation): those calls go to R. */
/* On 64-bit ARM, GNU R's own cov() and cor() round their sums of products
 * as its C compiler vectorises and fuses those loops, which a separate build
 * cannot be relied on to repeat; there the compiled code calls the routine
 * R itself calls, .Call(stats:::C_cov or C_cor, x, y, 4L, FALSE), so the
 * result is R's by construction. R's headers are not included here (their
 * Boolean type clashes with macOS headers), so the few entry points are
 * declared directly. */
#if defined(__aarch64__) || defined(__arm64__)
#define AW_R_COV 1
typedef struct SEXPREC *aw_sexp;
extern aw_sexp R_BaseEnv;
extern aw_sexp Rf_eval(aw_sexp e, aw_sexp env);
extern aw_sexp Rf_install(char const *name);
extern aw_sexp Rf_lang3(aw_sexp a, aw_sexp b, aw_sexp c);
extern aw_sexp Rf_lang6(aw_sexp a, aw_sexp b, aw_sexp c, aw_sexp d, aw_sexp e, aw_sexp f);
extern void R_PreserveObject(aw_sexp s);
extern aw_sexp Rf_allocVector(unsigned int type, ptrdiff_t length);
extern aw_sexp Rf_allocMatrix(unsigned int type, int nrow, int ncol);
extern aw_sexp Rf_protect(aw_sexp s);
extern void Rf_unprotect(int n);
extern aw_sexp Rf_ScalarInteger(int x);
extern aw_sexp Rf_ScalarLogical(int x);
extern double *REAL(aw_sexp x);

static aw_sexp aw_stats_routine(char const *name)
{
    aw_sexp e = Rf_protect(Rf_lang3(Rf_install(":::"), Rf_install("stats"), Rf_install(name)));
    aw_sexp f = Rf_eval(e, R_BaseEnv);
    R_PreserveObject(f);
    Rf_unprotect(1);
    return f;
}

static double aw_cov2_r(sl_f64 x, sl_f64 y, int32_t cor)
{
    static aw_sexp fcov = NULL, fcor = NULL;
    if (fcov == NULL) {
        fcov = aw_stats_routine("C_cov");
        fcor = aw_stats_routine("C_cor");
    }
    aw_sexp xs = Rf_protect(Rf_allocVector(14u, (ptrdiff_t) x.len));
    aw_sexp ys = Rf_protect(Rf_allocVector(14u, (ptrdiff_t) y.len));
    memcpy(REAL(xs), x.data, (size_t) x.len * sizeof(double));
    memcpy(REAL(ys), y.data, (size_t) y.len * sizeof(double));
    aw_sexp na = Rf_protect(Rf_ScalarInteger(4)); /* use = "everything" */
    aw_sexp kd = Rf_protect(Rf_ScalarLogical(0));
    aw_sexp call = Rf_protect(Rf_lang6(Rf_install(".Call"), cor ? fcor : fcov, xs, ys, na, kd));
    double r = REAL(Rf_eval(call, R_BaseEnv))[0];
    Rf_unprotect(5);
    return r;
}

static void aw_covmat_r(const double *x, int64_t n, int64_t ncx, const double *y, int64_t ncy, int32_t cor, double *z)
{
    static aw_sexp fcov = NULL, fcor = NULL;
    if (fcov == NULL) {
        fcov = aw_stats_routine("C_cov");
        fcor = aw_stats_routine("C_cor");
    }
    aw_sexp xs = Rf_protect(Rf_allocMatrix(14u, (int) n, (int) ncx));
    aw_sexp ys = Rf_protect(Rf_allocMatrix(14u, (int) n, (int) ncy));
    memcpy(REAL(xs), x, (size_t) (n * ncx) * sizeof(double));
    memcpy(REAL(ys), y, (size_t) (n * ncy) * sizeof(double));
    aw_sexp na = Rf_protect(Rf_ScalarInteger(4)); /* use = "everything" */
    aw_sexp kd = Rf_protect(Rf_ScalarLogical(0));
    aw_sexp call = Rf_protect(Rf_lang6(Rf_install(".Call"), cor ? fcor : fcov, xs, ys, na, kd));
    memcpy(z, REAL(Rf_eval(call, R_BaseEnv)), (size_t) (ncx * ncy) * sizeof(double));
    Rf_unprotect(5);
}

extern aw_sexp R_NilValue;

/* cov(X) and cor(X) with one argument: .Call(C_cov or C_cor, x, NULL, ...). */
static void aw_covmat1_r(const double *x, int64_t n, int64_t nc, int32_t cor, double *z)
{
    static aw_sexp fcov = NULL, fcor = NULL;
    if (fcov == NULL) {
        fcov = aw_stats_routine("C_cov");
        fcor = aw_stats_routine("C_cor");
    }
    aw_sexp xs = Rf_protect(Rf_allocMatrix(14u, (int) n, (int) nc));
    memcpy(REAL(xs), x, (size_t) (n * nc) * sizeof(double));
    aw_sexp na = Rf_protect(Rf_ScalarInteger(4)); /* use = "everything" */
    aw_sexp kd = Rf_protect(Rf_ScalarLogical(0));
    aw_sexp call = Rf_protect(Rf_lang6(Rf_install(".Call"), cor ? fcor : fcov, xs, R_NilValue, na, kd));
    memcpy(z, REAL(Rf_eval(call, R_BaseEnv)), (size_t) (nc * nc) * sizeof(double));
    Rf_unprotect(4);
}
#endif

static double aw_cov2(sl_f64 x, sl_f64 y, int32_t cor)
{
    int64_t n = x.len;
    if (n != y.len || n < 2) return NAN;
    for (int64_t i = 0; i < n; i++)
        if (!isfinite(x.data[i]) || !isfinite(y.data[i])) return NAN;
#ifdef AW_R_COV
    if (cor) {
        /* R warns for a zero standard deviation: leave such calls to R. */
        int64_t i = 1, j = 1;
        while (i < n && x.data[i] == x.data[0]) i++;
        while (j < n && y.data[j] == y.data[0]) j++;
        if (i == n || j == n) return NAN;
    }
    return aw_cov2_r(x, y, cor);
#endif
    long double mx = aw_rmean(x), my = aw_rmean(y), sxy = 0.0;
    for (int64_t i = 0; i < n; i++) sxy += (x.data[i] - mx) * (y.data[i] - my);
    double c = (double) (sxy / (n - 1));
    if (!cor) return c;
    long double sxx = 0.0, syy = 0.0;
    for (int64_t i = 0; i < n; i++) sxx += (x.data[i] - mx) * (x.data[i] - mx);
    for (int64_t i = 0; i < n; i++) syy += (y.data[i] - my) * (y.data[i] - my);
    double sx = (double) sqrtl(sxx / (n - 1)), sy = (double) sqrtl(syy / (n - 1));
    if (sx == 0.0 || sy == 0.0) return NAN;
    double r = c / (sx * sy);
    if (r > 1.0) r = 1.0;
    if (r < -1.0) r = -1.0;
    return r;
}

/* Whether some column of an n by nc matrix is constant (zero variance). */
static int aw_const_col(const double *x, int64_t n, int64_t nc)
{
    for (int64_t j = 0; j < nc; j++) {
        const double *c = x + j * n;
        int64_t i = 1;
        while (i < n && c[i] == c[0]) i++;
        if (i == n) return 1;
    }
    return 0;
}

/* cov() and cor() of single matrix columns, x[, j], from statistics the
 * compiled code keeps per column until the matrix is written again (the
 * mean, and for cor() the standard deviation, are then computed once rather
 * than at every call). aw_colmean() is the mean aw_cov2() uses, NaN when the
 * column has a non-finite value (R gives NA there, so the caller bails);
 * aw_colsd() the standard deviation aw_cov2() uses; aw_cov2col() the value
 * aw_cov2() returns for the two columns, NaN where it returns NaN. A vector
 * is a matrix with one column. On 64-bit ARM the value comes from R's own
 * routine, as aw_cov2() does there. */
static double aw_colmean(sl_f64 x, int64_t nr, int64_t j)
{
    const double *c = x.data + (j - 1) * nr;
    for (int64_t i = 0; i < nr; i++)
        if (!isfinite(c[i])) return NAN;
    return aw_rmean_p(c, nr);
}

static double aw_colsd(sl_f64 x, int64_t nr, int64_t j, double m)
{
    const double *c = x.data + (j - 1) * nr;
    long double mc = m, ss = 0.0;
    for (int64_t k = 0; k < nr; k++) ss += (c[k] - mc) * (c[k] - mc);
    return (double) sqrtl(ss / (nr - 1));
}

static double aw_cov2col(sl_f64 x, int64_t nx, int64_t jx, double mx, double sx,
                         sl_f64 y, int64_t ny, int64_t jy, double my, double sy, int32_t cor)
{
    if (nx != ny || nx < 2 || isnan(mx) || isnan(my)) return NAN;
    const double *a = x.data + (jx - 1) * nx, *b = y.data + (jy - 1) * ny;
#ifdef AW_R_COV
    if (cor && (aw_const_col(a, nx, 1) || aw_const_col(b, ny, 1))) return NAN;
    sl_f64 xs = x, ys = y;
    xs.data = (double *) a;
    xs.len = nx;
    ys.data = (double *) b;
    ys.len = ny;
    return aw_cov2_r(xs, ys, cor);
#endif
    long double ax = mx, ay = my, s = 0.0;
    for (int64_t k = 0; k < nx; k++) s += (a[k] - ax) * (b[k] - ay);
    double c = (double) (s / (nx - 1));
    if (!cor) return c;
    if (sx == 0.0 || sy == 0.0) return NAN;
    double r = c / (sx * sy);
    if (r > 1.0) r = 1.0;
    if (r < -1.0) r = -1.0;
    return r;
}

/* cov(X, Y) and cor(X, Y) of two matrices (a vector counts as one column),
 * as GNU R computes them with two arguments: entry (i, j) is exactly the
 * value of cov() or cor() of column i of X and column j of Y, the rule
 * aw_cov2() implements, but each column's mean and standard deviation is
 * computed once. cor(X, X) computes one triangle and mirrors it, which is
 * exact: both entries add the same products in the same order. Returns 1
 * where R gives NA, warns or errors (rows differ, fewer than two, non-finite
 * data, a zero standard deviation): those calls go to R. */
static int32_t aw_covmat(sl_f64 x, int64_t n, int64_t ncx, sl_f64 y, int64_t ny, int64_t ncy, int32_t cor, sl_f64 z)
{
    if (n != ny || n < 2 || ncx < 1 || ncy < 1) return 1;
    for (int64_t i = 0; i < n * ncx; i++) if (!isfinite(x.data[i])) return 1;
    for (int64_t i = 0; i < n * ncy; i++) if (!isfinite(y.data[i])) return 1;
#ifdef AW_R_COV
    if (cor && (aw_const_col(x.data, n, ncx) || aw_const_col(y.data, n, ncy))) return 1;
    aw_covmat_r(x.data, n, ncx, y.data, ncy, cor, z.data);
    return 0;
#endif
    int same = x.data == y.data && ncx == ncy;
    double *m = malloc((size_t) (2 * (ncx + ncy)) * sizeof(double));
    if (m == NULL) return 1;
    double *mx = m, *my = m + ncx, *sx = m + ncx + ncy, *sy = sx + ncx;
    for (int64_t i = 0; i < ncx; i++) mx[i] = aw_rmean_p(x.data + i * n, n);
    for (int64_t j = 0; j < ncy; j++) my[j] = same ? mx[j] : aw_rmean_p(y.data + j * n, n);
    if (cor) {
        for (int64_t i = 0; i < ncx + ncy; i++) {
            if (same && i >= ncx) {
                sx[i] = sx[i - ncx];
                continue;
            }
            const double *c = i < ncx ? x.data + i * n : y.data + (i - ncx) * n;
            long double mc = i < ncx ? mx[i] : my[i - ncx], ss = 0.0;
            for (int64_t k = 0; k < n; k++) ss += (c[k] - mc) * (c[k] - mc);
            sx[i] = (double) sqrtl(ss / (n - 1));
            if (sx[i] == 0.0) {
                free(m);
                return 1;
            }
        }
    }
    for (int64_t j = 0; j < ncy; j++) {
        const double *cy = y.data + j * n;
        for (int64_t i = 0; i < ncx; i++) {
            if (same && i > j) continue;
            const double *cx = x.data + i * n;
            long double ax = mx[i], ay = my[j], s = 0.0;
            for (int64_t k = 0; k < n; k++) s += (cx[k] - ax) * (cy[k] - ay);
            double c = (double) (s / (n - 1));
            if (cor) {
                c = c / (sx[i] * sy[j]);
                if (c > 1.0) c = 1.0;
                if (c < -1.0) c = -1.0;
            }
            z.data[i + j * ncx] = c;
        }
    }
    if (same)
        for (int64_t j = 0; j < ncy; j++)
            for (int64_t i = j + 1; i < ncx; i++) z.data[i + j * ncx] = z.data[j + i * ncx];
    free(m);
    return 0;
}

/* cov(X) and cor(X) of one matrix. cov(X) is cov(X, X) bit for bit. cor(X)
 * rounds differently from cor(X, X): GNU R gives the covariance matrix
 * divided by the product of the double square roots of its two diagonal
 * entries, with the diagonal exactly 1 and the rest clamped to [-1, 1]
 * (3,000 of 3,000 random matrices identical in a black-box comparison).
 * Returns 1 where R gives NA, warns or errors, as aw_covmat() does. */
static int32_t aw_covmat1(sl_f64 x, int64_t n, int64_t nc, int32_t cor, sl_f64 z)
{
    if (n < 2 || nc < 1) return 1;
    for (int64_t i = 0; i < n * nc; i++) if (!isfinite(x.data[i])) return 1;
#ifdef AW_R_COV
    if (cor && aw_const_col(x.data, n, nc)) return 1;
    aw_covmat1_r(x.data, n, nc, cor, z.data);
    return 0;
#endif
    if (aw_covmat(x, n, nc, x, n, nc, 0, z) != 0) return 1;
    if (!cor) return 0;
    double *s = malloc((size_t) nc * sizeof(double));
    if (s == NULL) return 1;
    for (int64_t i = 0; i < nc; i++) {
        s[i] = sqrt(z.data[i + i * nc]);
        if (s[i] == 0.0) {
            free(s);
            return 1;
        }
    }
    for (int64_t j = 0; j < nc; j++)
        for (int64_t i = 0; i < nc; i++) {
            double r = i == j ? 1.0 : z.data[i + j * nc] / (s[i] * s[j]);
            if (r > 1.0) r = 1.0;
            if (r < -1.0) r = -1.0;
            z.data[i + j * nc] = r;
        }
    free(s);
    return 0;
}

/* mean() of integers or logicals: NA if any element is NA. */
static double aw_imean(sl_i32 x, double na)
{
    long double s = 0.0;
    for (int64_t i = 0; i < x.len; i++) {
        if (x.data[i] == INT32_MIN) return na;
        s += x.data[i];
    }
    return (double) (s / x.len);
}

/* x + y and x * y with GNU R's NA or NaN, whichever operand order the C
 * compiler picks for these commutative operations. When an operand is NaN,
 * the result is the NaN the hardware returns for R's order (x, y): on arm64
 * a signalling NaN (R stores NA_real_ as one) takes priority, otherwise the
 * first NaN wins; it is quieted by setting the quiet bit, as the hardware
 * does, which no optimiser can remove. */
static double aw_quiet(double x)
{
    uint64_t u;
    memcpy(&u, &x, sizeof u);
    u |= UINT64_C(0x0008000000000000);
    memcpy(&x, &u, sizeof u);
    return x;
}

static double aw_nan_of(double x, double y)
{
#if defined(__aarch64__) || defined(_M_ARM64)
    uint64_t ux, uy;
    memcpy(&ux, &x, sizeof ux);
    memcpy(&uy, &y, sizeof uy);
    if (isnan(x) && !(ux & UINT64_C(0x0008000000000000))) return aw_quiet(x);
    if (isnan(y) && !(uy & UINT64_C(0x0008000000000000))) return aw_quiet(y);
#endif
    return aw_quiet(isnan(x) ? x : y);
}

static double aw_dadd(double x, double y)
{
    double r = x + y;
    return (isnan(x) || isnan(y)) ? aw_nan_of(x, y) : r;
}

static double aw_dmul(double x, double y)
{
    double r = x * y;
    return (isnan(x) || isnan(y)) ? aw_nan_of(x, y) : r;
}

/* min() and max() of doubles (?Extremes): NA wins over NaN, NaN over
 * numbers, and of equal values (such as 0 and -0) the first is kept. */
static double aw_rextreme(sl_f64 x, int32_t want_max)
{
    double s = 0.0;
    int seen = 0;
    for (int64_t i = 0; i < x.len; i++) {
        double v = x.data[i];
        if (isnan(v)) {
            if (!aw_isna(s)) s = v;
            seen = 1;
        } else if (!seen || (want_max ? v > s : v < s)) {
            s = v;
            seen = 1;
        }
    }
    return s;
}

/* ---- Matrix products and solve() through R's own BLAS and LAPACK ---------- */
#define USE_FC_LEN_T
#include <Rconfig.h>
#include <R_ext/RS.h>
#include <R_ext/BLAS.h>
#include <R_ext/Lapack.h>
#ifndef FCONE
# define FCONE
#endif

/* R's default matrix product hands operands with NA, NaN, infinite values (or
 * values whose sums overflow) to its own non-BLAS code; such calls are left
 * to GNU R. The test here is wider than R's, which only costs a re-run. */
static int aw_unusual(sl_f64 x)
{
    for (int64_t i = 0; i < x.len; i++) if (!(fabs(x.data[i]) <= 1e307)) return 1;
    return 0;
}

static void aw_zero_fill(sl_f64 z) { for (int64_t i = 0; i < z.len; i++) z.data[i] = 0.0; }

/* x (nrx by ncx) %*% y (nry by ncy) into z: dgemv for a matrix-vector or a
 * vector-matrix product, dgemm otherwise. Returns 1 to leave the call to R. */
static int32_t aw_matprod(sl_f64 x, int64_t nrx, int64_t ncx, sl_f64 y, int64_t nry, int64_t ncy, sl_f64 z)
{
    if (nrx == 0 || ncx == 0 || nry == 0 || ncy == 0) { aw_zero_fill(z); return 0; }
    if (aw_unusual(x) || aw_unusual(y)) return 1;
    int m = (int) nrx, k = (int) ncx, ry = (int) nry, n = (int) ncy, one_i = 1;
    double one = 1.0, zero = 0.0;
    if (ncy == 1)
        F77_CALL(dgemv)("N", &m, &k, &one, x.data, &m, y.data, &one_i, &zero, z.data, &one_i FCONE);
    else if (nrx == 1)
        F77_CALL(dgemv)("T", &ry, &n, &one, y.data, &ry, x.data, &one_i, &zero, z.data, &one_i FCONE);
    else
        F77_CALL(dgemm)("N", "N", &m, &n, &k, &one, x.data, &m, y.data, &ry, &zero, z.data, &m FCONE FCONE);
    return 0;
}

/* crossprod(x) (nc by nc): dsyrk on the upper triangle, mirrored. */
static int32_t aw_crossprod1(sl_f64 x, int64_t nr, int64_t nc, sl_f64 z)
{
    if (nr == 0 || nc == 0) { aw_zero_fill(z); return 0; }
    if (aw_unusual(x)) return 1;
    int r = (int) nr, c = (int) nc;
    double one = 1.0, zero = 0.0;
    F77_CALL(dsyrk)("U", "T", &c, &r, &one, x.data, &r, &zero, z.data, &c FCONE FCONE);
    for (int i = 1; i < c; i++)
        for (int j = 0; j < i; j++) z.data[i + (int64_t) c * j] = z.data[j + (int64_t) c * i];
    return 0;
}

/* crossprod(x, y) = t(x) %*% y: dgemv when either side is a single column
 * (as R chooses; the routines round differently with optimised BLAS), dgemm
 * otherwise. */
static int32_t aw_crossprod2(sl_f64 x, int64_t nrx, int64_t ncx, sl_f64 y, int64_t nry, int64_t ncy, sl_f64 z)
{
    if (nrx == 0 || ncx == 0 || nry == 0 || ncy == 0) { aw_zero_fill(z); return 0; }
    if (aw_unusual(x) || aw_unusual(y)) return 1;
    int rx = (int) nrx, cx = (int) ncx, ry = (int) nry, cy = (int) ncy, one_i = 1;
    double one = 1.0, zero = 0.0;
    if (ncy == 1)
        F77_CALL(dgemv)("T", &rx, &cx, &one, x.data, &rx, y.data, &one_i, &zero, z.data, &one_i FCONE);
    else if (ncx == 1)
        F77_CALL(dgemv)("T", &ry, &cy, &one, y.data, &ry, x.data, &one_i, &zero, z.data, &one_i FCONE);
    else
        F77_CALL(dgemm)("T", "N", &cx, &cy, &rx, &one, x.data, &rx, y.data, &ry, &zero, z.data, &cx FCONE FCONE);
    return 0;
}

/* solve(a, b) for an n by n double matrix a: b (n by p) is overwritten with
 * the solution by dgesv; the reciprocal condition number from dgecon must
 * reach R's default tolerance, .Machine$double.eps. Returns 1 when GNU R
 * would signal an error (singular or computationally singular). */
static int32_t aw_solve(sl_f64 a, int64_t n, sl_f64 b, int64_t p)
{
    int nn = (int) n, pp = (int) p, info = 0;
    double *lu = malloc((size_t) (n * n) * sizeof(double));
    int *ipiv = malloc((size_t) n * sizeof(int));
    double *work = malloc((size_t) (4 * n) * sizeof(double));
    int32_t bad = (lu == NULL || ipiv == NULL || work == NULL);
    if (!bad) {
        memcpy(lu, a.data, (size_t) (n * n) * sizeof(double));
        F77_CALL(dgesv)(&nn, &pp, lu, &nn, ipiv, b.data, &nn, &info);
        if (info != 0) {
            bad = 1;
        } else {
            double anorm = F77_CALL(dlange)("1", &nn, &nn, a.data, &nn, (double *) NULL FCONE), rcond = 0.0;
            F77_CALL(dgecon)("1", &nn, lu, &nn, &anorm, &rcond, work, ipiv, &info FCONE);
            if (rcond < DBL_EPSILON) bad = 1;
        }
    }
    free(lu);
    free(ipiv);
    free(work);
    return bad;
}

/* .lm.fit(x, y, tol): R's own LINPACK least squares (dqrls, Householder QR
 * with limited pivoting), as lm() and glm() use it. Fills coef (p), resid (n)
 * and pivot (p) as .lm.fit() returns them, pivoted when the design is rank
 * deficient, and returns the rank; -1 leaves the call to GNU R, for data or a
 * tolerance R rejects (non-finite values).
 * The prototype is R's (R_ext/Applic.h). The header itself is not included:
 * its Rboolean enum clashes with a macOS system header that Goose's
 * standalone runtime includes. */
void F77_NAME(dqrls)(double *x, int *n, int *p, double *y, int *ny, double *tol, double *b, double *rsd,
                     double *qty, int *k, int *jpvt, double *qraux, double *work);

static int32_t aw_lmfit(sl_f64 x, int64_t n, int64_t p, sl_f64 y, double tol, sl_f64 coef, sl_f64 resid,
                        sl_i32 pivot)
{
    if (n <= 0 || p <= 0 || !(tol >= 0.0) || !isfinite(tol)) return -1;
    for (int64_t i = 0; i < x.len; i++) if (!isfinite(x.data[i])) return -1;
    for (int64_t i = 0; i < y.len; i++) if (!isfinite(y.data[i])) return -1;
    int nn = (int) n, pp = (int) p, ny = 1, rank = 0;
    double *qr = malloc((size_t) (n * p) * sizeof(double));
    double *yy = malloc((size_t) n * sizeof(double));
    double *eff = malloc((size_t) n * sizeof(double));
    double *qraux = malloc((size_t) p * sizeof(double));
    double *work = malloc((size_t) (2 * p) * sizeof(double));
    int32_t out = -1;
    if (qr != NULL && yy != NULL && eff != NULL && qraux != NULL && work != NULL) {
        memcpy(qr, x.data, (size_t) (n * p) * sizeof(double));
        memcpy(yy, y.data, (size_t) n * sizeof(double));
        memcpy(resid.data, y.data, (size_t) n * sizeof(double));
        memcpy(eff, y.data, (size_t) n * sizeof(double));
        for (int i = 0; i < pp; i++) pivot.data[i] = i + 1;
        F77_CALL(dqrls)(qr, &nn, &pp, yy, &ny, &tol, coef.data, resid.data, eff, &rank, pivot.data, qraux, work);
        out = rank;
    }
    free(qr); free(yy); free(eff); free(qraux); free(work);
    return out;
}

/* Called by the shim after the entry returns: hands over the result buffer. */
int aw_res_take(void **buf, int64_t *len, int64_t *nr, int64_t *nc)
{
    int t = aw_res_oom ? -1 : aw_res_type;
    *buf = aw_res_buf;
    *len = aw_res_len;
    *nr = aw_res_nr;
    *nc = aw_res_nc;
    aw_res_buf = NULL;
    aw_res_len = 0;
    aw_res_type = 0;
    aw_res_oom = 0;
    return t;
}
