// Phase 0 spike: OLS by Householder QR and a nonparametric case bootstrap,
// written by hand in Goose to test its memory model on a statistical workload.
//
// Run from the repository root:
//   goose run bench/phase0/ols_bootstrap.goose -- bench/phase0/data.csv 10000
//
// Reads the same data.csv as phase0_reference.R and draws the same resampling
// indices (Park-Miller minimal-standard LCG), so results can be compared with R.

import std;
import math;
import os;
import csv;

let P = 9;                  // predictors in data.csv
let K = 10;                 // coefficients, including the intercept
let SEED: i64 = 20261024;
let MODULUS: i64 = 2147483647;

// Least squares by Householder QR for a full-rank design, the method lm.fit uses.
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

fn main() {
    var path: u8[>..] = [];
    if arg_count() > 1 { arg(1, path); } else { path.append("bench/phase0/data.csv"); }
    var reps: i64 = 10000;
    if arg_count() > 2 {
        var text_b: u8[>..] = [];
        arg(2, text_b);
        let v, ok = parse_int(text_b);
        if ok { reps = v; }
    }

    var text: u8[>..] = [];
    guard read_file(path, text) else { print("cannot read ", path); exit(1); }

    // Parse: P predictors and y per row, after the header.
    var xs: f64[>..] = [];
    var ys: f64[>..] = [];
    var row = 0;
    var bad = 0;
    let parsed = csv::each_record(text) { fields =>
        if row > 0 && fields.len == P + 1 {
            for j in P {
                let v, ok = parse_flt(fields[j]);
                if !ok { bad++; }
                xs.push(v);
            }
            let v, ok = parse_flt(fields[P]);
            if !ok { bad++; }
            ys.push(v);
        }
        row++;
    };
    guard parsed && bad == 0 else { print("malformed CSV"); exit(1); }
    let n = ys.len;

    // Design matrix with intercept, column-major.
    var x: f64[>..] = [];
    x.resize(n * K, 0.0);
    for i in n {
        x[i] = 1.0;
        for j in P { x[(j + 1) * n + i] = xs[i * P + j]; }
    }

    var rdiag: f64[>..] = [];
    rdiag.resize(K, 0.0);
    var beta: f64[>..] = [];
    beta.resize(K, 0.0);
    var a: f64[>..] = [];
    a.append(x);
    var yy: f64[>..] = [];
    yy.append(ys);
    ols_qr(a, yy, n, K, rdiag, beta);

    // Resampling indices, generated before the bootstrap timing (as in the R
    // reference); this scalar loop is timed on its own.
    var idx: i32[>..] = [];
    var s = SEED;
    var checksum: i64 = 0;
    let ti0 = clock();
    for t in reps * n {
        s = (16807 * s) % MODULUS;
        let ii = s % n;
        idx.push(ii as i32);
        checksum += ii + 1;
    }
    let ti1 = clock();

    // Bootstrap: per-replicate scratch lives in the loop body and is released
    // at the end of each iteration.
    var coefs: f64[>..] = [];
    coefs.resize(reps * K, 0.0);
    var bb: f64[>..] = [];
    bb.resize(K, 0.0);
    let t0 = clock();
    for b in reps {
        var ab: f64[>..] = [];
        ab.resize(n * K, 0.0);
        var yb: f64[>..] = [];
        yb.resize(n, 0.0);
        let base = b * n;
        for i in n {
            let src = idx[base + i] as i64;
            yb[i] = ys[src];
            for j in K { ab[j * n + i] = x[j * n + src]; }
        }
        ols_qr(ab, yb, n, K, rdiag, bb);
        for j in K { coefs[b * K + j] = bb[j]; }
    }
    let t1 = clock();

    print("n ", n, " B ", reps, " checksum ", checksum);
    for j in K {
        var m = 0.0;
        for b in reps { m += coefs[b * K + j]; }
        m = m / reps;
        var ss = 0.0;
        for b in reps { let d = coefs[b * K + j] - m; ss += d * d; }
        let sd = sqrt(ss / (reps - 1));
        print("coef ", j, " ", beta[j], " ", m, " ", sd);
    }
    print("index_seconds ", ti1 - ti0);
    print("bootstrap_seconds ", t1 - t0);
}
