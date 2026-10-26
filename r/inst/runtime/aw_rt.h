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

static void aw_res_set(int type, const void *data, int64_t len, size_t size)
{
    free(aw_res_buf);
    aw_res_buf = NULL;
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

/* Called by the shim after the entry returns: hands over the result buffer. */
int aw_res_take(void **buf, int64_t *len)
{
    int t = aw_res_oom ? -1 : aw_res_type;
    *buf = aw_res_buf;
    *len = aw_res_len;
    aw_res_buf = NULL;
    aw_res_len = 0;
    aw_res_type = 0;
    aw_res_oom = 0;
    return t;
}
