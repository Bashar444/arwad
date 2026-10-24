# Governance

## Project lead

**Dr. Bashar Al Agha** ([ORCID 0009-0004-5178-2345](https://orcid.org/0009-0004-5178-2345)) founded R-Goose and has final authority on its direction, architecture decisions, releases, licensing and name.

## How decisions are made

1. Anything with lasting consequences (language semantics, IR schemas, the native back end, licensing, the public name) is proposed as an Architecture Decision Record in [docs/adr/](docs/adr/).
2. An ADR states its context, the decision, and its consequences, and is merged only with the project lead's approval.
3. Day-to-day changes follow [CONTRIBUTING.md](CONTRIBUTING.md): a pull request, a verifier's review from a different model family or a different person, and a green equivalence gate.

## Agents

AI agents build and verify under the rules in [docs/AGENT_TEAM.md](docs/AGENT_TEAM.md). They never merge to `main` and never publish claims; both require the project lead.

## Future

When outside contributors join regularly, this document will add maintainer roles and a steering process. Until then, the model is a single project lead.
