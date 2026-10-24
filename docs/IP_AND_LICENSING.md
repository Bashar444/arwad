# Intellectual property and licensing

*This document records the project's position and the reasoning behind it. It is not legal advice; obtain professional advice before filing any trademark or patent application.*

## 1. Copyright

Copyright in the code arises automatically when it is written (Berne Convention; in India, computer programs are literary works under the Copyright Act, 1957). No registration is needed. Optional registration with the Indian Copyright Office adds evidential weight in a dispute. The copyright holder for code written by or for the project lead is **Bashar Al Agha**.

## 2. The MIT License

- **It is self-applied.** There is no application, approval or fee: placing the MIT text in `LICENSE` *is* the licence grant. GitHub then labels the repository "MIT".
- **What it allows:** anyone may use, copy, modify, merge, publish, distribute, sublicense and sell the software, provided the copyright notice and licence text are kept.
- **What the author keeps:** the copyright itself, and the requirement that every copy carry the author's name and notice.
- **What cannot be undone:** a version released under MIT stays available under MIT to whoever has it. Later versions may be released under different terms, because MIT also lets the author incorporate MIT contributions into differently licensed work.

## 3. How an open-source project is "owned"

| Lever | What it protects | Action |
|---|---|---|
| Copyright | The code as written | Automatic; keep the notice in `LICENSE` |
| **Trademark** | The *name* and *logo*: only the owner can call a release "R-Goose" | Choose a distinctive final name, then register it (India: classes 9 and 42) |
| Control of the official repository and releases | Which build is the authentic one | Project lead holds owner rights; releases are signed and tagged |
| Priority and credit | Who did it first | Dated commits; Zenodo DOI per release; peer-reviewed methods paper |

Trademark is the strongest lever: Linux, Python and Rust are open source, yet their names are controlled.

## 4. The project name

"R-Goose" is a **working title**. Before the first public release:

- "Goose" is the name of Wouter van Oortmerssen's language and also of Block's open-source AI agent *goose*, now hosted by the Linux Foundation's Agentic AI Foundation. A name built on it is weak as a trademark and may imply an affiliation that does not exist. Options: ask the Goose author for permission to use the name, or choose an independent name.
- R-Goose does not use the R logo and does not imply endorsement by the R Foundation or the R Core Team.

Decision recorded in [ADR-0003](adr/0003-mit-licence-dco-clean-room.md).

## 5. Patent assessment

| Question | Assessment |
|---|---|
| Does publishing destroy novelty? | Yes in India and most countries. India's grace provisions are narrow (for example, certain exhibitions or papers read before learned societies, within 12 months). The United States allows one year after the inventor's own disclosure; Europe has essentially no grace period. Pushing code to a public repository is publication. |
| Is software patentable in India? | "A computer programme per se" is excluded by section 3(k) of the Patents Act; an application must claim a technical effect (for example, a measured reduction in memory use by a specific method), following the CRI Guidelines. |
| What prior art exists? | Goose's memory model is public (since 30 August 2026); compiling R or R subsets to native code has a long history (Section 8 of [ARCHITECTURE.md](ARCHITECTURE.md)). A claim would have to rest on a specific, non-obvious technical method, such as the memory planner for statistical resampling. |
| Cost | Professional drafting and prosecution, plus foreign filings for international protection. |

**Default position:** do not pursue a patent unless a patent attorney identifies a concrete, novel technical method *before any public disclosure*. The working plan is MIT open source, plus a registered trademark, plus a peer-reviewed methods paper. The repository stays private until the project lead records the decision.

## 6. Licence compatibility

| Component | Licence | Role in R-Goose | Obligation |
|---|---|---|---|
| Goose compiler and runtime | Apache-2.0 | Build tool; its runtime C is linked into compiled kernels | Keep Goose's `LICENSE` and `NOTICE` when redistributing it or its runtime; compatible with distribution alongside MIT code |
| GNU R | GPL-2 or GPL-3 | Host runtime in Phases 1–3 | Never copy GPL source into this repository (clean room) |
| R API headers (`R.h`, `Rinternals.h`, …) | LGPL-2.1 or later (per R's `COPYRIGHTS` file) | The `rgoose` package compiles against them | Permitted for MIT-licensed packages, as thousands of CRAN packages do |
| tree-sitter-r (Phase 4 candidate) | MIT | Parser for the standalone runtime | Keep its notice |
| Reference BLAS/LAPACK, OpenBLAS | BSD-style | Linear algebra | Keep notices |
| CRAN packages | Each package's own licence (64.8% mention GPL, 28.7% MIT) | Run by R-Goose; not bundled in its distribution | Each package keeps its own licence |

## 7. Contributions

- **Developer Certificate of Origin** (`git commit -s`), inbound = outbound: contributions are licensed under MIT. Because MIT permits sublicensing, the project lead can still ship contributed code in other editions, provided the notices are kept, so a Contributor License Agreement is not required.
- **Clean room:** contributors and agents must not paste or translate GNU R source code. Behaviour is re-implemented from documentation (*R Language Definition*, *Writing R Extensions*, *R Internals*) and verified by black-box comparison with GNU R. Pull requests that contain GPL-derived code are rejected.
