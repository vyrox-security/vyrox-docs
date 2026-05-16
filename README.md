![Vyrox Docs Banner](assets/vyrox-docs-banner.png)

# Your AI Security Copilot

> **Vyrox is an AI Security Copilot that runs your SOC 24/7.** We automatically triage alerts, surface critical incidents in Discord, and handle containment — so you don't have to.

[![Open Source: vyrox-proxy](https://img.shields.io/badge/Open%20Source-vyrox--proxy-blue?style=flat-square)](https://github.com/vyrox-security/vyrox-proxy)
[![License: MIT](https://img.shields.io/badge/License-MIT-green?style=flat-square)](https://github.com/vyrox-security/vyrox-proxy/blob/main/LICENSE)
[![Status: Alpha](https://img.shields.io/badge/Status-Alpha-orange?style=flat-square)](#design-partners)

---

## What Vyrox Does

Vyrox is your 24/7 AI security operations team. We don't just triage alerts — we run your complete security operations.

```
[Data Sources]                    [Three-Layer Operations]
    │                                    │
[EDR + Vuln Scanners + Cloud APIs]     │
    │                                    ▼
    │              ┌─────────────────────────────────────┐
    │              │         VYROX AI SECURITY COPILOT     │
    │              │                                      │
    │              │  Layer 1: Always-On (Autonomous)     │
    │              │  • Continuous monitoring             │
    │              │  • Vulnerability surface map         │
    │              │  • Automated response playbooks      │
    │              │  • Compliance evidence               │
    │              │                                      │
    │              │  Layer 2: Assisted (AI + Human)     │
    │              │  • Complex investigation             │
    │              │  • Weekly AI security briefings     │
    │              │  • Security posture recommendations  │
    │              │                                      │
    │              │  Layer 3: Escalated (Human Expert) │
    │              │  • Critical incidents                │
    │              │  • Strategic advisory                │
    │              │  • Board-level reporting             │
    │              └─────────────────────────────────────┘
    │                      │
    ▼                      ▼
[Audit Log]           [vyrox-proxy]
(Append-only,         (MIT licensed,
SHA-256 chained)       publicly auditable)
```

**The promise:** "We'll run your security operations the way a $500K/year SOC team would — for a fraction of that cost."

---

## Key Properties

| Property | Detail |
|---|---|
| 24/7 Coverage | Always-on, not just business hours |
| Proactive Hunting | Find attackers before they act |
| Integration time | ~15 minutes (webhook + Discord) |
| EDR support | CrowdStrike, SentinelOne, Microsoft Defender |
| Human approval | Required for critical — automated for low-risk |
| Audit log | Append-only JSONL, SHA-256 chained, customer-exportable |
| Execution layer | Open-source, MIT licensed, publicly auditable |

---

## Pricing Tiers

Multiple tiers available to match company size and security needs. Contact hello@vyrox.dev for details.

---

## Open-Core Model

**What is public:**
- `vyrox-proxy` — The Rust proxy that executes containment. Read the code that touches your infrastructure.
- `vyrox-docs` — Architecture, API reference, integration guide.
- `vyrox-simulator` — Alert simulation scripts for testing.

**What is private:**
- Heuristics engine — Detection patterns and scoring logic.
- LLM prompt templates — Tuning for triage decisions.
- Multi-tenant infrastructure.

The split is intentional: the execution layer is auditable; the intelligence is proprietary.

---

## Quick Start

### 1. Run the alert simulator

```bash
git clone https://github.com/vyrox-security/vyrox-simulator
cd vyrox-simulator
pip install -r requirements.txt

# Mimikatz credential dump — should classify as CRITICAL
python simulate_crowdstrike_alert.py --scenario mimikatz

# Benign sysadmin activity — should classify as BENIGN, no Discord message
python simulate_crowdstrike_alert.py --scenario benign
```

### 2. Read the proxy code

```bash
git clone https://github.com/vyrox-security/vyrox-proxy
cd vyrox-proxy
cargo run -- --help
```

The proxy receives signed instructions, verifies HMAC, rate-limits, executes the EDR API call, and writes an audit entry. That's all it does.

### 3. Read the architecture

Full architecture documentation: [ARCHITECTURE.md](./ARCHITECTURE.md)

---

## Design Partners

Vyrox is in alpha. We are accepting design partners who want to be first to experience the AI Security Copilot.

**What you get:**
- 3 months free (Starter tier)
- Direct line to the founding team
- Product roadmap shaped by your feedback

**What we ask:**
- Honest feedback
- Anonymized metrics in case studies
- A 30-minute call every 2 weeks

**You qualify if:**
- Run CrowdStrike, SentinelOne, or Microsoft Defender
- Handle 100+ alerts per day
- Want 24/7 security operations, not just alert triage

Apply: hello@vyrox.dev (subject: "design partner")

---

## Repository Overview

| Repo | Visibility | Description |
|------|------------|-------------|
| [vyrox](https://github.com/vyrox-security/vyrox) | 🔒 Private | Core pipeline: ingestion, triage, approval |
| [vyrox-proxy](https://github.com/vyrox-security/vyrox-proxy) | 🌐 Public (MIT) | Containment proxy |
| [vyrox-docs](https://github.com/vyrox-security/vyrox-docs) | 🌐 Public | Architecture, API reference, this site |
| [vyrox-simulator](https://github.com/vyrox-security/vyrox-simulator) | 🌐 Public (MIT) | Alert simulation scripts |
| [vyrox-landing](https://github.com/vyrox-security/vyrox-landing) | 🌐 Public | Marketing site |

Private repos: `vyrox-heuristics` (detection engine), `vyrox-deploy` (infra), `vyrox-design-partners` (CRM).

---

## Security

Found a vulnerability? Do not open a public issue. Email: **sec.vyrox@proton.me**

Response SLA: acknowledgement within 48h, initial triage within 7 days, patch timeline within 14 days.

PGP key: [vyrox.dev/.well-known/pgp-key.txt](https://vyrox.dev/.well-known/pgp-key.txt)

Full security policy: [SECURITY.md](./SECURITY.md)

---

## License

`vyrox-proxy` and `vyrox-simulator` are MIT licensed.

`vyrox-docs`, `vyrox-landing`, `vyrox-heuristics`, `vyrox-deploy`, `vyrox-design-partners`, and the `vyrox` monorepo are proprietary.

---

*Vyrox Security, Inc. — hello@vyrox.dev*
