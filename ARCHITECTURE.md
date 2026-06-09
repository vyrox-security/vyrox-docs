# Architecture

This document is the engineering reference for the Vyrox platform. It is
written for the person who is about to read or modify the code, or who is
evaluating Vyrox for a regulated workload and needs to know exactly what
the system does. It does not describe what the product will become. It
describes what runs in CI today.

If you are looking for setup steps, see [`QUICKSTART.md`](QUICKSTART.md).
If you are looking for the threat model, see [`THREAT_MODEL.md`](THREAT_MODEL.md).
If you want the on-disk audit format, see [`AUDIT_CHAIN.md`](AUDIT_CHAIN.md).

## Pipeline at a glance

```
   EDR vendors                                   Vyrox platform

  CrowdStrike Falcon  ─┐
  SentinelOne          ├─▶  POST /webhook/{vendor}  ─▶  Ingestion (FastAPI)
  Defender Graph       │      HMAC or bearer auth          │
  Generic JSON         ─┘      per-tenant secret           ▼
                                                  NormalizedAlert  ─▶ Redis  LPUSH/RPOP
                                                                          │   vyrox:alerts:{tid}
                                                                          ▼
                                              Worker (asyncio)

                                              1. Cache lookup     (24h TTL by alert fingerprint)
                                              2. Heuristics       (Noisy OR, <5ms)
                                                                  ├─ confidence ≥ 0.75 ▶ accept
                                                                  ├─ confidence ≤ 0.25 ▶ BENIGN
                                                                  └─ otherwise ▶ LLM
                                              3. LLM fallback     (primary + 2 fallback models)
                                                                  + Pydantic schema validation
                                                                  + per-tenant daily token budget
                                              4. Persist          (SQLite, tenant-scoped tables)
                                              5. Notify           (signed HTTP to bot)

                                              Discord bot (FastAPI)
                                              ├─ /interactions  (Ed25519 verified)
                                              ├─ /webhook       (HMAC verified)
                                              └─ approval flow  ▶ Rust proxy

                                              Rust proxy
                                              ├─ HMAC verify       (constant time)
                                              ├─ replay window     (±30s)
                                              ├─ nonce dedup       (DashMap, 10min retention)
                                              ├─ audit append      (hash-chained JSONL)
                                              └─ EDR API call      (or DRY_RUN short-circuit)
```

All five services are independent processes. They communicate over HTTP
and Redis only. There is no shared in-process state across services. The
SQLite database is shared between the worker and the Discord bot in the
current pilot deployment. A future Postgres migration is tracked in
`todo.md` (private) before tenant count reaches twenty five.

## Components

| Component | Language | Process | What it owns |
|---|---|---|---|
| Ingestion | Python, FastAPI | `uvicorn ingestion.main:app` | Webhook auth, vendor payload normalisation, Redis enqueue |
| Worker | Python, asyncio | `python -m worker.main` | Triage pipeline, persistence, Discord notification |
| Discord bot | Python, FastAPI | `uvicorn discord_bot.main:app` | Interaction handling, approval flow, signing toward the proxy |
| Containment proxy | Rust, Axum | `vyrox-proxy` | HMAC verify, replay window, nonce dedup, audit, EDR API call |
| Heuristics engine | Python | imported by the worker | Pattern matching, Noisy OR aggregation |

The heuristics engine is private. The shape of its API (`HeuristicsEngine.score(alert: dict) -> HeuristicResult`) is documented here because callers depend on it. The pattern weights and the MITRE technique mapping are not.

## Critical rules

These six rules are enforced by tests and reviewed in every PR. Violating
one is a blocking issue, not a stylistic choice.

### Rule 1: Tenant isolation

Every database query carries a `tenant_id` filter. Every Redis key is
namespaced `vyrox:alerts:{tenant_id}`. There is no shared bucket and no
fallback tenant.

The previous default-tenant fallback was removed on 2026-05-21 after the
first audit caught it. The replacement contract: if a payload arrives
without the vendor's tenant identifier (`customer_id`, `accountId`,
`tenantId`), the ingestion route returns HTTP 400 and the EDR retries.
The function is `resolve_tenant_id` in `ingestion/main.py`. It raises
`MissingTenantIdentifier` on a missing or empty value.

The schema invariant is checked at boot. `shared/db.py:_assert_tenant_id_present`
walks every table in `_TENANT_SCOPED_TABLES` (`alerts`, `actions`,
`verdict_cache`, `token_usage`) and refuses to start the service if any
of them is missing the `tenant_id` column. The check uses `PRAGMA
table_info`, runs once at startup, and raises `SchemaIntegrityError`
loudly enough that the deploy fails.

### Rule 2: Audit before response

Every state-changing operation writes an audit entry before the response
goes back to the caller. The audit log is append-only JSONL. Each entry
carries `previous_hash` (the SHA-256 of the prior entry) and `hash` (the
SHA-256 of `previous_hash || canonical_json(entry)`). The first entry of
the very first log file links to a sentinel genesis hash of sixty four
zeros.

The chain survives process restarts. `AuditWriter.__init__` in
`shared/audit.py` reads the last hash from today's log file before
accepting the first write. The Rust proxy uses the same approach in
`audit::ChainState::from_file`. Both implementations agree on the wire
format. The independent specification is in [`AUDIT_CHAIN.md`](AUDIT_CHAIN.md).

Audit writes are durable. `_sync_write` in `shared/audit.py` flushes and
`os.fsync` after every entry. The Rust side does `flush` followed by
`sync_data`. A power cut between the write and the OS writeback does
not lose entries.

### Rule 3: HMAC before processing

Every webhook payload is verified before any parser touches its bytes.
The verification uses `hmac.compare_digest` on the Python side and the
`subtle::ConstantTimeEq` trait on the Rust side. Both run in time
proportional to the MAC length, not to where the first byte mismatch
appears.

The wire format on the Python side: `sign(payload: str, secret: str)`
returns `f"sha256={hex_digest}"`. The Rust verifier strips the
`"sha256="` prefix before comparing. The round-trip is locked by
`tests/test_p0_regressions.py::test_hmac_python_sign_uses_sha256_prefix`.

For requests carrying JSON bodies that travel between Vyrox services
(the worker calling the bot, the bot calling the proxy), the body is
serialised with `separators=(",", ":")` and `sort_keys=True`. Without
that pinning, Python's default `json.dumps` and Rust's `serde_json`
disagree on whitespace and key order, which produces a different MAC
on the verifier side and a silent 401.

### Rule 4: No autonomous containment

The LLM cannot trigger a containment action. The heuristics engine
cannot trigger a containment action. The worker cannot trigger a
containment action.

The only code path that calls the Rust proxy is the Discord bot's
approval handler in `discord_bot/handlers/approvals.py`, which runs in
response to a Discord button click. The button click itself is
authenticated end to end: Discord signs the interaction with Ed25519,
the bot verifies the signature against the application's public key in
`discord_bot/security.py`, the handler then signs an `ActionRequest`
with the shared HMAC secret, and the proxy verifies that signature
before doing anything else.

The static invariant is enforced by a test:
`tests/test_p0_regressions.py::test_worker_triage_never_invokes_proxy`
greps the worker modules at import time and at source level for any
reference to `discord_bot.proxy_client.execute_action`. If the worker
ever imports that symbol, the test fails. The check covers both eager
imports and lazy imports inside functions.

### Rule 5: DRY_RUN by default

The Rust proxy's `dry_run` flag is `true` by default. Production has to
opt in to real execution by setting `DRY_RUN=false` in the environment.
The check happens before the EDR client is even constructed, so
mis-configuration cannot accidentally call the vendor's API.

```rust
// vyrox-proxy/src/main.rs
let response = if state.dry_run {
    info!(/* ... */, "DRY_RUN: skipping EDR call");
    ExecuteResponse { status: "dry_run".to_string(), dry_run: true }
} else {
    state.edr.dispatch(payload.action_type, &payload.host).await
};
```

The audit entry written on a DRY_RUN action looks identical to a real
action except for the `dry_run: true` field. That is intentional. An
operator looking at the audit log can tell the difference, and a
compliance review on the JSONL stream sees the same chain integrity
either way.

### Rule 6: LLM output never directly executed

The LLM returns a JSON object with five fixed fields: `verdict`,
`confidence`, `reasoning`, `mitre_techniques`, `suggested_action`. The
`triage_with_llm` function in `worker/llm.py` runs the parsed object
through `_parse_triage_json` which checks every field against a fixed
allow-list (verdict in `{CRITICAL, HIGH, MEDIUM, LOW, BENIGN}`,
confidence clamped to `[0, 1]`, suggested_action in the action allow-list).
A response that fails validation produces a conservative MEDIUM verdict
at 0.5 confidence, not a partial commit.

The validated object never touches `exec`, `eval`, `subprocess`, the
filesystem, or SQL. It only sets fields on a `TriageResult`. The
Pydantic model itself is frozen so even a downstream caller cannot
mutate fields after the fact.

## Multi-tenancy

Tenant isolation is a property of the data layer, not a runtime check
in business logic.

| Surface | How tenants are separated |
|---|---|
| Redis queue | Key namespace: `vyrox:alerts:{tenant_id}` |
| SQLite tables | Every row carries `tenant_id`; queries filter on it |
| Discord channels | `DiscordGuild.tenant_id` maps Discord server to tenant |
| Webhook secrets | Looked up per tenant in `tenant_credentials.webhook_secret_encrypted` |
| Audit log | Each entry carries `tenant_id`; export endpoints filter server-side |
| Token budget | Daily ledger keyed on `tenant_id` and date |
| Verdict cache | Cache key `(tenant_id, fingerprint)` |

The webhook routes resolve the tenant from the vendor payload's own
identifier field (`customer_id`, `accountId`, `tenantId`), then look up
that tenant's secret in `tenant_credentials` before verifying the
signature. A payload that authenticates with the wrong tenant's secret
fails the HMAC check and returns 401. A payload with no identifier
returns 400. There is no path where an unmatched payload lands on a
shared queue.

Cross-tenant access from inside the Discord bot is blocked by
`discord_bot/main.py:312`. The `custom_id` of every approval button
embeds the alert's tenant ID. Before calling the approval handler, the
bot checks that the alert tenant matches the Discord guild's tenant.
A mismatch returns "This action is not valid for this server" without
contacting the proxy.

## Two-stage triage

Triage runs in `worker/triage.py::triage`. Five stages, three early
returns.

```
                                                              ┌────────────────────────┐
       NormalizedAlert ──▶ verdict cache ──▶ cache hit ──▶ │ return cached verdict │
                                  │                            └────────────────────────┘
                                  │ cache miss
                                  ▼
                          heuristics engine
                                  │
        ┌─────────────────────────┼─────────────────────────┐
        ▼                          ▼                          ▼
  confidence ≥ 0.75         confidence ≤ 0.25       0.25 < confidence < 0.75
  accept heuristic         return BENIGN               LLM fallback
       verdict                                          │
                                                            ▼
                                                  token budget check
                                                            │
                                ┌───────────────────────────┼───────────────────────────┐
                                ▼                            ▼                            ▼
                          budget exhausted        primary model            primary 429/5xx
                          MEDIUM / 0.5            parse + return          ▼
                                                                              fallback model 1
                                                                              parse + return
                                                                                      │
                                                                                      ▼
                                                                              fallback model 2
                                                                              parse + return
                                                                                      │
                                                                                      ▼
                                                                              all rate limited
                                                                              MEDIUM / 0.5
```

The two-stage design solves three problems at once. Determinism and
explainability for the eighty percent of alerts that are obvious. Low
cost because the LLM is reserved for the ambiguous middle band. A
conservative default verdict for any failure mode, so the queue never
jams on a provider outage. The LLM provider is not named in this doc
because the choice is operational. The model chain is configured in
environment variables (`LLM_PRIMARY_MODEL`, `LLM_FALLBACK_MODEL_1`,
`LLM_FALLBACK_MODEL_2`).

## Approval flow

```
   Discord button click
            │
            ▼
   bot /interactions   ◀──── Ed25519 verify against settings.discord_public_key
            │
            ▼
   custom_id parse  ──▶ approve / deny / investigate
            │
            ▼  (approve only)
   AlertRecord lookup by alert_id + tenant_id
            │
            ▼
   Idempotency check  ──▶ if status already executed/executing/approved → no-op
            │
            ▼
   Mark alert "executing"
   Persist ActionRecord "approved"
   Audit "approve.requested"      ◀──── written before any outbound call
            │
            ▼
   proxy_client.execute_action()
   body signed with vyrox_hmac_secret (deterministic JSON)
            │
            ▼
   Rust proxy /execute
   ├─ HMAC verify
   ├─ replay window check (±30s)
   ├─ nonce.claim_or_replay(request_id)
   ├─ audit::append_audit  ◀──── written before EDR call
   └─ edr.dispatch (or DRY_RUN short-circuit)
            │
            ▼
   ActionRecord.status = "executed" or "dry_run"
   Alert.status        = "executed"
   Audit "approve.executed"
```

The flow's idempotency story has three layers. The bot checks the
`AlertRecord.status` before generating a request ID, so a double-click
returns "already approved". The proxy keeps a per-request-ID nonce
store with ten minute retention, so a network retry replays the cached
response instead of calling the EDR twice. The audit entry is written
once per state transition; replayed requests do not double-log.

## Configuration

All configuration is read at startup from environment variables through
`shared/config.py::Settings`. The settings class uses
`pydantic_settings` so a missing required field raises a
`ValidationError` before the service serves traffic.

The full env contract is in [`.env.example`](https://github.com/vyrox-security/vyrox/blob/main/.env.example)
in the private monorepo. The fields that an OSS contributor needs to
know about:

| Variable | Component | Purpose |
|---|---|---|
| `VYROX_HMAC_SECRET` | all | Sixty four hex characters. Signs Python ↔ Python and Python ↔ Rust traffic. |
| `REDIS_URL` | ingestion, worker | `redis://` or `rediss://` URL. The legacy REST-style Redis variables are still accepted for backward compatibility but new deployments should set this. |
| `OPENCODE_ZEN_API_KEY` | worker | LLM provider key. Empty falls back to the legacy `OPENROUTER_API_KEY` during the migration window. |
| `DISCORD_BOT_TOKEN` | bot | Discord application token. |
| `DISCORD_PUBLIC_KEY` | bot | Application public key for interaction Ed25519 verification. Empty skips verification (local dev only). |
| `CROWDSTRIKE_WEBHOOK_SECRET` | ingestion | Vendor-default HMAC secret. Per-tenant secrets stored in `tenant_credentials` override this. |
| `SENTINELONE_WEBHOOK_SECRET` | ingestion | Vendor-default bearer token. |
| `DEFENDER_WEBHOOK_SECRET` | ingestion | Defender Graph `clientState` value used as bearer. |
| `AUDIT_LOG_PATH` | all writers | Directory for daily JSONL files. The hash chain depends on this surviving restart. |
| `VYROX_PROXY_URL` | bot | Base URL of the Rust proxy. |
| `DRY_RUN` | proxy | `true` by default. Production opts in to real EDR calls. |

## What is in the private side

Reading the public docs without seeing the private code is intentional.
The boundary makes contribution clear.

The private monorepo holds the implementation of the pipeline above.
File names mirror the layout described here (`ingestion/`, `worker/`,
`discord_bot/`, `shared/`, `playbook/`, `migrations/`, `tests/`). The
Python tests covering the public contracts have public-safe names
(`test_p0_regressions.py`, `test_p05_blockers.py`). Anyone with access
can map a private fix to a public contract in seconds.

The detection patterns, the LLM prompts, and the operational configs
stay private. Those are the layer that creates the business; the proxy
and the contracts are the layer that creates the trust. The split is
deliberate.

## Operating commitments

We do not publish hard SLA percentages in this repo. The reasons are
honest. Numbers we cannot defend across all pilots today belong in
negotiated contracts, not in OSS docs.

What we can commit publicly:

- The audit log is customer-owned. We do not lose it, we do not modify
  it, and we provide export at any time. The format is the contract,
  not our retention policy.
- Containment proceeds only after a human in Discord clicks Approve.
  There is no autonomous containment path.
- Webhook authentication failures and proxy signature failures both
  return generic 401 responses. We never tell a caller which part of
  the credential was wrong.

Per-customer SLAs that involve uptime targets and triage latency live
in signed contracts.

## Decisions worth knowing

A short list, written for the reader who is asking "why this and not
that".

**Rust for the proxy.** The proxy is the only Vyrox process that can
cause customer-side side effects. The set of properties we wanted in
one binary: memory safety without a garbage collector, a small static
binary, a constant-time HMAC implementation in the ecosystem, no
runtime dependency on a vendor library. The Rust choice gave us all of
them. The proxy is intentionally small. About a thousand lines of code
including tests, splitting across `main`, `hmac`, `audit`, `nonce`,
`edr`, and `actions`.

**SQLite for the pilot.** SQLite with WAL mode and a single writer
process handles the pilot scale (ten tenants, low hundreds of alerts
per day per tenant). Write contention bites somewhere around twenty
five tenants, which is the trigger for the Postgres migration. The
schema is already SQLModel-compatible, so the migration is a SQL dump
plus a connection string change, not a rewrite.

**Discord as the operator UI.** The first ten pilots use Discord
exclusively. The bot handles onboarding, alert review, approval, and
slash commands for stats and audit export. The cost is one extra
infrastructure provider; the benefit is that a customer's first
five-minute experience is "I added your bot to my server and a
synthetic alert appeared." A web dashboard ships when a prospect
refuses Discord or when customer count reaches eleven, whichever comes
first.

**Two-stage triage.** A pure LLM design is slow, expensive at scale,
and not auditable without careful prompt engineering. A pure rules
design misses anything novel. The split lets us run the heuristics for
free, run the LLM only on the ambiguous middle band, fall back to a
conservative MEDIUM on any failure, and keep the LLM output strictly
inside a Pydantic schema before it touches anything else.

**Human in the loop for execution.** Auto-isolating hosts on false
positives is the kind of incident that loses you the customer. Until
we have a year of per-tenant false-positive data, every CRITICAL and
HIGH containment is gated on a human Approve click. LOW auto-approval
is opt-in per tenant and logged identically to manual approvals.

## Cross-references

- [`THREAT_MODEL.md`](THREAT_MODEL.md): assets, threats, mitigations,
  out of scope.
- [`API_REFERENCE.md`](API_REFERENCE.md): every public endpoint with
  schemas and error codes.
- [`AUDIT_CHAIN.md`](AUDIT_CHAIN.md): on-disk format spec for the
  hash-chained audit log.
- [`ADAPTERS.md`](ADAPTERS.md): contributor guide for adding a new
  EDR vendor.
- [`QUICKSTART.md`](QUICKSTART.md): from `git clone` to a signed alert
  in about ten minutes.
- Rust proxy source: <https://github.com/vyrox-security/vyrox-proxy>.
- Simulator: <https://github.com/vyrox-security/vyrox-simulator>.
