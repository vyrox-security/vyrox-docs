# Roadmap

This roadmap is organised by capability, not by quarter. It tells a
reader what we are working on, what is committed, and what is on the
list but not started. It does not contain revenue targets, customer
counts, or aspirational SLA percentages. Those live in negotiated
contracts and internal planning, not in OSS docs.

The roadmap reflects the state of the codebase. Items move from
"planned" to "in flight" when a branch exists. They move from "in
flight" to "shipped" when the code is in `main` with tests. They
move from "shipped" to "stable" when they survive a quarter without
being reverted.

## Recently shipped

The two audits in May 2026 (private; the fixes are public) drove
sixteen blocker items that all shipped between 2026-05-21 and
2026-05-23. The list:

**P0 (audit 1, 2026-05-21):**

- Per-tenant webhook secrets for CrowdStrike and SentinelOne.
- Removal of the default-tenant fallback. Missing identifier now
  returns HTTP 400, no silent shared bucket.
- HTTP 503 on Redis enqueue failure with `Retry-After: 5`. The
  silent-drop bug is gone.
- Distinct `QueueUnavailable` exception on dequeue so the worker can
  apply exponential backoff instead of spinning on a dead connection.
- Token budget enforced before every LLM call. Exhausted tenants
  return MEDIUM/0.5 with `budget_exhausted` in the audit log.
- Redis-backed retry queue for failed Discord notifications. Tenant
  scoped dead-letter with two-week TTL. Backup notification path
  triggers at five dead-letter entries per hour.
- Deterministic JSON in the proxy client. Python and Rust now sign
  byte-identical payloads with `separators=(",", ":")` and
  `sort_keys=True`.
- Idempotency on Discord approval clicks. Alert status flips through
  `executing` so a concurrent click loses the race.
- Four new regression tests: cross-tenant isolation, HMAC round-trip,
  no-autonomous-containment static guard, replay-window enforcement.

**P0.5 (audit 2, 2026-05-23):**

- Discord Ed25519 verification on the bot `/interactions` endpoint.
  Anyone with the URL can no longer forge an Approve click.
- HMAC verification on the bot `/webhook` endpoint. The phishing
  pretext via fake embeds is closed.
- HMAC verification on the proxy `/audit/export` endpoint. Tenant
  data leak via query string is closed.
- SHA-256 hash chain on the Rust proxy audit log. The Python and
  Rust chains now agree on format. See `AUDIT_CHAIN.md`.
- Python audit chain survives process restart. Previously
  `__init__` reset to genesis; now it reads the last hash from
  today's log.
- Real `/onboard` Discord wizard. Generates a per-tenant webhook
  secret with `secrets.token_hex(32)`, persists `TenantCredential`,
  fires a signed synthetic alert through ingestion, refuses to mark
  the tenant active until the round-trip succeeds.
- `.env.example` rewritten with logical sections and every new
  variable documented.
- `Settings.effective_redis_url()` resolves the canonical `REDIS_URL`
  first and falls back to the legacy REST-style Redis variables. The
  worker refuses to start with no Redis URL.

## In flight

Tracked in the private `todo.md`; called out here when the work
touches a public contract.

- **Postgres migration before tenant twenty five.** SQLite write
  contention is the binding constraint at scale. The schema is
  already SQLModel-compatible so the migration is a SQL dump plus a
  connection string change.
- **Streaming `/audit/export`.** Current endpoint reads the full log
  into memory. Fine for pilot scale; needs to be a streaming JSONL
  response for SaaS scale.
- **Per-tenant secret encryption at rest.** The
  `tenant_credentials.webhook_secret_encrypted` column stores raw
  bytes during the pilot. Encryption module ships before the first
  production payment.
- **Concurrent per-tenant triage.** The worker polls tenants
  sequentially. A slow triage on tenant A blocks tenants B through
  J. Move to `asyncio.gather` with bounded concurrency.
- **Retry runner wired into worker startup.** The retry-queue
  background task exists but the worker entrypoint does not invoke
  it. The queue accumulates without draining.

## Planned, not started

Public-facing items only. The internal product roadmap covers more.

- **Programmatic API.** A REST API for tenants to fetch verdicts,
  audit entries, and statistics outside of Discord. OAuth2 client
  credentials per tenant. Prerequisite for MSP integrations.
- **Customer-side audit verifier.** A small Rust binary that walks a
  tenant's `audit-YYYY-MM-DD.jsonl` directory and verifies the
  chain. Distributed as a single static binary. The Python reference
  in `AUDIT_CHAIN.md` is the spec.
- **EU data region.** Per-tenant `data_region` flag. Ingestion
  endpoint shard. No cross-region data flow. Required for any EU
  customer with a GDPR review.
- **Generic-vendor adapter at the route level.** Today the generic
  adapter's field map lives in `tenant_credentials.edr_api_key_encrypted`
  as a JSON string. That column should be split into a dedicated
  `field_map_json` column with a real schema.
- **Public OpenAPI spec.** The four ingestion routes and the two
  proxy routes documented in `API_REFERENCE.md`. Auto-generated
  from FastAPI on the public side; hand-written for the Rust proxy.
- **Web operator interface.** Read-only first. Tenant status, recent
  verdicts, audit search, monthly digests. Triggered when a customer
  refuses Discord-only or when total customer count crosses double
  digits, whichever first.

## Adapter coverage

| Vendor | Status | Notes |
|---|---|---|
| CrowdStrike Falcon | shipped | Detection events via HMAC-signed webhook. |
| SentinelOne | shipped | Streaming API via bearer token. |
| Microsoft Defender for Endpoint | shipped | Graph Security API `alertV2` via bearer (`clientState`). |
| Generic JSON webhook | shipped | Customer-mapped field map per tenant. |
| Sophos | planned | Native adapter, on demand. |
| Quick Heal / Seqrite | planned | Native adapter, on demand. |
| Trellix | planned | Native adapter, on demand. |
| Syslog (CEF / LEEF) | planned | Separate service that converts to the ingestion contract. |

The "on demand" adapters land when a real customer commits to a
pilot conditional on the vendor. We do not build speculatively. The
contract a new adapter must follow is in [`ADAPTERS.md`](ADAPTERS.md).

## Compliance and certification

- SOC 2 Type I evidence collection: in flight. Audit log format
  (hash-chained JSONL) is the substrate. Vendor selection for the
  audit firm is internal.
- SOC 2 Type II: planned after Type I closes.
- ISO 27001 prep: planned after SOC 2 Type II.
- Public bug bounty: not active during alpha. See
  [`SECURITY.md`](SECURITY.md) for the disclosure-only model in
  effect today.

## Versioning and release cadence

The four public repos follow semver. Today everything is `0.1.x`. The
audit log format will get an explicit `schema_version` field before we
bump to `0.2.x`. The HMAC signing format and the public webhook URL
shape will not change between `0.x` releases without a deprecation
notice in the relevant repo's `CHANGELOG.md` at least thirty days
ahead.

Patch releases happen as needed. Minor releases happen when a
meaningful feature lands. Major releases are reserved for breaking
changes to a contract published in this repo.

## What is intentionally not on the roadmap

A short list, kept honest, of capabilities we do not plan to build.

- A SIEM. Vyrox is not a log lake. We ingest alerts the EDR already
  decided are worth surfacing. Customers who want a SIEM have a
  SIEM.
- A managed SOC service with humans. We are a software platform. We
  point customers at MSSPs for the human SOC layer.
- A web dashboard during alpha. The first ten pilots use Discord
  exclusively. The dashboard ships when triggered (see "Planned,
  not started" above), not on a calendar.
- A free public ingestion endpoint. The ingestion service is operated
  per tenant. Anyone running their own can use the open path
  documented in [`QUICKSTART.md`](QUICKSTART.md).

## Cross-references

- [`README.md`](README.md) for the project overview.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) for the pipeline and the six
  critical rules.
- [`API_REFERENCE.md`](API_REFERENCE.md) for the contracts the
  roadmap references.
- [`SECURITY.md`](SECURITY.md) for the disclosure model during
  alpha.
