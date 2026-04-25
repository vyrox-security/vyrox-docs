# Vyrox Docs

![Licence](https://img.shields.io/badge/licence-proprietary-lightgrey?style=flat-square)
![Build](https://img.shields.io/badge/build-passing-2ea44f?style=flat-square)
![Version](https://img.shields.io/badge/version-v0.1.0--alpha-005cc5?style=flat-square)
![Platform](https://img.shields.io/badge/platform-markdown-1f2328?style=flat-square)
![Funny](https://img.shields.io/badge/docs-unusually%20accurate-6a737d?style=flat-square)

Vyrox Docs is the public technical reference for architecture, API behavior, and security decisions across the Vyrox platform, intended for engineers who prefer verifiable detail over marketing adjectives. It exists as a dedicated repository so documentation quality is versioned, reviewable, and auditable independently of implementation churn, which is essential in an open-core model where trust starts with what a CISO can read before deployment.

## Why This Exists

Security tooling fails in one of two ways: poor implementation or poor understanding of implementation. Teams spend plenty of time on the first and often leave the second for later, usually the day before an investor or procurement call.

This repository avoids that failure mode by treating architecture and security rationale as first-class deliverables. If a reviewer cannot trace how a decision was made, the decision effectively does not exist.

Separate docs also keep integration risk lower for design partners. They can evaluate assumptions and constraints quickly without waiting for private repository access.

## Architecture

```text
[Architecture]
	|
	+--> system flow and boundaries
	|
	+--> security model and trust assumptions
	|
	+--> API contracts and payload schemas
	|
	+--> quickstart and integration guides
```

Document status:

| Document | Status | Last Updated |
| --- | --- | --- |
| ARCHITECTURE.md | Published | 2026-04-23 |
| README.md | Published | 2026-04-25 |

## Quickstart

Prerequisites:

1. A Markdown-capable editor
2. Basic familiarity with the Vyrox pipeline

1. Open the architecture overview first.

```bash
# Read the end-to-end system and component map
less ARCHITECTURE.md
```

2. Identify the document path relevant to your role.

```bash
# Search for integration and security sections
rg "Integration|Security|API|Webhook" ARCHITECTURE.md
```

3. Use this repository as the source of truth for public technical claims.

```bash
# Confirm local changes before proposing doc updates
git diff
```

## Configuration

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| N/A | No | N/A | Documentation repository; no runtime environment variables. |

## Contributing

Contributions are most useful when they improve technical accuracy, remove ambiguity, or close gaps between documented behavior and actual implementation in public repositories. Precise corrections beat broad rewrites.

Do not submit narrative-only copy updates that avoid technical detail, and do not add claims about security controls unless they are implemented and testable. If a statement cannot be verified, it should not be in this repository.

See CONTRIBUTING.md for review process and formatting expectations. Documentation pull requests are accepted, but they are held to the same accuracy standard as code changes.

## Licence

This repository is released under Vyrox commercial terms. See LICENCE for details.