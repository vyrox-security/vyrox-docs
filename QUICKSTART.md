# Vyrox Quickstart Guide

> **Time to complete:** ~15 minutes
> **Prerequisites:** CrowdStrike or SentinelOne subscription, Discord server

---

## What You'll Get

- Automatic triage of every EDR alert
- Containment-ready verdicts in Discord
- Human approval workflow for CRITICAL/HIGH actions

---

## Step 1: Get Your API Keys

1. Log into your Vyrox dashboard at https://app.vyrox.dev
2. Navigate to **Settings → API Keys**
3. Create a new key pair:
   - **Ingestion Key** — for your EDR webhook
   - **HMAC Secret** — for request signing

---

## Step 2: Configure CrowdStrike Webhook

1. Open CrowdStrike Falcon console
2. Go to **Settings → Integrations → Webhooks**
3. Add new webhook:
   - **URL:** `https://api.vyrox.dev/webhook/crowdstrike`
   - **Authentication:** Custom header
     - Key: `X-Vyrox-Signature`
     - Value: HMAC-SHA256 of request body using your HMAC Secret
4. Select event types:
   - `_detection_summary_event` (required)
   - `incident_summary_event` (optional)

**Note:** If using Falcon Next-Gen AV, add the webhook to **Cloud Matches** in Sensor Policy.

---

## Step 3: Configure SentinelOne Webhook

1. Open SentinelOne console
2. Go to **Settings → Integrations → Webhooks**
3. Add new webhook:
   - **URL:** `https://api.vyrox.dev/webhook/sentinelone`
   - **Authentication:** Bearer token (use your Ingestion Key)
4. Select:
   - `Threats` (all severities)
   - `Agents` (status changes)

---

## Step 4: Install Discord Bot

1. Open your Vyrox dashboard
2. Go to **Settings → Discord**
3. Click **Add to Server**
4. Select your Discord server and authorize
5. Run `/vyrox register` in your server to complete setup

---

## Step 5: Verify Integration

Trigger a test alert in your EDR:
1. Open terminal on a monitored endpoint
2. Run: `powershell -Command "Invoke-WebRequest -Uri http://example.com"`

Within 30 seconds, you should see a LOW severity alert in your Discord channel.

---

## Step 6: Test Containment (optional)

To test the full approval workflow:

1. In Discord, run `/vyrox test-alert --scenario mimikatz`
2. You should see a CRITICAL alert with Approve/Deny buttons
3. Click **Approve** — this sends a containment request to the proxy

---

## What Happens Next

| Alert Severity | Behavior |
|---|---|
| CRITICAL/HIGH | Discord embed with Approve/Deny buttons |
| MEDIUM | Discord embed, no action required |
| LOW | Auto-dismissed (configurable) |

---

## Troubleshooting

**"Invalid signature" errors:**
- Verify HMAC secret matches between Vyrox dashboard and EDR webhook config
- Ensure you're signing the raw request body, not JSON

**No alerts appearing in Discord:**
- Check Discord channel permissions for the bot
- Run `/vyrox status` to verify connection

**Containment actions failing:**
- Verify the proxy is reachable: `curl https://proxy.vyrox.dev/health`
- Check dry_run mode is disabled in production

---

## Next Steps

- [ARCHITECTURE.md](./ARCHITECTURE.md) — system design overview
- [API_REFERENCE.md](./API_REFERENCE.md) — webhook payload schemas
- [SECURITY.md](./SECURITY.md) — HMAC and audit design