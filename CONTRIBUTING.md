# Contributing to Vyrox Docs

## Before You Open a PR

This repository is in alpha. Bug reports and documentation corrections are welcome from anyone.

Code-adjacent documentation changes are accepted when they improve technical accuracy and reduce ambiguity.

## Development Setup

```bash
# Clone repository
git clone https://github.com/vyrox-security/vyrox-docs.git
cd vyrox-docs

# Optional markdown tooling
python -m pip install --upgrade pip
python -m pip install markdownlint-cli2 || true
```

## Opening an Issue

Use the issue templates in `.github/ISSUE_TEMPLATE`.

Do not report security vulnerabilities in public issues. Follow `SECURITY.md`.

## Opening a Pull Request

Use `.github/PULL_REQUEST_TEMPLATE.md`.

Every PR must include clear validation steps and, when applicable, updates to related docs.

## Code Style

- Write precise technical prose
- Prefer explicit examples over vague claims
- Keep command snippets runnable
- Commit messages follow Conventional Commits (`feat`, `fix`, `docs`, `test`, `chore`)

## What We Will Not Merge

- Unverifiable technical claims
- Marketing language presented as architecture fact
- Security guidance that weakens controls
- Documentation-only changes that do not fix a concrete inaccuracy
