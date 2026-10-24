# ADR-0003: MIT licence, DCO, clean room, no patent; name Arwad

- **Status:** Accepted
- **Date:** 2026-10-24
- **Decided by:** the project lead (the patent question was delegated by him to the engineering team on 2026-10-24 and decided as below)

## Context

The project lead wants an open, globally adopted language that he owns and that carries his name, as a decisive step in his career. Ownership in open source comes from copyright, trademark, control of releases and recognised priority. Public disclosure ends the possibility of patenting in most jurisdictions. GNU R is GPL-licensed; Goose is Apache-2.0.

## Decision

1. **Licence:** MIT, copyright Bashar Al Agha, worldwide. (A dual "MIT OR Apache-2.0" licence, as used by Rust, remains an option that adds an explicit patent grant for users.)
2. **Contributions:** Developer Certificate of Origin sign-off; inbound = outbound.
3. **Clean room:** no GNU R source is copied or translated; behaviour is re-implemented from documentation and black-box tests.
4. **Patent: none.** Reasons: India's section 3(k) excludes computer programs per se; Goose's memory model is public prior art (since 30 August 2026); compiling R subsets to native code has a long history; costs are high and enforcement unrealistic for an open-source language. Global protection of the project's identity comes instead from a **registered trademark**: first in India (classes 9 and 42), then internationally through the Madrid Protocol (WIPO).
5. **Priority and credit:** a public repository with dated commits, a Zenodo DOI per release, and a peer-reviewed methods paper.

## Name

**Arwad**, confirmed by the project lead on 2026-10-24 (his first preference, R++, is already in use and cannot be a repository, package or domain name; see [IP_AND_LICENSING.md](../IP_AND_LICENSING.md) §4). The working title "R-Goose" is retired. The trademark application follows a professional clearance search.

## Consequences

- The repository became public on 2026-10-24, under the MIT licence.
- Trademark registration, not the licence, protects the project's identity worldwide.
