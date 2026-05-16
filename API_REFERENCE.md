# Vyrox API Reference

> **Base URL:** `https://api.vyrox.dev`
> **Version:** 1.0

---

## Authentication

All endpoints require authentication via:
- **HMAC-SHA256** signature in `X-Vyrox-Signature` header
- **Bearer token** in `Authorization` header (for SentinelOne)

Signature format: `sha256=<hex_signature>`

---

## Webhooks

### POST /webhook/crowdstrike

Receives detection events from CrowdStrike Falcon.

**Authentication:** HMAC-SHA256 signature

**Headers:**
```
Content-Type: application/json
X-Vyrox-Signature: sha256=<signature>
```

**Request Body:**
```json
{
  "detect_id": "evt:1234567890:abc123",
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

**Field Reference:**
| Field | Type | Required | Description |
|---|---|---|---|
| detect_id | string | Yes | Unique detection ID from CrowdStrike |
| timestamp | integer | Yes | Unix timestamp |
| severity | string | No | low, medium, high, critical |
| tactic | string | No | MITRE ATT&CK tactic (e.g., TA0004) |
| technique | string | No | MITRE ATT&CK technique (e.g., T1059) |
| sensor.hostname | string | No | Endpoint hostname |
| process.file_name | string | No | Process name |
| process.command_line | string | No | Full command line |
| process.user_name | string | No | Username (domain\\user) |
| process.sha256 | string | No | File SHA-256 hash |

**Response:** `200 OK`
```json
{
  "status": "queued",
  "alert_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

---

### POST /webhook/sentinelone

Receives threat events from SentinelOne.

**Authentication:** Bearer token

**Headers:**
```
Content-Type: application/json
Authorization: Bearer <ingestion_key>
```

**Request Body:**
```json
{
  "id": "thrt_1234567890abc",
  "createdAt": 1704067200,
  "severity": "high",
  "mitreTactic": "TA0004",
  "mitreTechnique": "T1059",
  "agentRealtimeInfo": {
    "computerName": "workstation-01",
    "agentId": "1234567890abc"
  },
  "fileName": "powershell.exe",
  "fileFullName": "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
  "commandLine": "powershell -enc JABjAGwA...",
  "fileContentHash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
}
```

**Field Reference:**
| Field | Type | Required | Description |
|---|---|---|---|
| id | string | Yes | Unique threat ID |
| createdAt | integer | Yes | Unix timestamp |
| severity | string | No | low, medium, high, critical |
| mitreTactic | string | No | MITRE ATT&CK tactic |
| mitreTechnique | string | No | MITRE ATT&CK technique |
| agentRealtimeInfo.computerName | string | No | Endpoint hostname |
| agentRealtimeInfo.agentId | string | No | Agent ID |
| fileName | string | No | Process name |
| fileFullName | string | No | Full file path |
| commandLine | string | No | Full command line |
| fileContentHash | string | No | File SHA-256 hash |

**Response:** `200 OK`
```json
{
  "status": "queued",
  "alert_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

---

## Normalized Schema

All webhooks normalize to this internal schema:

| Field | Type | Description |
|---|---|---|
| id | string | Vyrox-generated UUID |
| source | string | "crowdstrike" or "sentinelone" |
| raw_id | string | Vendor-specific ID |
| timestamp | integer | Unix timestamp |
| hostname | string | Endpoint hostname |
| username | string | User (domain\\user) |
| process_name | string | Process executable name |
| process_cmdline | string | Full command line |
| sha256 | string | File hash |
| tactic | string | MITRE tactic |
| technique | string | MITRE technique |
| vendor_severity | string | Vendor's severity (INFORMATIONAL/LOW/MEDIUM/HIGH/CRITICAL) |

---

## Error Responses

**400 Bad Request** — Invalid payload
```json
{
  "error": "invalid_payload",
  "message": "Missing required field: detect_id"
}
```

**401 Unauthorized** — Invalid signature
```json
{
  "error": "invalid_signature",
  "message": "HMAC verification failed"
}
```

**429 Too Many Requests** — Rate limited
```json
{
  "error": "rate_limited",
  "message": "Too many requests",
  "retry_after": 30
}
```

---

## Testing

Use the simulator to generate test payloads:
```bash
python vyrox-simulator/simulate_crowdstrike_alert.py --scenario mimikatz
python vyrox-simulator/simulate_crowdstrike_alert.py --scenario lateral
python vyrox-simulator/simulate_crowdstrike_alert.py --scenario benign
```