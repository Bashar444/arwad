# ADR-0003: MIT licence, DCO, clean room; name and patent decisions pending

- **Status:** Accepted for licence, DCO and clean room · **Pending** for name and patent (project lead to decide)
- **Date:** 2026-10-24

## Context

The project lead wants an open, widely adopted language that he owns and that carries his name. Ownership in open source comes from copyright, trademark, control of releases and recognised priority. Public disclosure ends the possibility of patenting in most jurisdictions. GNU R is GPL-licensed; Goose is Apache-2.0.

## Decision

1. **Licence:** MIT, copyright Bashar Al Agha. (A dual "MIT OR Apache-2.0" licence, as used by Rust, would add an explicit patent grant for users; it can be adopted before the first public release if preferred.)
2. **Contributions:** Developer Certificate of Origin sign-off; inbound = outbound.
3. **Clean room:** no GNU R source is copied or translated; behaviour is re-implemented from documentation and black-box tests.
4. **Repository visibility:** private until the two pending decisions below are recorded here.

## Pending decisions (project lead)

| Decision | Options | Recommendation |
|---|---|---|
| Patent | (a) consult a patent attorney and file before any disclosure; (b) no patent | (b), unless an attorney identifies a concrete novel technical method first ([IP_AND_LICENSING.md](../IP_AND_LICENSING.md) §5) |
| Public name | (a) keep "R-Goose" with the Goose author's permission; (b) choose an independent, registrable name | (b), then register the trademark in India (classes 9 and 42) |

## Consequences

- Making the repository public is irreversible disclosure and happens only after the patent decision.
- Trademark registration, not the licence, protects the project's identity.
