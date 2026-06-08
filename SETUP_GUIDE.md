# Vyrox MVP Setup Guide, Design Partner Demo

> How to get the Vyrox prototype running in a B2B prospect environment for demonstration.

**Last Updated:** 2026-05-20
**Status:** MVP Demo-Ready

---

## What This Guide Covers

This guide walks through setting up Vyrox for a live B2B demo with a design partner. The goal is to have a working end-to-end system that demonstrates:

1. EDR alert ingestion (simulated or real CrowdStrike/SentinelOne)
2. AI-powered triage (heuristics + LLM fallback)
3. Discord approval workflow (CRITICAL/HIGH alerts surface in Discord)
4. Containment proxy (human-approved action execution)

**Time to demo-ready:** ~30 minutes with real credentials, ~10 minutes with simulated alerts only.

---

## Architecture Overview

```
EDR (CrowdStrike/SentinelOne)
         │
         ▼
┌─────────────────────────────────────────────┐
│  INGESTION API (port 8001)                 │
│  - HMAC/Bearer verification                │
│  - Payload normalization                   │
│  - Redis queue enqueue                      │
└────────────────┬────────────────────────────┘
                 │ redis://
                 ▼
┌─────────────────────────────────────────────┐
│  WORKER (background process)               │
│  - BRPOP from Redis queues                  │
│  - Heuristics scoring (80% of alerts)      │
│  - LLM triage (ambiguous cases, 20%)        │
│  - Verdict persistence to SQLite            │
└────────────────┬────────────────────────────┘
                 │
         ┌──────┴──────┐
         ▼              ▼
┌─────────────┐  ┌─────────────────────────┐
│  DISCORD    │  │  vyrox-proxy (port 3000)│
│  BOT        │  │  - HMAC verification     │
│  (port 8002)│  │  - Audit logging          │
│  - Alerts   │  │  - DRY_RUN=true default   │
│  - Buttons  │  └─────────────────────────┘
└─────────────┘
```

---

## Prerequisites

### Required Accounts

1. **Discord application credentials**
   - Create application at https://discord.com/developers/applications
   - Enable bot permissions: Send Messages, Use Slash Commands, Manage Roles
   - Add bot to your test server with required permissions

2. **Redis instance**
   - Local development: `docker run -p 6379:6379 redis:alpine`
   - Managed Redis: any Redis 6+ compatible provider works

3. **LLM provider credentials**
   - Vyrox supports OpenAI-compatible APIs (OpenAI, Anthropic, or any OpenAI-compatible endpoint)
   - Configure the model via `LLM_MODEL` and the endpoint via `LLM_BASE_URL`

### Optional (for real EDR integration)

4. **CrowdStrike** (requires customer account)
   - Falcon Cloud API credentials
   - Or: Use simulator for demo purposes

5. **SentinelOne** (requires customer account)
   - API token from Singularity console
   - Or: Use simulator for demo purposes

---

## Quick Start (Simulator Only, No Real EDR Needed)

This is the fastest path to a working demo without real EDR credentials.

### Step 1: Start Redis

```bash
# Terminal 1
docker run -p 6379:6379 redis:alpine
```

### Step 2: Start Ingestion API

```bash
# Terminal 2
cd ~/vyrox-workspace/vyrox
cp .env.example .env  # Edit with your secrets
uvicorn ingestion.main:app --reload --port 8001
```

### Step 3: Start Worker

```bash
# Terminal 3
cd ~/vyrox-workspace/vyrox
python -m worker.main
```

### Step 4: Start Discord Bot

```bash
# Terminal 4
cd ~/vyrox-workspace/vyrox
uvicorn discord_bot.main:app --reload --port 8002
```

### Step 5: Start Proxy

```bash
# Terminal 5
cd ~/vyrox-workspace/vyrox-proxy
cargo run
```

### Step 6: Send Simulated Alert

```bash
# Terminal 6
cd ~/vyrox-workspace/vyrox-simulator

# Configure your HMAC secret via env (matches VYROX_HMAC_SECRET in the
# ingestion service). The simulator is pure bash, no edits to source.
export VYROX_HMAC_SECRET="<paste-the-64-hex-string-from-your-.env>"
export VYROX_URL="http://localhost:8001/webhook"
export VYROX_TENANT_ID="default-tenant"

# Run a scenario
./simulate.sh mimikatz
./simulate.sh lateral --all-stages
```

**Expected behavior:**
1. Alert appears in worker logs as triaged
2. If CRITICAL/HIGH: Discord message posted with Approve/Deny/Investigate buttons
3. Clicking Approve sends request to vyrox-proxy
4. Proxy logs action (DRY_RUN=true prevents actual containment)

---

## Environment Configuration

### .env file for vyrox

```bash
# =====================================================================
# Webhook Secrets (64-char hex for HMAC)
# Generate with: python -c "import secrets; print(secrets.token_hex(32))"
# =====================================================================
CROWDSTRIKE_WEBHOOK_SECRET=YOUR_64_CHAR_HEX_HERE
SENTINELONE_WEBHOOK_SECRET=YOUR_WEBHOOK_SECRET_HERE

# =====================================================================
# HMAC Secret (shared between all services)
# =====================================================================
VYROX_HMAC_SECRET=YOUR_64_CHAR_HEX_HERE

# =====================================================================
# Redis
# =====================================================================
REDIS_URL=redis://localhost:6379

# =====================================================================
# LLM Provider (any OpenAI-compatible endpoint)
# =====================================================================
OPENCODE_ZEN_API_KEY=YOUR_LLM_API_KEY_HERE
LLM_BASE_URL=https://your-openai-compatible-endpoint/v1
LLM_MODEL=YOUR_MODEL_NAME

# =====================================================================
# SQLite Database
# =====================================================================
SQLITE_DB_PATH=./vyrox.db

# =====================================================================
# Discord Bot
# Get from https://discord.com/developers/applications
# =====================================================================
DISCORD_BOT_TOKEN=Bot YOUR_BOT_TOKEN_HERE
DISCORD_BOT_URL=http://localhost:8002
DISCORD_GUILD_ID=YOUR_GUILD_ID_HERE
DISCORD_ALERT_CHANNEL_ID=YOUR_CHANNEL_ID_HERE
DISCORD_CLIENT_ROLE_ID=YOUR_ROLE_ID_HERE

# =====================================================================
# vyrox-proxy (Rust containment executor)
# =====================================================================
VYROX_PROXY_URL=http://localhost:3000

# =====================================================================
# EDR API Credentials (optional for demo)
# =====================================================================
CROWDSTRIKE_CLIENT_ID=YOUR_CLIENT_ID
CROWDSTRIKE_CLIENT_SECRET=YOUR_CLIENT_SECRET
SENTINELONE_API_TOKEN=YOUR_API_TOKEN

# =====================================================================
# Audit & Security
# =====================================================================
AUDIT_LOG_PATH=./audit

# =====================================================================
# Development Mode (IMPORTANT: set to false only when ready for real actions)
# =====================================================================
DRY_RUN=true
```

### .env file for vyrox-proxy

```bash
VYROX_HMAC_SECRET=YOUR_64_CHAR_HEX_HERE  # Must match vyrox/.env
AUDIT_LOG_PATH=./audit.jsonl
DRY_RUN=true  # Prevent actual containment actions in demo
```

---

## Discord Bot Setup

### Create Discord Application

1. Go to https://discord.com/developers/applications
2. Click "New Application" → Name: "Vyrox Demo"
3. Left sidebar → Bot → Add Bot
4. Under "Privileged Gateway Intents":
   - yes Presence Intent
   - yes Server Members Intent
   - yes Message Content Intent
5. Under "OAuth2 URL Generator":
   - Scopes: yes bot, yes applications.commands
   - Bot Permissions: Send Messages, Manage Channels, Manage Roles, Read Message History
6. Copy the OAuth URL, open in browser, add to your test server

### Get Required IDs

1. **Guild ID** (your server):
   - Enable Developer Mode in Discord settings
   - Right-click server name → Copy Server ID

2. **Channel ID** (where alerts post):
   - Right-click channel → Copy Channel ID

3. **Role ID** (client-admin role):
   - Create a role called "client-admin" in server settings
   - Right-click role → Copy Role ID

---

## Testing the Full Pipeline

### Test 1: Health Checks

```bash
# Ingestion health
curl http://localhost:8001/health
# Expected: {"status":"ok"}

# Discord bot health
curl http://localhost:8002/health
# Expected: {"status":"ok"}

# Proxy health
curl http://localhost:3000/health
# Expected: {"status":"ok"}
```

### Test 2: Simulated Alert (Happy Path)

```bash
cd ~/vyrox-workspace/vyrox-simulator

# The simulator signs the payload with $VYROX_HMAC_SECRET (set above)
# and POSTs to $VYROX_URL. Add --dry-run to skip the POST and just
# print the signed body.
./simulate.sh mimikatz
```

**Expected logs:**
```
# Ingestion (terminal 2)
INFO:     127.0.0.1:xxxx - "POST /webhook/crowdstrike HTTP/1.1" 202 Accepted

# Worker (terminal 3)
INFO: Triaged alert xxx-xxx: verdict=HIGH, confidence=0.95, used_llm=False

# Discord (terminal 4)
INFO: Notified Discord for alert xxx-xxx
```

### Test 3: Approve Button

In Discord, find the alert message and click "Approve":

**Expected logs:**
```
# Discord bot (terminal 4)
INFO: Approved: user=USER_ID alert=ALERT_ID

# Proxy (terminal 5)
INFO: vyrox proxy listening on :3000
```

### Test 4: View Database

```bash
cd ~/vyrox-workspace/vyrox

# View alerts
sqlite3 vyrox.db "SELECT id, severity, confidence, reasoning FROM alerts LIMIT 5;"

# View audit log
sqlite3 vyrox.db "SELECT * FROM actions LIMIT 5;"
```

---

## Simulator Scenarios

The simulator generates realistic EDR alerts using Lua scenarios:

| Scenario | Description | Expected Verdict |
|---------|-------------|-----------------|
| `mimikatz` | Credential dumping tool detection | CRITICAL/HIGH |
| `lateral` | Lateral movement with WMI/PowerShell | HIGH |
| `sentinelone_lateral` | SentinelOne format variant | HIGH |

### Creating Custom Scenarios

Each scenario is a self-contained bash script in `vyrox-simulator/scenarios/`
that defines a `build_payload()` function. The dispatcher (`simulate.sh`)
sources the script, calls `build_payload`, signs the result, and POSTs it.

Copy an existing scenario as your template, then edit the JSON body:

```bash
# scenarios/custom_attack.sh
#!/usr/bin/env bash
# Scenario: Custom Attack, example template

SCENARIO_NAME="custom_attack"
SCENARIO_SOURCE="crowdstrike"
SCENARIO_SEVERITY="HIGH"
SCENARIO_TACTIC="Execution"
SCENARIO_TECHNIQUE="T1059.001"

TIMESTAMP=$(date +%s)
DETECT_ID="custom-${TIMESTAMP}"

build_payload() {
    local tenant_id="${1:-default-tenant}"
    cat <<EOF
{
    "detect_id": "${DETECT_ID}",
    "customer_id": "${tenant_id}",
    "timestamp": ${TIMESTAMP},
    "sensor": { "hostname": "WORKSTATION-DEMO" },
    "process": {
        "user_name": "DOMAIN\\\\admin",
        "file_name": "malicious.exe",
        "command_line": "malicious.exe --stealth-mode",
        "sha256": "abc123def456..."
    },
    "tactic": "${SCENARIO_TACTIC}",
    "technique": "${SCENARIO_TECHNIQUE}",
    "severity": "${SCENARIO_SEVERITY}"
}
EOF
}
```

Make it executable, then run:
```bash
chmod +x scenarios/custom_attack.sh
./simulate.sh custom_attack
```

---

## Troubleshooting

### Alert not reaching Discord

1. Check worker logs: Is the alert being triaged?
   ```
   grep -i "triage" vyrox.log
   ```

2. Check Redis queue depth:
   ```bash
   redis-cli LLEN vyrox:alerts:default-tenant
   ```

3. Verify Discord channel ID in .env matches your server

4. Check bot has correct permissions in Discord server

### Worker not processing alerts

1. Is Redis running?
   ```bash
   redis-cli ping
   # Expected: PONG
   ```

2. Check worker is polling:
   ```
   INFO: Worker started. Polling queue for alerts...
   ```

3. Check for errors in worker output

### Proxy returning 401

1. Verify HMAC secret matches between vyrox and vyrox-proxy
2. Check that requests are signed with `sha256=` prefix
3. Check proxy logs for specific error

### LLM not called (using heuristics only)

This is **expected behavior** for clear-cut alerts. The heuristics engine handles ~80% of alerts directly. LLM is only called for ambiguous cases (confidence 0.25-0.75).

To force LLM path, use a scenario that triggers ambiguity or test with a mix of scenarios.

---

## Demo Scripts

### Demo 1: "Zero to Alert in 60 Seconds"

```bash
# Reset state
rm vyrox.db && touch vyrox.db
redis-cli FLUSHDB

# Step 1: Show empty state
echo "=== Database before ==="
sqlite3 vyrox.db "SELECT COUNT(*) FROM alerts;"

# Step 2: Fire alert (from the vyrox-simulator directory)
./simulate.sh mimikatz

# Step 3: Wait for processing
sleep 3

# Step 4: Show populated state
echo "=== Database after ==="
sqlite3 vyrox.db "SELECT severity, confidence, reasoning FROM alerts;"
```

### Demo 2: "Approve → Contain"

1. Fire alert → shows in Discord
2. Click "Approve" button
3. Show proxy audit log:
   ```bash
   cat audit.jsonl
   ```
4. Show database action record:
   ```bash
   sqlite3 vyrox.db "SELECT * FROM actions;"
   ```

### Demo 3: "False Positive Dismiss"

1. Fire alert → shows in Discord
2. Click "Deny" button
3. Show status update:
   ```bash
   sqlite3 vyrox.db "SELECT status FROM alerts ORDER BY created_at DESC LIMIT 1;"
   ```

---

## Key Files for Demo

| File | Purpose |
|------|---------|
| `vyrox-simulator/scenarios/mimikatz.sh` | Realistic credential-dumping alert |
| `vyrox-simulator/scenarios/lateral_stage1.sh` | Lateral movement (stage 1 of 8) |
| `vyrox-simulator/simulate.sh` | Dispatcher, signs and POSTs every scenario |
| `vyrox/worker/triage.py` | Two-stage triage logic |
| `vyrox/shared/crypto.py` | HMAC signature verification |
| `vyrox-proxy/src/main.rs` | Containment proxy endpoint |
| `vyrox-proxy/src/audit.rs` | Append-only audit logging |

---

## Performance Notes

For demo purposes with simulated data:

- **Ingestion:** ~10ms per alert (Redis enqueue)
- **Heuristics:** ~5ms per alert (pattern matching)
- **LLM triage:** ~500ms-2s (API latency, only 20% of alerts)
- **Total latency:** ~20ms for heuristics, ~1-2s for LLM path

With real EDR credentials, the system handles:
- **100-500 alerts/minute** comfortably
- **1,000+ alerts/minute** with worker scaling

---

## Security Notes for Demo

1. **DRY_RUN=true** is default, no actual containment happens
2. HMAC verification on all endpoints
3. SHA-256 audit chain for compliance
4. Tenant isolation via Redis keys

**To enable real containment (ONLY in production):**

1. Set `DRY_RUN=false` in vyrox-proxy
2. Configure real CrowdStrike/SentinelOne credentials
3. Move to production infrastructure (don't demo on localhost)

---

## Contacts & Support

- **Docs:** https://docs.vyrox.dev
- **Security:** security@vyrox.dev
- **GitHub:** https://github.com/vyrox-security/vyrox

---

*Document maintained in `vyrox-docs/SETUP_GUIDE.md`*