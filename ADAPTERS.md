# EDR adapter contributor guide

This document is for a contributor who wants to add a new EDR vendor to
the Vyrox ingestion pipeline. The current set is CrowdStrike Falcon,
SentinelOne, Microsoft Defender for Endpoint, and a customer-mapped
generic JSON webhook. The fifth one might be yours.

## What an adapter is

A Vyrox adapter is the code that turns one specific EDR vendor's
webhook payload into a `NormalizedAlert`. The triage pipeline
downstream of ingestion only sees `NormalizedAlert`. It does not
care which vendor the alert came from. Adding a new vendor is
mechanical: write one factory method, one route, one test file,
update one README, done.

The contract between the adapter and the rest of the platform is the
four rules in the next section. The rules are not stylistic; they
are how the security model holds. Every existing adapter follows
them. Every new adapter must.

## The four rules

These exist in the private monorepo at
`vyrox/ingestion/adapters/README.md`. They are reproduced here so
contributors do not need access to the private side to know what to
build.

### Rule 1: Authentication before parsing

The route MUST verify the request's authentication before running
`json.loads()` on the body. Parsing untrusted bytes is a class of
attack we do not need to be exposed to.

The accepted pattern, in pseudocode:

```python
body = await request.body()                       # 1. raw bytes
preview = json.loads(body)                        # 2. untrusted parse, only to find tenant_id
tenant_id = resolve_tenant_id(vendor, preview)    # 3. raises if missing
secret = resolve_tenant_secret(tenant_id, vendor) # 4. per-tenant
verify(body, signature, secret)                   # 5. authenticate on raw bytes
payload = preview                                 # 6. now trusted
alert = NormalizedAlert._from_<vendor>(payload, tenant_id)
```

Step 2 is the only place where an unauthenticated parse is allowed,
and its result is used for one thing only: finding the tenant_id
field on the payload. If the per-tenant secret lookup fails or the
signature comparison fails, the request returns 401 before any
business logic touches the parsed dict.

### Rule 2: tenant_id from authenticated context

The `tenant_id` that goes onto the `NormalizedAlert` MUST come from
a source the signature actually authenticates. Two acceptable
patterns:

- The tenant identifier is part of the signed body. CrowdStrike
  (`customer_id`), SentinelOne (`accountId`), and Defender
  (`tenantId`) all work this way. The preview-parse trick is safe
  because the per-tenant secret is keyed on the identifier from the
  preview, and the signature compare uses that secret. A wrong
  tenant either produces no secret lookup hit or fails the signature
  check.
- The tenant identifier is part of the URL path. The generic adapter
  works this way. The URL itself is not signed, but the per-tenant
  secret is keyed on the path tenant_id, so a mismatched path
  resolves to the wrong secret and the HMAC compare fails.

What is NOT acceptable: trusting an unauthenticated header like
`X-Tenant-Id`, relying on a query string parameter, or falling back
to a shared default tenant when the identifier is missing. The
`MissingTenantIdentifier` exception in the private
`ingestion/main.py` exists for exactly this case. Missing identifier
returns HTTP 400, never a silent route to a shared bucket.

### Rule 3: Audit entry before HTTP 202

Every accepted alert MUST land in the audit JSONL chain before the
ingestion handler returns 202 to the EDR vendor. The order matters.
If the process crashes between the enqueue and the audit write, we
prefer the audit to be missing rather than the alert. The current
implementation writes the audit hop inside `queue.enqueue` for that
reason.

If your adapter calls a non-default code path that bypasses
`queue.enqueue`, write the audit entry manually before the route
returns. The pattern in `shared/audit.py::AuditWriter.write` takes a
dict; the conventional event name is `ingest.accepted` with at
minimum `tenant_id`, `source` (vendor name), and `raw_id` (the
vendor's own alert ID).

### Rule 4: Output is a valid `NormalizedAlert`

The only thing the rest of the pipeline sees is `NormalizedAlert`.
Your adapter MUST produce one. Three constraints:

- `source` is a unique vendor string. Lowercase, no spaces. Choose
  one that does not collide with the existing four
  (`crowdstrike`, `sentinelone`, `defender`, `generic`).
- `tenant_id` is populated from the authenticated context (rule 2).
- `id` is a fresh internal UUID. Do not reuse the vendor's
  identifier. Store the vendor's ID in `raw_id` instead. The two are
  not the same: `raw_id` is for vendor-side dedup; `id` is the
  Vyrox-internal identifier referenced by audit entries and Discord
  buttons.

Missing optional fields default to `None` or empty string. Never to a
placeholder like `"unknown"`, the triage engine treats `None` and
`"unknown"` differently.

## What `NormalizedAlert` looks like

```python
@dataclass
class NormalizedAlert:
    tenant_id: str
    id: str                                # internal UUID, auto-generated
    source: str                            # "crowdstrike", "sentinelone", ...
    raw_id: str                            # vendor's own alert ID, used for dedup
    timestamp: int                         # unix epoch seconds
    hostname: str                          # affected endpoint
    username: str | None                   # optional
    process_name: str | None
    process_cmdline: str | None
    sha256: str | None
    tactic: str | None                     # MITRE tactic name
    technique: str | None                  # MITRE technique ID
    vendor_severity: str                   # INFORMATIONAL | LOW | MEDIUM | HIGH | CRITICAL
```

The dataclass is intentionally flat. Nested vendor structures
(CrowdStrike's `sensor`, SentinelOne's `agentRealtimeInfo`, Defender's
`evidence` array) are flattened during normalisation. Triage code
reads top-level fields only.

`vendor_severity` is the vendor's own assessment, not Vyrox's. The
triage pipeline produces its own verdict afterwards.

## Adding a new vendor in six steps

The example below sketches an adapter for a hypothetical "Acme EDR"
vendor that posts alerts to a webhook with a bearer token.

### Step 1: Add a factory method on `NormalizedAlert`

In the private monorepo, in `vyrox/ingestion/models.py`, add a
classmethod that takes the vendor payload and a tenant_id and returns
a populated `NormalizedAlert`.

```python
@classmethod
def _from_acme(cls, payload: dict[str, Any], tenant_id: str) -> "NormalizedAlert":
    """
    Parse an Acme EDR alert payload into a NormalizedAlert.

    Acme posts a flat JSON with a top-level `alert_uuid`, a nested
    `endpoint` block, and a nested `actor` block. The schema is the
    one documented at <Acme docs URL> retrieved on <date>.
    """
    return cls(
        tenant_id=tenant_id,
        source="acme",
        raw_id=str(payload.get("alert_uuid", "")),
        timestamp=int(payload.get("ts", time.time())),
        hostname=payload.get("endpoint", {}).get("name", ""),
        username=payload.get("actor", {}).get("user"),
        process_name=payload.get("actor", {}).get("process_name"),
        process_cmdline=payload.get("actor", {}).get("command_line"),
        sha256=payload.get("actor", {}).get("sha256"),
        tactic=payload.get("mitre", {}).get("tactic"),
        technique=payload.get("mitre", {}).get("technique"),
        vendor_severity=str(payload.get("severity", "LOW")).upper(),
    )
```

Two conventions worth following. Pin the Acme schema URL and the
date you read it in the docstring; vendors change their format and a
future maintainer needs to know which version you targeted. Default
optional fields to `None` (or empty string for strings); do not
substitute placeholders.

### Step 2: Add a thin adapter module

In `vyrox/ingestion/adapters/`, create `acme.py`:

```python
"""
Acme EDR webhook adapter.

The route in `ingestion/main.py` calls into `normalize`. This module
exists to keep the route file readable as the vendor count grows.
"""

from __future__ import annotations
from typing import Any

from ingestion.models import NormalizedAlert


def normalize(payload: dict[str, Any], tenant_id: str) -> NormalizedAlert:
    """Convert an Acme alert payload into a NormalizedAlert."""
    return NormalizedAlert._from_acme(payload, tenant_id)
```

The module is intentionally tiny. The reason is convention: every
adapter ships as a `normalize(payload, tenant_id) -> NormalizedAlert`
function so the route code does not have to memorise factory method
names.

### Step 3: Add a route in `ingestion/main.py`

Mirror the existing routes. Here is the shape for a bearer-token
vendor that puts `tenant_id` in the body:

```python
@app.post("/webhook/acme", status_code=status.HTTP_202_ACCEPTED)
async def webhook_acme(
    request: Request,
    authorization: str = Header(default=""),
    q: QueueClient = Depends(get_queue_client),
) -> dict[str, str]:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid signature")
    token = authorization[7:]

    body = await request.body()
    try:
        untrusted_preview = json.loads(body)
    except json.JSONDecodeError:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="bad payload")
    if not isinstance(untrusted_preview, dict):
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="bad payload")

    try:
        tenant_id = resolve_tenant_id("acme", untrusted_preview)
    except MissingTenantIdentifier:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="missing tenant identifier")

    tenant_secret = _resolve_tenant_webhook_secret(
        tenant_id=tenant_id, vendor="acme", default_secret=settings.acme_webhook_secret
    )
    if not tenant_secret or not hmac.compare_digest(token, tenant_secret):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid signature")

    payload = untrusted_preview

    try:
        from ingestion.adapters import acme as acme_adapter
        alert = acme_adapter.normalize(payload, tenant_id)
    except Exception:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="bad payload")

    if not q:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="redis unavailable", headers={"Retry-After": "5"})

    try:
        alert_id = await q.enqueue(alert)
        return {"status": "queued", "alert_id": alert_id}
    except (EnqueueFailed, ConnectionError):
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="redis unavailable", headers={"Retry-After": "5"})
```

For an HMAC-signed vendor (like CrowdStrike or the generic adapter)
swap the bearer-token check for `verify(body.decode("utf-8"),
x_vyrox_signature, tenant_secret)`. The shape stays the same.

### Step 4: Wire the tenant identifier into `resolve_tenant_id`

Add a case to `resolve_tenant_id`:

```python
elif source == "acme":
    identifier = payload.get("customer_id")  # or whatever Acme calls it
```

If the vendor identifier is missing, the function raises
`MissingTenantIdentifier`, the route returns 400, and the EDR retries.
No silent default.

### Step 5: Add tests

Create `vyrox/tests/test_adapters_acme.py`. Cover at least:

- Happy path: a valid signed payload returns 202 with an `alert_id`.
- Missing tenant ID: returns 400.
- Wrong signature: returns 401.
- Malformed JSON: returns 422.
- Redis unavailable: returns 503 with `Retry-After: 5`.
- Field mapping: the resulting `NormalizedAlert` has the expected
  values for every field your factory populates.

Use the same fixture style as `tests/test_ingestion_main.py`. The
existing tests are the right template; copy and adjust.

### Step 6: Update the adapter README and the public docs

Two files to touch:

- `vyrox/ingestion/adapters/README.md` (private): add a row to the
  adapter table.
- `vyrox-docs/API_REFERENCE.md` (public): add the new endpoint with
  its full schema and the field-mapping table.

The pattern in the existing adapters is the documentation contract.
A reviewer reading the new endpoint should be able to integrate
against it without reading your code.

## Anti-patterns we catch in review

The list below is what we have actually rejected in past reviews.

- **"Just for testing" default-tenant fallback.** Returns a shared
  bucket when the identifier is missing. This was the SEV-1 we
  removed on 2026-05-21. There is no scenario where this is correct.
- **Re-serialising the body before HMAC verify.** Python's default
  `json.dumps` and Rust's `serde_json` disagree on whitespace and key
  order. Always verify on the raw bytes from `await request.body()`,
  never on `json.dumps(payload)`.
- **Skipping per-tenant secret lookup "for the pilot".** The pilot is
  when per-tenant secrets matter most. Falling back to the global
  secret is a deliberate, audited choice for un-onboarded tenants
  only.
- **Logging the full raw payload.** Payloads contain process command
  lines, user accounts, hostnames. Log structured fields, not the
  whole blob.
- **Treating the vendor's severity as Vyrox's verdict.** The vendor's
  severity goes into `vendor_severity`. Triage produces a separate
  verdict. Conflating the two breaks the entire downstream contract.

## Adapters that already exist

| Adapter | Vendor | Auth | Tenant ID source | Code |
|---|---|---|---|---|
| `crowdstrike` | CrowdStrike Falcon detection events | HMAC-SHA256 | `customer_id` on body | private |
| `sentinelone` | SentinelOne streaming API | Bearer token | `accountId` on body | private |
| `defender` | Microsoft Graph Security API alertV2 | Bearer token (Microsoft `clientState`) | `tenantId` on body | private |
| `generic` | Any EDR posting JSON | HMAC-SHA256 | URL path | private |

The CrowdStrike and SentinelOne factories live directly on
`NormalizedAlert` (`_from_crowdstrike`, `_from_sentinelone`) for
historical reasons. The Defender and generic factories live in the
adapter package. Newer adapters should follow the package pattern.

## What the review focuses on

When a contributor opens an adapter PR, the reviewer checks:

- Authentication-before-parse order, byte-exact.
- Per-tenant secret lookup, with the global default only as a
  fallback for un-onboarded tenants.
- Tenant ID source is authenticated.
- Audit entry written before the 202 returns.
- `NormalizedAlert.source` is unique and lowercase.
- `raw_id` is set from the vendor's own identifier.
- Tests cover the five failure modes plus the happy path.
- Schema URL and date are pinned in the factory docstring.
- No raw payload logging.
- Public docs updated with the new endpoint.

Adapters that pass review tend to ship in a single PR. Adapters that
fail review usually fail rule 1 (parse before verify) or rule 2
(tenant from unauthenticated source). Read the existing adapters
before writing yours.

## Cross-references

- [`API_REFERENCE.md`](API_REFERENCE.md) for the public webhook
  contracts.
- [`ARCHITECTURE.md`](ARCHITECTURE.md#critical-rules) for the six
  critical rules every adapter must respect.
- [`THREAT_MODEL.md`](THREAT_MODEL.md) for the attacker model.
