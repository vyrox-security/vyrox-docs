# Vyrox Security

> The auditable action layer for your EDR alerts. Vyrox ingests alerts, triages
> them through a deterministic heuristics engine with an LLM fallback, routes the
> verdicts that matter to a human approver, and runs every containment action
> through a small Rust proxy you can read and audit, with a tamper-evident,
> SHA-256-chained log you own. Built for teams and MSSPs that have the alerts but
> not a 24/7 SOC.

[![License: MIT (proxy)](https://img.shields.io/badge/proxy-MIT-green?style=flat-square)](https://github.com/vyrox-security/vyrox-proxy/blob/main/LICENSE)
[![Status](https://img.shields.io/badge/status-alpha-orange?style=flat-square)](#status)
[![Audit](https://img.shields.io/badge/audit_log-SHA--256_chained-blue?style=flat-square)](AUDIT_CHAIN.md)

---

## What this repository is

`vyrox-docs` is the public engineering documentation for the Vyrox Security
platform. It carries the architecture, the API contracts, the threat model,
the audit-log specification, and the contributor guides. Sales copy,
pricing, customer rosters, and SLA contract language live elsewhere.

If you found this repo looking for the source code that touches your
endpoints, you want [`vyrox-proxy`](https://github.com/vyrox-security/vyrox-proxy).
That is the Rust binary that receives signed containment instructions from
the rest of the platform and calls the EDR vendor's API. It is MIT licensed
and small enough to read in an afternoon.

## What Vyrox actually does

Pipeline in five steps:

1. Your EDR posts alerts to a Vyrox webhook over HTTPS. Each payload is
   authenticated per tenant with HMAC-SHA256 or a vendor-specific bearer
   token. CrowdStrike, SentinelOne, Microsoft Defender, and a customer
   field-mapped generic adapter are all supported today.
2. Ingestion verifies the signature, normalises the vendor payload into a
   single `NormalizedAlert` schema, and pushes it onto a per-tenant Redis
   queue.
3. The worker pulls the alert and runs it through the heuristics engine
   (deterministic regex-and-weight pattern matching with Noisy OR
   aggregation). The result is one of CRITICAL, HIGH, MEDIUM, LOW, BENIGN
   plus a confidence score.
4. Anything in the ambiguous confidence band goes to an LLM with a strict
   JSON schema response. The LLM never executes anything. It only writes
   verdict fields. A Pydantic validator catches malformed responses and
   falls back to a conservative MEDIUM verdict at 0.5 confidence.
5. CRITICAL and HIGH verdicts land in the tenant's Discord channel as an
   embed with Approve, Deny, and Investigate buttons. Approve generates an
   `ActionRequest`, signs it, and sends it to the Rust proxy. The proxy
   verifies the signature, checks a thirty-second replay window, dedupes
   on request ID, writes an audit entry, then either dry-runs or calls
   the EDR vendor's API.

In active development (see [`ROADMAP.md`](ROADMAP.md)): per-client evidence
packs built on the audit chain (scrubbed, signed, verifiable with a bundled
open-source script), a web operational console as the primary surface with
Discord becoming one of several notifiers, real rollback for containment
actions, and a per-tenant autonomy policy layer that defaults to human
approval. None of these change the six rules below.

Six rules hold across the whole pipeline. They are documented in
[`ARCHITECTURE.md`](ARCHITECTURE.md#critical-rules) and enforced by tests.
The shortest version:

- Every database query carries `tenant_id`.
- Every state change writes an audit entry before the response goes back.
- HMAC verification happens before any payload is parsed.
- The LLM cannot trigger containment. Only a human button click can.
- Local development sets `DRY_RUN=true` by default so the proxy refuses to
  call real EDR APIs.
- LLM JSON output is never passed to `exec`, `eval`, `subprocess`, SQL, or
  file operations. Only to Pydantic-validated verdict fields.

## What is public, what is not

Open-core. The execution surface that touches customer infrastructure is
open. The detection intelligence and the operational configuration is not.

| Component | Repo | Visibility | Why |
|---|---|---|---|
| Rust containment proxy | [`vyrox-proxy`](https://github.com/vyrox-security/vyrox-proxy) | Public, MIT | Customers should be able to read the code that isolates their hosts. |
| Engineering docs | `vyrox-docs` (this repo) | Public | Threat model, API contracts, contributor guides. |
| Alert simulator | [`vyrox-simulator`](https://github.com/vyrox-security/vyrox-simulator) | Public, MIT | Lets anyone replay a signed alert against a local stack. |
| Core monorepo | `vyrox` | Private | Ingestion, worker, Discord bot. The pipeline shape is documented here; the implementation is not. |
| Heuristics engine | `vyrox-heuristics` | Private | Pattern weights, MITRE technique mapping, false-positive baselines. The detection moat. |
| Adversarial playbook | `vyrox-adversarial-playbook` | Private | Red-team TTPs we test against. |
| Infrastructure | `vyrox-deploy` | Private | Provider-specific configs and secrets. |
| Partner CRM | `vyrox-design-partners` | Private | GTM, contracts, prospect roster. |

If you want to contribute, you can do it against `vyrox-proxy`,
`vyrox-simulator`, or this docs repo without ever touching the private
side. The contribution guide is in [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Documents in this repo

Read in this order if you are new:

1. [`QUICKSTART.md`](QUICKSTART.md) walks you from `git clone` to a signed
   alert hitting a local proxy. About ten minutes, no production
   credentials required.
2. [`ARCHITECTURE.md`](ARCHITECTURE.md) is the system reference. Pipeline
   stages, multi-tenancy, audit chain, the six critical rules, the
   container boundary diagram, the decisions behind each component.
3. [`THREAT_MODEL.md`](THREAT_MODEL.md) lists the assets, the threats, the
   mitigations, and the things explicitly out of scope. If you are
   evaluating Vyrox for a regulated workload, start here.
4. [`API_REFERENCE.md`](API_REFERENCE.md) documents every public endpoint:
   the four ingestion webhooks, the proxy's `/execute` and `/audit/export`,
   request and response shapes, error codes, signing rules.
5. [`AUDIT_CHAIN.md`](AUDIT_CHAIN.md) is the wire spec for the SHA-256
   hash-chained audit log. Independent verifiers can reproduce the chain
   from the JSONL stream alone.
6. [`ADAPTERS.md`](ADAPTERS.md) is for contributors adding a new EDR
   vendor. Four rules to follow, one factory method to write, one test
   file to copy.
7. [`SECURITY.md`](SECURITY.md) is the disclosure policy. Email address,
   PGP key, scope, SLA on triage, what we do not call a vulnerability.
8. [`ROADMAP.md`](ROADMAP.md) is the public roadmap by capability. No
   revenue targets, no customer counts.
9. [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)
   cover how to send a patch and what behaviour is expected.

## Status

Alpha. The pipeline is wired end to end and runs against synthetic alerts
in CI on every push. Ten pilot integrations are the next milestone. The
two recent audits in `todo.md` (a private file) drove the P0 fixes and
the P0.5 follow-ups already merged. Test counts at the moment of writing
this README: 89 Python tests, 17 Rust tests, lints clean across the
workspace.

What "alpha" means in practice:

- The on-disk audit format is stable. Field names will not change without
  a documented migration. [`AUDIT_CHAIN.md`](AUDIT_CHAIN.md) is the
  contract.
- The HMAC signing format is stable. Python `sign` returns
  `sha256=<hex>` and the Rust proxy strips the prefix before
  constant-time-comparing.
- The ingestion webhook URL shape is stable. The four routes documented
  in `API_REFERENCE.md` are the ones we will keep.
- Anything else can move. Internal data models, the LLM provider, the
  worker concurrency model. We will note breaking changes in the
  CHANGELOG once a release tagging discipline lands.

## Security contact

`security@vyrox.dev`, PGP key at
[`vyrox.dev/.well-known/pgp-key.txt`](https://vyrox.dev/.well-known/pgp-key.txt).
Acknowledgement within forty-eight hours. Full policy in
[`SECURITY.md`](SECURITY.md). Please do not file vulnerabilities as
public GitHub issues.

## License

`vyrox-proxy` and `vyrox-simulator` are MIT licensed.

`vyrox-docs`, `vyrox-www`, `vyrox-heuristics`, `vyrox-deploy`, `vyrox-design-partners`, and the `vyrox` monorepo are proprietary.

---

*Vyrox Security, Inc., hello@vyrox.dev*
