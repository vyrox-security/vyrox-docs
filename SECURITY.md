# Security policy

This document tells you how to report a vulnerability to Vyrox, what we
will do with the report, what is in scope and what is not, and which
properties of the system we consider security invariants. If you read
nothing else, the contact is `sec.vyrox@proton.me` and the PGP key is at
`vyrox.dev/.well-known/pgp-key.txt`.

## Reporting

Send the report to `sec.vyrox@proton.me`. Subject line `SECURITY: <one
line description>`. PGP-encrypt the body if the finding is sensitive;
the key is published at `vyrox.dev/.well-known/pgp-key.txt`.

Please include:

- A description of the issue, in plain language, with enough detail that
  we can reproduce it.
- The repository or service affected. If the bug is in `vyrox-proxy`,
  include the commit hash you tested against.
- A proof of concept, ideally as a single shell command or a short
  script. Synthetic targets only. Do not exploit a production tenant.
- Your preferred handle for credit, or "anonymous" if you would rather
  not be named.

Please do not file vulnerabilities as public GitHub issues.

## Response

Acknowledgement within forty-eight hours.
Initial triage decision within seven calendar days.
Patch timeline shared within fourteen calendar days, including a target
fix date and the version we expect to roll into.

If we accept the report, we coordinate disclosure with you. We default
to a thirty day embargo while we ship and verify the fix. The embargo
extends if the issue affects a vendor we have not yet patched against,
and we tell you in writing why.

If we decline the report, we explain why in writing and you are free to
disclose at your discretion. Common reasons we decline: the finding is
in a third-party dependency we do not maintain, the finding requires an
attacker who already controls the host, or the finding is a known
trade-off documented in this repo.

## Scope

In scope across every repository in the Vyrox organisation:

- Authentication bypass on any service. The Rust proxy `/execute` and
  `/audit/export` endpoints, the Python ingestion webhooks, the
  Discord bot `/interactions` and `/webhook`.
- Cross-tenant data leakage. Anything that lets a request from tenant
  A read, write, or signal tenant B.
- Audit log tampering. Anything that breaks the hash chain without
  detection. See [`AUDIT_CHAIN.md`](AUDIT_CHAIN.md) for the format.
- Containment action execution without a Discord human approval click.
- HMAC verification weaknesses. Timing channels, prefix confusion,
  malleability in the canonical JSON used by Python `↔` Rust signing.
- Replay attacks within the thirty second window on the proxy.
- LLM prompt injection that produces a result the Pydantic validator
  accepts but that should have been rejected.
- Webhook signature forgery against any of the four ingestion routes
  (`crowdstrike`, `sentinelone`, `defender`, `generic`).
- Secret extraction from any in-memory or on-disk location the
  documentation says is unreachable.

Out of scope:

- Findings that require physical access to a customer host.
- Denial-of-service caused by exhausting public dependencies (rate
  limits on free LLM tiers, Discord rate limits, Redis quotas). These
  are operational concerns we degrade gracefully against, not
  vulnerabilities.
- Issues in EDR vendor APIs that Vyrox calls into. Report those to
  the vendor.
- Bugs in development-only tooling (the simulator, local docker
  setups) when used outside their documented purpose.
- Misconfiguration findings on a customer-operated installation that
  ignore the documented configuration in this repo.

## Security invariants

The six critical rules in [`ARCHITECTURE.md`](ARCHITECTURE.md#critical-rules)
are the invariants we hold the code to. Any report that demonstrates a
break in one of these is in scope and the patch will ship with the
shortest reasonable embargo.

1. Tenant isolation on every database query and every Redis key.
2. Audit entry written before any state-changing response.
3. HMAC verification on the raw bytes, before any parse, in constant
   time.
4. No path from LLM output or worker logic to a containment call. Only
   a Discord button click reaches the proxy.
5. `DRY_RUN=true` by default in the proxy. Production opts in.
6. LLM output passes Pydantic validation before any field is read.

The threat model in [`THREAT_MODEL.md`](THREAT_MODEL.md) lists the
specific attacker capabilities we defend against and the mitigations
that defend against them.

## What we do with the report

After triage, you can expect:

- A private GitHub Security Advisory in the affected repository, with
  you tagged if you accepted credit.
- A CVE if the issue qualifies under MITRE's rules and we are the
  primary CVE numbering authority for the affected component.
- A code fix and a regression test that locks the fix in. We do not
  patch a finding without adding a test that would have caught it.
- A note in the changelog of the affected repository on the day the
  embargo ends.

We do not pay bounties during alpha. We do publish credit on the
`vyrox.dev/security/credits` page once the issue is public.

## Coordinated disclosure timeline

```
day  0   report received
day  2   acknowledgement sent
day  7   triage decision (accept, decline, or follow-up questions)
day 14   patch timeline shared
day 30   embargo end (default)
```

The reporter can negotiate a longer embargo. We will not extend it
unilaterally without explaining why.

## What you can do today without filing a report

We welcome adversarial testing against the open-source components. The
proxy and the simulator are designed to be run against each other in a
local stack. If you find a behaviour that worries you but you are not
sure whether it is a vulnerability, open a discussion in the
`vyrox-proxy` repository and tag a maintainer. We will move the
conversation to private if it turns out to be sensitive.

## Maintainer contact

`sec.vyrox@proton.me` is monitored by the founder and one engineer.
Replies come from the same address. We do not respond from personal
accounts, and we do not ask reporters to contact us through DMs on
social platforms.
