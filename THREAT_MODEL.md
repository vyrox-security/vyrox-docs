# Threat model

This document is the asset-by-asset, attacker-by-attacker view of the
Vyrox platform. It is the document a regulated workload's security
review will ask for, and it is the document that drives every test in
`tests/test_p0_regressions.py` and `tests/test_p05_blockers.py`.

The format is STRIDE-aligned but pragmatic. We list each asset, the
attackers we consider in scope for that asset, the threats they could
plausibly carry out, the mitigations that defend against those threats,
and the residual risks we have accepted.

## Trust boundaries

```
   public internet                                   private network

   EDR vendors  ──── webhooks ────────▶  ingestion   ────▶  Redis
                                              │
                                              └────────▶  SQLite
                                                              ▲
   Discord  ──── interactions ──────────▶  bot   ────────────┘
                                              │
                                              └──── HMAC-signed ──▶  Rust proxy
                                                                          │
                                                                          ▼
                                                                    EDR vendor
                                                                    APIs
```

Boundaries that matter:

1. EDR vendor → ingestion webhook. The vendor is honest, the network
   between them and us is not. Mitigations: HMAC-SHA256 or bearer
   token per route, per-tenant secrets stored in `tenant_credentials`.
2. Discord → bot `/interactions`. Discord is honest, anyone with the
   bot URL is not. Mitigations: Ed25519 signature verification with
   the application public key.
3. Worker → bot `/webhook`. The worker is honest, anyone on the same
   network as the bot is not. Mitigations: HMAC-SHA256 over
   deterministic-JSON body using the shared `VYROX_HMAC_SECRET`.
4. Bot → Rust proxy. Same model. Mitigations: HMAC-SHA256 plus a
   thirty second replay window plus per-request-ID nonce dedup.
5. Customer → bot slash commands. Customer-side users are not all
   equal. Mitigations: Discord-side RBAC via role IDs; the bot rejects
   approval clicks from users without the configured admin role.

## Assets

### A1: Customer audit log

The append-only JSONL audit log per tenant. Contains a record of every
alert triaged, every Discord approval click, every proxy execution,
every action result. The log is the authoritative incident-response
artifact and the SOC 2 evidence sample.

| Threat | Mitigation | Residual |
|---|---|---|
| Modify a past entry to hide an executed containment | SHA-256 hash chain over the full payload. Any single-byte change breaks the chain at the modified entry and every entry after it. Operators verify with the standalone script in [`AUDIT_CHAIN.md`](AUDIT_CHAIN.md). | An attacker who controls the host can truncate the log to a prior good entry. We detect truncation only on restart by comparing `last_hash` between processes. Tracked as "tamper detection on truncation" in the roadmap. |
| Read another tenant's audit log | Every audit entry carries `tenant_id`. The Rust proxy `/audit/export` endpoint filters server-side on `tenant_id` and requires an HMAC-signed timestamp header on the request. | An operator with shell access on the proxy host can read everyone's log. Out of scope; treat shell access as a P0 incident. |
| Lose entries on power loss between write and OS flush | `_sync_write` in `shared/audit.py` calls `flush` + `os.fsync`. The Rust side calls `flush` + `sync_data`. Both flush to physical storage before returning. | A disk failure between fsync and the next read can still lose the entry. Mitigate at the filesystem layer (RAID, snapshots). |

### A2: HMAC shared secret (`VYROX_HMAC_SECRET`)

A thirty two byte secret encoded as sixty four hex characters. Signs
every Python-to-Python and Python-to-Rust call.

| Threat | Mitigation | Residual |
|---|---|---|
| Recover the secret from a timing channel during HMAC compare | `hmac.compare_digest` in Python, `subtle::ConstantTimeEq` in Rust. Both run in time proportional to MAC length, not to where the first byte mismatches. Locked by tests in `tests/test_crypto.py` and `vyrox-proxy/src/hmac.rs::tests`. | An attacker who can co-locate on the same CPU might measure cache timing in theory. Not feasible against an HMAC compare in practice. |
| Leak the secret in logs or error responses | Settings module never logs the secret. HMAC failures return a generic 401 with detail "invalid signature". The Rust proxy uses `tracing` with the secret field marked private. | Misconfigured external log aggregator could capture an env dump. Mitigate at the deployment layer. |
| Use the same secret to forge a request after a key rotation | A rotation invalidates all signed requests immediately. The bot regenerates the request ID on every retry, so any cached old-secret payload becomes useless after the rotation. | Operator must coordinate rotation between the worker, bot, and proxy. Documented in the runbook. |

### A3: Per-tenant webhook secrets

Each onboarded tenant has its own webhook secret in
`tenant_credentials.webhook_secret_encrypted`. The column is named
"encrypted" but stores raw bytes during the pilot. Encryption at rest
ships when the encryption module lands.

| Threat | Mitigation | Residual |
|---|---|---|
| Tenant A spoofs a payload as tenant B | The route resolves the tenant from the payload first, then looks up that tenant's secret. The signature must match the per-tenant secret, not the global one. A wrong-tenant signature fails the HMAC compare. | A misconfigured route that uses the global fallback secret for a tenant who should have their own is detectable in the audit log (the lookup logs at WARN). Tracked as I-8 in the roadmap. |
| Read another tenant's secret from the DB | All DB queries filter by `tenant_id`. There is no read path that returns all `tenant_credentials` rows. The schema preflight at startup refuses to start the service if the table is missing the `tenant_id` column. | A direct SQL session has access to everything. Restrict shell access. |

### A4: Discord application token

`DISCORD_BOT_TOKEN` lets the bot post messages, fetch member rosters,
and react to interactions. A compromised token lets an attacker delete
the bot, post arbitrary messages, or impersonate the bot inside
customer servers.

| Threat | Mitigation | Residual |
|---|---|---|
| Token leaked via env dump | Token is not logged. Settings module masks the value in `__repr__`. Production deployments use a secret manager rather than .env files on disk. | Misconfigured CI could leak the token in a build log. Use the secret-injection feature of the CI provider, not echo. |
| Attacker uses the token to forge an interaction reply | Outbound calls to Discord use the token. Inbound interactions are verified against the application public key (Ed25519). A leaked token does not let an attacker forge interactions back to us, only push messages out as the bot. | Cannot prevent an attacker from impersonating the bot in customer servers until we detect and rotate the token. Rotation runbook ships before customer #5. |

### A5: Containment proxy ability to call EDR vendors

The Rust proxy can call CrowdStrike, SentinelOne, or Defender APIs to
isolate hosts, kill processes, and quarantine network access. The
blast radius of a compromised proxy is the whole tenant fleet.

| Threat | Mitigation | Residual |
|---|---|---|
| Forge an `ActionRequest` without the shared secret | HMAC verification before any parse. Constant-time compare. Replay window of thirty seconds. Nonce dedup on `request_id`. All four together leave the attacker no path. | Compromising the host running the proxy bypasses everything. Treat as a P0 host-level incident. |
| Trick the proxy into calling a wrong host | The proxy treats the `host` field as opaque and passes it through to the EDR API. The EDR vendor checks that the host belongs to the calling tenant. A wrong host either fails the EDR API or affects the same tenant. | An attacker with the right HMAC and the right tenant can isolate a host belonging to that tenant. They have already passed authentication; this is not a privilege escalation. |
| Re-execute a containment via the replay window | Nonce store records every `request_id` for ten minutes. A replayed request with the same ID returns the cached response and never calls the EDR. A replayed request with a different ID fails the thirty second timestamp check. | An attacker who controls the wire could ship a fresh `request_id` within thirty seconds, but they would also need to ship a valid signature. They cannot do that without the secret. |
| `DRY_RUN=false` in development by accident | `DRY_RUN=true` is the default. Production opts in. The bool parser accepts the common spellings (`true`, `1`, `yes`, `on`) and warns on anything else. | An operator who explicitly turns off DRY_RUN can still cause real EDR calls. Documented. The expected production setting is `DRY_RUN=false` plus a vendor API token; the absence of the token also short-circuits the call. |

### A6: LLM provider trust boundary

We send process command lines, hostnames, and user account names to a
third-party LLM router. The router is a trust boundary we do not
control. Some customers will require an opt-out.

| Threat | Mitigation | Residual |
|---|---|---|
| LLM provider logs payloads and is compromised | Tenants can opt out of LLM triage at the contract level. With LLM disabled, the worker returns MEDIUM/0.5 from `worker.llm._conservative_fallback` on the ambiguous middle band. Heuristics still handle the high and low confidence ends. | Cannot prevent the provider from seeing data when LLM is enabled. Documented in the pilot agreement. |
| LLM prompt-injection attack from inside a malicious file path | The prompt is a fixed template; vendor data only appears in the value slots. The response goes through Pydantic validation before any field is used. A response that does not match the schema falls back to MEDIUM/0.5 and writes a `llm_call_parse_error` audit event. | A model that returns a perfectly-formed but wrong verdict still passes validation. Mitigate with heuristics overrides for known false-positive patterns. |

### A7: Discord interaction endpoint

The bot's `/interactions` route is publicly reachable on the internet
because that is the contract with Discord. Anyone who finds the URL
without the Ed25519 public key can attempt to forge interactions.

| Threat | Mitigation | Residual |
|---|---|---|
| Forge an `approve_<alert_id>_<tenant_id>` button click | Every interaction POST carries `X-Signature-Ed25519` and `X-Signature-Timestamp`. The bot verifies the Ed25519 signature against `settings.discord_public_key` before any handler runs. A bad signature returns 401. Locked by `tests/test_p05_blockers.py::test_discord_signature_*`. | The verifier is bypassed when `DISCORD_PUBLIC_KEY` is empty. Local dev only; production refuses to set up Discord without the key. |
| Replay a captured legitimate interaction | Discord publishes guidance against this and uses a short timestamp window. The Vyrox approval handler also checks `AlertRecord.status` and ignores clicks on alerts that are already executed, executing, or approved. A replayed click on an alert that already fired is a no-op. | A replay of a click on a brand-new alert within a few seconds is theoretically possible if Discord's window is open. The cost is one duplicate audit entry of `approve.duplicate_click_ignored`, not a double execution. |

### A8: Worker `/webhook` from bot

The bot calls the worker's notification surface only when the worker
calls the bot first, but the bot also receives worker notifications.
The `/webhook` on the bot was unauthenticated until 2026-05-23 (Fix B
in the audit). It is now HMAC-protected.

| Threat | Mitigation | Residual |
|---|---|---|
| Anyone with the bot URL posts a fake alert embed into a tenant channel | Worker signs the body with `VYROX_HMAC_SECRET`. Bot verifies before parsing. Locked by `tests/test_discord_bot.py::test_webhook_post_rejects_unsigned`. | Compromise of `VYROX_HMAC_SECRET` lets an attacker do this; same blast radius as the proxy compromise above. |

## Out of scope

We do not consider the following in this threat model. They are real
risks; they are out of scope because they live above or below our
control surface.

- A malicious EDR vendor sending fabricated alerts. We trust the EDR
  vendor as the source of truth on what events happened on the
  customer's hosts.
- A malicious tenant with the correct credentials self-isolating their
  own hosts. They authenticated; that is the contract.
- Physical attacks on the deployment host, the customer's endpoints,
  or our developer workstations.
- Side-channels at the silicon level. Spectre-class attacks, rowhammer,
  power analysis. Out of scope for a security tool that runs on top of
  Linux on commodity cloud hardware.
- Discord platform availability. We design for the platform being up;
  the backup notification path (email plus PagerDuty for CRITICAL
  alerts) handles platform outages.

## What changed and when

The threat model is versioned implicitly through the commit history of
this file. Material changes:

- 2026-05-21: First end-to-end audit. Drove the original eight P0
  blockers in `todo.md` (private), all of which shipped.
- 2026-05-23: Second audit. Drove eight P0.5 blockers: Discord Ed25519,
  bot webhook HMAC, proxy audit-export auth, Rust audit chain, Python
  audit chain across boots, real `/onboard` flow, env example sync,
  Redis configuration. All shipped.

The audits themselves are private. The fixes are public and the tests
that lock them are documented in [`ARCHITECTURE.md`](ARCHITECTURE.md).
