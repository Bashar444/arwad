# Agent team: ten builder–verifier duets

R-Goose is built by one project lead directing AI agents. Each work area has a **builder** and an **adversarial verifier** drawn from a *different* model family, so the verifier does not share the builder's blind spots. Twenty roles, ten duets.

## 1. Roles and tools on the project lead's workstation

| Role | Tool | Responsibility |
|---|---|---|
| Orchestrator and architect | Claude Code (Opus) | Owns contracts, ADRs and the task board; runs the Spec Kit cycle (`speckit-specify` → `speckit-plan` → `speckit-tasks` → `speckit-taskstoissues`) |
| Builders | Claude Code subagents, each in its own git worktree | One work package per session; opens a pull request |
| Verifiers | Codex (GPT family, via the Codex plugin), Gemini, DeepSeek (bulk test generation through the local LLM gateway) | Try to break the change: edge cases, fuzzing, equivalence, benchmark fairness |
| Final authority | Project lead | Approves ADRs, merges to `main`, approves any public claim |

## 2. The ten duets

| # | Area | Builder delivers | Verifier attacks with |
|---|---|---|---|
| 1 | Front end | R parse data → RG-IR lowering | Thousands of generated R snippets, including malformed and precedence-heavy ones |
| 2 | Types and shapes | Inference and specialisation guards | Type-confusion cases; calls that violate a specialisation |
| 3 | Memory planner | Storage plans and peak-memory bounds | Bounds proofs, Goose `checkfree fn` kernels, AddressSanitizer builds |
| 4 | Goose emitter | Goose modules with `export fn` entry points | Compiling every emitted module; any warning fails |
| 5 | Native build and cache | TinyCC and clang paths; content-hash cache | Reproducible-build checks; stale-cache scenarios |
| 6 | R binding | The `rgoose` package and `.Call` glue | `R CMD check --as-cran`, rchk, sanitiser builds |
| 7 | Linear algebra | QR, Cholesky, BLAS/LAPACK bindings | NIST StRD regression sets (Longley, Filip, Wampler) and ill-conditioned designs |
| 8 | Statistical engines | OLS/GLM, PLS-SEM, DEA, panel, time series, meta-analysis | Equivalence against `stats`, `seminr`, `Benchmarking`, `plm`, `rugarch`, `metafor` on 50 datasets each |
| 9 | Random numbers and resampling | Bit-exact Mersenne-Twister, inversion normals, `sample()` | Stream equality with GNU R across seeds and lengths |
| 10 | Benchmarks, CI and WebAssembly | Harnesses, CI matrix, browser build | Benchmark falsification: warm versus cold, caching, BLAS and thread parity |

## 3. Contracts between duets

- RG-IR and the memory plan are defined by versioned JSON schemas; a change to a schema needs an ADR.
- The compiled-kernel ABI is a generated C header; the binding layer is generated from it.
- The equivalence harness ([ADR-0004](adr/0004-numerical-equivalence-gate.md)) is the merge gate for every change that can affect a number.

## 4. Working rules

1. One work package per agent session, sized to finish within it; heavy jobs run in the background.
2. Builders never merge their own work; a verifier from another model family must sign off.
3. No GPL source in prompts or outputs (clean room, [IP_AND_LICENSING.md](IP_AND_LICENSING.md)).
4. No performance claim leaves the repository without a reproducible benchmark ([BENCHMARK_METHOD.md](BENCHMARK_METHOD.md)).
5. Usage discipline: check the usage meter before a heavy work package, offload bulk generation to the cheaper gateway model, and write a handoff note when limits approach.
