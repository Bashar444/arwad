# ADR-0005: Guarded native execution, with GNU R as the fallback

- **Status:** Accepted
- **Date:** 2026-10-26

## Context

The static tier must give GNU R's answers ([ADR-0004](0004-numerical-equivalence-gate.md)), including R's errors and warnings and their messages. Re-implementing every edge of R's semantics in generated code (zero and negative indices, `NA` conditions, the exact warning text and count for integer overflow, fractional loop bounds) would make the generated code large and each edge a new source of divergence. Phase 1 needed a rule for these cases before the first compiler slice.

## Decision

1. **Compiled functions are pure.** The subset ([spec/subset-v0.md](../../spec/subset-v0.md)) excludes every construct with an effect outside the call: superassignment, output, environments, random numbers (until R's generators are reproduced bit for bit), and changes to arguments (R's copy-on-modify is kept by copying an argument the body changes).
2. **The native path models the common case and guards the rest.** Generated code checks, at the point of use, every condition under which GNU R would signal an error or a warning or produce a different shape: an `NA` condition, integer overflow, `sqrt()` or `log()` producing `NaN`, a zero, negative or `NA` index where R would not return `NA`, a non-integer loop bound, `%%` on doubles that are not whole numbers below 2^52. When a guard fails the native code returns a bailout code.
3. **A bailout re-runs the whole call in GNU R.** Because the function is pure, running it again from the start is equivalent to running it once in R, so the caller sees exactly R's value, errors and warnings. Each bailout is counted by reason and shown by `aw_explain()`.
4. **Specialisation per argument signature.** A compiled function is built on its first call for each combination of argument types (double, integer, logical) and kinds (scalar, vector); arguments with attributes or other types run in GNU R. Native units are cached on disk by a content hash.
5. **One type per variable in slice 1.** A variable that would change type (an integer accumulator receiving a double) makes that signature run in GNU R, with the reason recorded. Flow-sensitive typing can lift this later.
6. **The front end walks R's language objects** (`body(f)`), which are the output of R's own parser; `getParseData()` is not needed for code generation.
7. **The R package lives in `r/`** of this repository, beside the specification and the benchmarks.

## Consequences

- Equivalence holds by construction for every guarded case, and the generated code stays small: most of R's unusual semantics are never compiled.
- A bailout costs the native work done before it plus a full R run. Bailouts are expected to be rare (error paths, unusual data); `aw_explain()` makes frequent ones visible so they can be compiled properly.
- Purity is a hard boundary of the static tier. Random-number generation will enter only with bit-identical generators, and re-execution after a bailout will restore `.Random.seed` first.
- Arguments are evaluated when the compiled function is called, not lazily, and a long-running compiled loop cannot be interrupted; both are documented in `?aw_compile`.

## Amendment (28 October 2026): fallbacks are announced

A function outside the subset, and a signature that cannot be compiled or built, used to run in GNU R silently, with the reason only in `attr(f, "arwad_fallback")` and `aw_explain()`. That hid a real problem: the first draft of the PLS-SEM engine assigned whole matrix columns, fell back to GNU R, and its first benchmark timed interpreted R ([ADR-0006](0006-pls-sem-engine.md)). Since package version 0.0.0.9011, `aw_compile()` and the first call of such a signature print one message naming the function and the reason; `options(arwad.quiet = TRUE)` turns the messages off. Bailouts during a call, which are part of normal operation (an `NA` condition, a value R warns about), stay silent and are counted by `aw_explain()`. The construct that caused it, `m[, j] <- v`, now compiles.
