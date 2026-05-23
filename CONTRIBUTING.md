# Contributing

This document tells you what we will merge, what we will not, and what
the review will check.

We accept contributions to three public repositories: `vyrox-proxy`,
`vyrox-simulator`, and this docs repo. The private monorepo is not
open to outside contributors today; once a public adapter or feature
needs private-side wiring, a Vyrox maintainer takes it from there.

## Before you start

If your patch is more than a hundred lines or changes a contract,
open an issue or a draft PR first. Five minutes of "is this the
shape you want" saves a week of "we cannot merge this because the
wrong abstraction".

If you found a vulnerability, do not open a PR. See
[`SECURITY.md`](SECURITY.md) for the disclosure path.

## Workflow

Standard GitHub flow on every repo:

```
fork ─▶ feature branch ─▶ commits ─▶ PR against main ─▶ review ─▶ squash merge
```

Branch names: `feat/<thing>`, `fix/<thing>`, `docs/<thing>`,
`chore/<thing>`, `test/<thing>`. The prefix matches the conventional
commit type below.

Commit messages: Conventional Commits.

```
feat(adapters): add acme webhook adapter
fix(proxy): release nonce claim on audit-write failure
docs(threat-model): document A8 worker-to-bot HMAC

Multi-line bodies are welcome. Wrap at 72.
```

If your PR has more than one logical change, split it. Reviewers can
hold one shape in their head at a time. Two unrelated changes in one
PR usually means one gets merged and the other gets nitpicked
forever.

## What we will merge

- Bug fixes with a regression test that would have caught the bug.
- New EDR adapters following the contract in
  [`ADAPTERS.md`](ADAPTERS.md), with the five required failure-mode
  tests.
- Documentation corrections backed by source. Quote the file and the
  line you read.
- Test coverage on existing code, especially around the six critical
  rules in [`ARCHITECTURE.md`](ARCHITECTURE.md#critical-rules).
- Performance improvements with benchmarks attached. We do not merge
  "should be faster" without numbers.
- Refactors that reduce surface area. We do not merge refactors that
  add surface area; those start as design discussions.

## What we will not merge

- Marketing copy presented as architecture fact. "Best in class"
  belongs on a landing page, not in the docs.
- Security guidance that weakens controls. If your PR makes the HMAC
  check optional, removes the replay window, or short-circuits the
  audit write, the answer is no, even if the test suite passes.
- Auto-generated docs that drift from the code. The OpenAPI spec is
  not the source of truth; the route handlers are.
- Code style PRs that touch hundreds of files. Run `ruff` or
  `cargo fmt` in your own branch; do not ship a workspace-wide
  reformat.
- Adapter PRs that violate the four rules. See `ADAPTERS.md` for
  what each rule is, in concrete terms.
- Changes that introduce a hard dependency on a paid SaaS provider
  without an open-source alternative documented as the default.

## Testing

Every PR runs the full test suite in CI. Local commands:

For `vyrox-proxy`:

```bash
cargo test
cargo clippy -- -D warnings
cargo fmt --check
```

For `vyrox-simulator`:

```bash
./run-tests.sh        # if present, otherwise read scenarios/ and run a few
shellcheck simulate.sh scenarios/*.sh
```

For `vyrox-docs`:

```bash
markdownlint-cli2 "**/*.md"          # if installed
```

We do not ship a private-side test harness in the public docs. If
your PR touches a contract documented here, write the test against
the public surface. The reviewer will run the matching private-side
test before merging.

## Code style

- Plain prose in docs. No em-dashes. No AI tells. Builder voice.
  Concrete file paths and function names where they help the reader.
- Rust: `cargo fmt` defaults, `cargo clippy -- -D warnings` clean.
- Python (private side): `ruff` defaults, `mypy --strict` clean, type
  hints on every public function.
- Shell: bash with `set -euo pipefail`. POSIX-compatible flags where
  practical (the simulator runs on macOS and Linux).

Tests follow the production code style. A test that would not pass
review for its prose does not get merged just because it is a test.

## Reviewer expectations

A reviewer on a public PR will:

- Read every line of the diff. We do not LGTM blocks of code we did
  not read.
- Verify the test suite covers the failure mode the change was
  supposed to fix. A bug fix without a regression test is sent back.
- Check the cross-references. If your PR changes a contract
  documented here, the docs change ships in the same PR.
- Push back on scope. If the PR is doing two things, the reviewer
  asks you to split it.

A reviewer on a private-side PR (Vyrox staff only) does the same plus
the rule-1-through-6 checklist from `ARCHITECTURE.md`.

## Documentation discipline

Three rules.

- **Document what is, not what should be.** If the code does X, the
  docs say X. Aspirational docs lead a new contributor to look at the
  code, find it disagrees, and lose trust in everything else.
- **Quote the file when you make a claim.** "The proxy verifies HMAC
  in constant time (`hmac::verify_signature` in
  `vyrox-proxy/src/hmac.rs:140`)." A reader who wants to confirm has
  exactly one place to look.
- **Update the docs in the same PR as the code.** Doc drift is a
  one-way ratchet. We close it on every PR or it grows forever.

## Cross-references

- [`QUICKSTART.md`](QUICKSTART.md) from `git clone` to a signed alert
  in about ten minutes.
- [`ADAPTERS.md`](ADAPTERS.md) for the EDR adapter contract.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) for the system overview and the
  six critical rules.
- [`SECURITY.md`](SECURITY.md) for the disclosure process.

## Code of conduct

See [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). Short version: be
direct, be technical, be respectful. We do not have time for the
opposite.
