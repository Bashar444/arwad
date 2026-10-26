/* arwad runtime for compiled units.
 *
 * Included into the C that Goose generates (goose --include aw_rt.h), after
 * Goose's own type declarations, so the slice types sl_f64 and sl_i32 are in
 * scope. The generated code returns its result through the aw_ret_* calls,
 * which copy it out of Goose memory; the unit's shim then hands it to R.
 * Nothing here calls into R except R_pow, R's own power function, so that
 * x ^ y gives exactly what GNU R gives.
 */
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <float.h>

double R_pow(double x, double y);

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
static double aw_rmean(sl_f64 x)
{
    long double s = 0.0;
    for (int64_t i = 0; i < x.len; i++) s += x.data[i];
    if (isfinite((double) s)) {
        s /= x.len;
    } else {
        long double t = 0.0;
        for (int64_t i = 0; i < x.len; i++) t += x.data[i] / x.len;
        s = t;
    }
    if (isfinite((double) s)) {
        long double t = 0.0;
        for (int64_t i = 0; i < x.len; i++) t += x.data[i] - s;
        s += t / x.len;
    }
    return (double) s;
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
