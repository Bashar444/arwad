# ADR-0004: Numerical-equivalence gate

- **Status:** Accepted
- **Date:** 2026-10-24

## Context

Statisticians will adopt a new engine only if it gives the same answers as R. Speed claims without equivalence are worthless, and silent numerical drift would undermine published research.

## Decision

Every change that can affect a computed value must pass an equivalence check against GNU R before merging:

- default tolerance: relative error at most 1e-9 (absolute error at most 1e-12 when the reference is near zero); tighter where R's own algorithm is replicated exactly;
- random-number streams are bit-identical to GNU R's for the same seed and generator settings;
- reference suites include the NIST Statistical Reference Datasets for linear regression and the reference packages listed in [ROADMAP.md](../ROADMAP.md) Phase 2;
- errors and warnings must match GNU R in class and message where the tests compare them.

## Consequences

- Some optimisations (fast-math, reordered reductions) are excluded unless they keep results within tolerance.
- Each statistical engine carries its own equivalence suite, which doubles as documentation of correctness for users and reviewers.
