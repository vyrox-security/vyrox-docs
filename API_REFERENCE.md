# API reference

Every public HTTP surface exposed by the Vyrox platform. There are seven
endpoints across three services:

| Service | Method | Path | Auth |
|---|---|---|---|
| Ingestion | POST | `/webhook/crowdstrike` | HMAC-SHA256 over body |
| Ingestion | POST | `/webhook/sentinelone` | Bearer token |
| Ingestion | POST | `/webhook/defender` | Bearer token (Microsoft `clientState`) |
| Ingestion | POST | `/webhook/generic/{tenant_id}` | HMAC-SHA256 over body |
| Ingestion | GET | `/health` | none |
| Rust proxy | POST | `/execute` | HMAC-SHA256 over body |
| Rust proxy | GET | `/audit/export?tenant_id={id}` | HMAC over `tenant_id:timestamp` |
| Rust proxy | GET | `/health` | none |

The Discord bot exposes `/interactions` and `/webhook`. Those are not
documented here because they speak the Discord protocol (Ed25519) or
are internal-only (worker to bot, HMAC signed). If you need to call
into the bot, you are inside the Vyrox monorepo and there is no public
contract.

## Authentication primitives

### HMAC-SHA256 over a request body

Used by the CrowdStrike webhook, the Generic webhook, and the proxy
`/execute`. The signing function in `shared/crypto.py::sign(payload,
secret)` returns `f"sha256={hex_digest}"`. The verifier on the
receiving side strips the `sha256=` prefix and compares against its
own computed digest with `hmac.compare_digest` (Python) or
`subtle::ConstantTimeEq` (Rust).

Two rules for any caller. Sign the raw bytes you put on the wire. If
your body is JSON, pin the encoding so the byte stream is
deterministic:

```python
import json
from shared.crypto import sign

body = json.dumps(payload, separators=(",", ":"), sort_keys=True)
signature = sign(body, secret)  # "sha256=..."
```

The `separators` and `sort_keys` parameters matter. Without them,
Python and Rust will serialise the same dictionary into different byte
streams and the signature will mismatch even when the value is
identical.

### Bearer token

Used by the SentinelOne and Defender webhooks. The header is
`Authorization: Bearer <secret>` and the receiver constant-time
compares with `hmac.compare_digest`. The secret is per tenant; resolution
happens after an "untrusted preview parse" of the body, identical to
the HMAC routes (see `_resolve_tenant_webhook_secret` in
`ingestion/main.py`).

### Replay window

The Rust proxy and the audit-export endpoint both enforce a thirty
second replay window. The timestamp is part of the signed message.
Requests older than thirty seconds, or more than thirty seconds in the
future, return HTTP 410.

The window is symmetric on purpose. A client whose clock is ahead of
ours by minutes cannot pre-sign requests for later use.

## Common patterns

### Per-tenant authentication

Every ingestion route resolves the tenant before verifying the
signature. The flow is the same regardless of vendor:

1. Read the raw body bytes.
2. Parse the body as JSON. This parse is untrusted; the result is used
   only to extract the vendor's tenant identifier (`customer_id`,
   `accountId`, `tenantId`).
3. Look up the per-tenant secret in `tenant_credentials`. Fall back to
   the environment-configured default secret for that vendor if the
   tenant has not been onboarded yet.
4. Verify the signature or bearer token against that secret.
5. Only after verification succeeds, promote the parsed body to the
   trusted payload and run the adapter.

A payload with no tenant identifier returns HTTP 400 with
`{"detail": "missing tenant identifier"}`. There is no default-tenant
fallback. This was the SEV-1 risk removed on 2026-05-21.

### Error envelope

Every endpoint returns a JSON body on error. The shape is consistent:

```json
{ "detail": "<short, generic message>" }
```

We do not leak which part of the credential was wrong, which field was
missing, or what the expected signature would have been. Errors are
the same for every failure of the same class. Use the audit log if you
need to debug an authentication failure; the log records the request
correlation ID, the resolved tenant, and the failure kind.

### Status codes

| Code | Meaning |
|---|---|
| 200 OK | Used only by `/health` and the proxy `/audit/export`. |
| 202 Accepted | Webhook payload was authenticated and queued for triage. |
| 400 Bad Request | Missing tenant identifier on a webhook payload. |
| 401 Unauthorized | Authentication failed. Generic message; no specifics. |
| 410 Gone | Timestamp outside the thirty second replay window. |
| 422 Unprocessable Entity | Authenticated payload could not be normalised. |
| 503 Service Unavailable | Redis is unreachable. `Retry-After: 5` header set. |

## Ingestion endpoints

The ingestion service runs on port 8001 by default. All four webhook
routes return HTTP 202 with `{"status": "queued", "alert_id":
"<uuid>"}` on success.

### POST `/webhook/crowdstrike`

Receives CrowdStrike Falcon detection events.

Headers:

```
Content-Type: application/json
X-Vyrox-Signature: sha256=<hex_digest>
```

The signature is computed over the raw body using the tenant's HMAC
secret. The tenant identifier is the `customer_id` field on the
payload.

Body shape (minimal):

```json
{
  "detect_id": "evt:1234567890:abc123",
  "customer_id": "acme-corp",
  "timestamp": 1704067200,
  "severity": "high",
  "tactic": "TA0004",
  "technique": "T1059",
  "sensor": {
    "hostname": "workstation-01",
    "agent_id": "12345678-1234-1234-1234-123456789abc"
  },
  "process": {
    "file_name": "cmd.exe",
    "command_line": "powershell -enc JABjAGwA...",
    "user_name": "CORP\\jsmith",
    "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  }
}
```

Fields the normaliser reads (`ingestion/models.py::_from_crowdstrike`):

| Field | Required | Notes |
|---|---|---|
| `detect_id` | yes | Vendor side identifier, stored as `raw_id` for dedup. |
| `customer_id` | yes | Resolves the tenant. A missing or empty value returns HTTP 400. |
| `timestamp` | no | Defaults to `time.time()` at receive time. |
| `severity` | no | Uppercased and stored as `vendor_severity`. |
| `tactic` | no | MITRE tactic name. |
| `technique` | no | MITRE technique ID. |
| `sensor.hostname` | no | The affected endpoint. |
| `process.file_name` | no | The executable name. |
| `process.command_line` | no | Full command line. Triage values this heavily. |
| `process.user_name` | no | User context. Domain format like `CORP\\jsmith` is fine. |
| `process.sha256` | no | File hash. |

### POST `/webhook/sentinelone`

Receives SentinelOne threat events.

Headers:

```
Content-Type: application/json
Authorization: Bearer <tenant_secret>
```

The bearer token is constant-time compared against the per-tenant
secret. The tenant identifier is `accountId` on the body.

Body shape (minimal):

```json
{
  "id": "thrt_1234567890abc",
  "accountId": "acme-corp",
  "createdAt": 1704067200,
  "severity": "high",
  "mitreTactic": "TA0004",
  "mitreTechnique": "T1059",
  "agentRealtimeInfo": {
    "computerName": "workstation-01",
    "agentId": "1234567890abc"
  },
  "fileName": "powershell.exe",
  "commandLine": "powershell -enc JABjAGwA...",
  "fileContentHash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
}
```

### POST `/webhook/defender`

Receives Microsoft Defender for Endpoint alerts via the Microsoft Graph
Security API webhook subscription.

Headers:

```
Content-Type: application/json
Authorization: Bearer <clientState>
```

The bearer value is the `clientState` you chose at subscription time.
The tenant identifier is `tenantId` on the body (the Azure AD tenant
the alert came from).

Body shape (alertV2 subset that the normaliser reads):

```json
{
  "id": "abc123",
  "tenantId": "11111111-2222-3333-4444-555555555555",
  "createdDateTime": "2026-05-23T14:32:00Z",
  "severity": "high",
  "category": "CredentialAccess",
  "mitreTechniques": ["T1003"],
  "evidence": [
    {
      "deviceDnsName": "workstation-01.acme.local",
      "userAccount": {
        "userPrincipalName": "jsmith@acme.com"
      },
      "imageFile": {
        "fileName": "lsass-dumper.exe"
      },
      "processCommandLine": "lsass-dumper.exe -o creds.dmp",
      "fileDetails": {
        "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
      }
    }
  ]
}
```

The Defender `evidence` array is heterogeneous. The normaliser
(`ingestion/models.py::_from_defender`) walks the array and pulls the
first instance of each evidence kind it recognises. Microsoft can and
does add new evidence kinds; that does not break normalisation, the
adapter just ignores what it has not seen before.

### POST `/webhook/generic/{tenant_id}`

The catch-all webhook for any EDR that can POST JSON but is not on the
natively-supported list. The tenant identifier comes from the URL path
because the customer's payload shape is not known in advance.

Headers:

```
Content-Type: application/json
X-Vyrox-Signature: sha256=<hex_digest>
```

The customer also supplies a field map at onboarding time. The map
tells the adapter how to find each `NormalizedAlert` field on their
payload, using dotted-path notation:

```json
{
  "raw_id": "event.id",
  "hostname": "device.name",
  "username": "actor.upn",
  "process_name": "process.exe",
  "process_cmdline": "process.cli",
  "sha256": "file.hash",
  "vendor_severity": "metadata.severity",
  "tactic": "mitre.tactic",
  "technique": "mitre.technique",
  "timestamp": "event.ts"
}
```

Required keys in the field map: `raw_id`, `hostname`, `vendor_severity`.
A missing required key returns HTTP 422.

### GET `/health`

Returns `{"status": "ok"}` when the service is up and Redis is
reachable. Returns 503 with `Retry-After: 5` otherwise.

## Containment proxy endpoints

The Rust proxy runs on port 3000 by default. It accepts two
non-health requests and refuses everything else.

### POST `/execute`

Executes a human-approved containment action.

Headers:

```
Content-Type: application/json
X-Vyrox-Signature: sha256=<hex_digest>
```

Body:

```json
{
  "request_id": "550e8400-e29b-41d4-a716-446655440000",
  "tenant_id": "acme-corp",
  "alert_id": "alt_abc123",
  "action_type": "HOST_ISOLATION",
  "host": "workstation-01",
  "approved_by": "jane.smith#1234",
  "approved_at": 1704067200
}
```

| Field | Type | Notes |
|---|---|---|
| `request_id` | string | UUID-v4. Idempotency key. Same ID returns the cached response. |
| `tenant_id` | string | Multi-tenant scope. Carried into every audit entry. |
| `alert_id` | string | The alert that triggered the action. |
| `action_type` | enum | `HOST_ISOLATION`, `PROCESS_KILL`, or `NETWORK_QUARANTINE`. |
| `host` | string | Vendor-specific host identifier. CrowdStrike uses device IDs. |
| `approved_by` | string | Identifier of the human who approved the action (console user, or notifier username such as the Discord bot's). |
| `approved_at` | int | Unix epoch seconds. Must fall in the replay window. |

Responses:

```json
{ "status": "executed", "dry_run": false }
{ "status": "dry_run",  "dry_run": true  }
{ "status": "replayed", "dry_run": false }
```

| Status | Meaning |
|---|---|
| `executed` | The EDR vendor returned success. |
| `dry_run` | `DRY_RUN=true` was in effect; the EDR API was not called. |
| `replayed` | The same `request_id` was already executed; the cached response is returned without calling the EDR again. |

Error codes:

| Code | Cause |
|---|---|
| 400 | `request_id` empty or body fails to parse after HMAC succeeds. |
| 401 | HMAC verification failed, or `X-Vyrox-Signature` header missing. |
| 409 | Same `request_id` still in flight from a prior call. |
| 410 | `approved_at` outside the thirty second replay window. |
| 500 | Internal failure, including audit write failure. The nonce claim is released so a retry can succeed. |
| 502 | EDR vendor API returned an error. The nonce claim is released. |

### GET `/audit/export?tenant_id={id}`

Returns every audit entry for the requested tenant. The entries are
returned as JSON in the response body; for streaming exports on large
logs, see the roadmap.

Headers:

```
X-Vyrox-Signature: sha256=<hex_digest>
X-Vyrox-Timestamp: 1704067200
```

The signature is HMAC-SHA256 of the canonical message
`"<tenant_id>:<timestamp>"` using the shared HMAC secret. The
timestamp must fall in the thirty second replay window. Without both
headers, the response is 401.

Response:

```json
[
  {
    "timestamp": 1704067200,
    "tenant_id": "acme-corp",
    "action_type": "HOST_ISOLATION",
    "host": "workstation-01",
    "approved_by": "jane.smith#1234",
    "dry_run": false,
    "previous_hash": "0000...0000",
    "hash": "e3b0c4..."
  }
]
```

Every entry carries a `previous_hash` and a `hash` so an external
verifier can reproduce the chain. The format spec and a reference
verifier are in [`AUDIT_CHAIN.md`](AUDIT_CHAIN.md).

### GET `/health`

Returns `{"status": "ok"}` when the proxy is up. The health endpoint
has no dependencies; it returns 200 even when EDR vendors are
unreachable.

## Rate limiting

The ingestion service has no rate limit at the HTTP layer. EDR vendors
themselves rate-limit their webhook deliveries. If you need to slow
the worker down, throttle at the queue layer.

The Rust proxy has no per-route rate limit either. The nonce store
dedups by `request_id` for ten minutes, which is the effective limit
for repeated requests with the same ID. A burst of unique requests
hits the EDR vendor's own rate limit, which the proxy surfaces as a
502.

A per-tenant rate limit on the proxy is on the roadmap. The driver is
operational: a misconfigured automation that fires a hundred Approve
clicks in a second should not turn into a hundred EDR API calls.

## Versioning

API contracts in this document are stable for the alpha. Breaking
changes will be announced in `CHANGELOG.md` of the relevant repo at
least thirty days before they ship. New endpoints can be added
without notice. New optional fields on existing endpoints can be added
without notice. Removing or renaming a field is breaking.

The audit log format is versioned separately. See
[`AUDIT_CHAIN.md`](AUDIT_CHAIN.md).

## Testing your integration

Use the simulator. It is in [`vyrox-simulator`](https://github.com/vyrox-security/vyrox-simulator)
and runs entirely in bash with `openssl` and `curl`. Replays a signed
mimikatz alert against a local ingestion service in under five seconds:

```bash
git clone https://github.com/vyrox-security/vyrox-simulator
cd vyrox-simulator
VYROX_URL=http://localhost:8001/webhook \
  VYROX_HMAC_SECRET=$(cat your-test-secret) \
  ./simulate.sh mimikatz
```

`--dry-run` prints the signed payload to stdout without making the
HTTP call. Useful for debugging signature mismatches.
