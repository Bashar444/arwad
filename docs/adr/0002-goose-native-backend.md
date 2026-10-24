# ADR-0002: Goose as the first native back end, behind a back-end-agnostic IR

- **Status:** Accepted
- **Date:** 2026-10-24

## Context

The static tier needs a code generator that gives deterministic memory, no garbage collection and fast native code. Goose (Apache-2.0) provides stack-only memory with scope-exit freeing, emits a single C file, embeds a TinyCC back end for in-process compilation, supports `export fn` so a module can be linked into a C host such as an R package, passes slices as `{data, len}` without copying, and offers share-nothing worker threads. Goose is also very young: repository created 30 August 2026, release v2026.3 on 21 October 2026, a single author.

## Decision

Use Goose as the first native back end. Keep the compiler's intermediate representation (RG-IR) and memory plan independent of Goose, so that a direct C or LLVM back end can be added without changing the front end or the R binding.

## Consequences

- Phase 0 must confirm, by measurement, that Goose kernels called from R are correct and fast enough to justify the approach.
- Goose versions are pinned; upstream issues are reported and fixed through contributions where possible.
- If Goose stalls or its constraints block a needed feature, the project switches back end without discarding the front end, inference or planner.
