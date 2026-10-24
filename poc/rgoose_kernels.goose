// Phase 0.4 proof of concept: Goose kernels exported to C and called from R
// through .Call. R's own vector memory is passed in as slices (no copies);
// results are written into a matrix that R allocated.
//
// Build: see poc/build.sh

import std;
import math;

// Least squares by Householder QR for a full-rank design (as lm.fit does).
// a: n x k, column-major, overwritten; y: length n, overwritten.
fn ols_qr(a: f64[:], y: f64[:], n: i64, k: i64, rdiag: f64[:], beta: f64[:]) {
    for j in k {
        var norm2 = 0.0;
        for i in j..n { let v = a[j * n + i]; norm2 += v * v; }
        let norm = sqrt(norm2);
        let ajj = a[j * n + j];
        let alpha = if ajj > 0.0 { -norm } else { norm };
        a[j * n + j] = ajj - alpha;
        let vtv = 2.0 * norm * (norm + abs(ajj));
        for c in (j + 1)..k {
            var dot = 0.0;
            for i in j..n { dot += a[j * n + i] * a[c * n + i]; }
            let f = 2.0 * dot / vtv;
            for i in j..n { a[c * n + i] -= f * a[j * n + i]; }
        }
        var doty = 0.0;
        for i in j..n { doty += a[j * n + i] * y[i]; }
        let fy = 2.0 * doty / vtv;
        for i in j..n { y[i] -= fy * a[j * n + i]; }
        rdiag[j] = alpha;
    }
    var r = k - 1;
    while r >= 0 {
        var s = y[r];
        for c in (r + 1)..k { s -= a[c * n + r] * beta[c]; }
        beta[r] = s / rdiag[r];
        r -= 1;
    }
}

// One OLS fit. x: R matrix n x k (column-major), y: length n, beta: length k (output).
export "rg_ols" fn rg_ols(x: const f64[:], y: const f64[:], n: i64, k: i64, beta: f64[:]) {
    var a: f64[>..] = [];
    a.append(x);
    var yy: f64[>..] = [];
    yy.append(y);
    var rdiag: f64[>..] = [];
    rdiag.resize(k, 0.0);
    ols_qr(a, yy, n, k, rdiag, beta);
}

// Case bootstrap of OLS coefficients. idx: R integer matrix n x reps with
// 1-based row indices (validated by the caller); out: R matrix k x reps.
export "rg_boot_ols" fn rg_boot_ols(x: const f64[:], y: const f64[:], idx: const i32[:], n: i64, k: i64, reps: i64, out: f64[:]) {
    var rdiag: f64[>..] = [];
    rdiag.resize(k, 0.0);
    var bb: f64[>..] = [];
    bb.resize(k, 0.0);
    for b in reps {
        // Per-replicate scratch: released when the iteration ends.
        var ab: f64[>..] = [];
        ab.resize(n * k, 0.0);
        var yb: f64[>..] = [];
        yb.resize(n, 0.0);
        let base = b * n;
        for i in n {
            let src = (idx[base + i] as i64) - 1;
            yb[i] = y[src];
            for j in k { ab[j * n + i] = x[j * n + src]; }
        }
        ols_qr(ab, yb, n, k, rdiag, bb);
        for j in k { out[b * k + j] = bb[j]; }
    }
}
