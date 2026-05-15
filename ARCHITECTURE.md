# Vyrox — Architecture Overview

> **Document:** `vyrox-docs/ARCHITECTURE.md`
> **Version:** 0.3.0
> **Last Updated:** 2026-05-15
> **Visibility:** Public

---

## Table of Contents

1. [What Vyrox Is](#1-what-vyrox-is)
2. [The Service Model](#2-the-service-model)
3. [The Pipeline](#3-the-pipeline)
4. [Component Overview](#4-component-overview)
5. [The Open-Core Model](#5-the-open-core-model)
6. [Security Design](#6-security-design)
7. [SLA & Operational Commitments](#7-sla--operational-commitments)
8. [Design Decisions](#8-design-decisions)
9. [Integrating with Vyrox](#9-integrating-with-vyrox)
10. [$1M ARR Growth Strategy](#10-1m-arr-growth-strategy)

---

## 1. What Vyrox Is

Vyrox is a **Managed Detection and Response (MDR) service** built on an AI-native operations model. You forward your CrowdStrike, SentinelOne, or Microsoft Defender alerts to us. We triage them, resolve the ones that can be resolved automatically, escalate the ones that require a human decision, and close every alert inside your SLA — with a complete audit trail of every action taken.

The problem it solves: a typical SOC analyst handles 150–300 alerts per shift. Upward of 70% are false positives they can identify on sight. The remaining 30% are split between low-severity noise and the genuine incidents that matter. Traditional MSSPs charge you for headcount to process all of it. Vyrox uses an AI triage pipeline to handle the volume automatically, which means our analysts spend their time on the 12 alerts per shift that actually require human judgment — not the 288 that don't.

**The result:** same SLA as a 50-person MSSP, at one-third the price, with faster mean time to detection and no billable-hours padding.

**Pricing:** per endpoint per month. No per-alert fees, no surge pricing, no professional services minimums.

---

## 2. The Service Model

Vyrox operates as a fully managed Tier-1 SOC. You retain ownership of your endpoints and your EDR platform. We operate on top of it.

### What you send us

Webhook events from your EDR console — the same events your current MSSP or in-house team receives. No agent, no sensor, no additional software installed on your endpoints. A CrowdStrike or SentinelOne webhook configuration takes approximately 5 minutes to set up.

### What we do

We ingest every alert, run it through a two-stage triage pipeline (deterministic heuristics first, LLM second for ambiguous cases), and produce a verdict within seconds. For CRITICAL and HIGH alerts, your designated analyst receives an interactive Discord notification with the alert summary, MITRE ATT&CK mapping, AI reasoning, and three options: approve a containment action, deny it, or request deeper investigation.

For LOW alerts above a configurable confidence threshold, containment can be automated with your explicit opt-in.

Every action we take — or decline to take — is permanently recorded in an append-only audit log. Nothing happens silently.

### What you keep

Full control. The containment proxy (`vyrox-proxy`) is open-source, MIT licensed, and runs in your environment or ours. You can read the code that executes actions on your infrastructure. You can pull the audit log at any time. You can revoke our access in under 60 seconds.

### Pricing model

| Tier | Endpoints | Price |
|---|---|---|
| Startup | Up to 250 | $8 / endpoint / month |
| Growth | 250–2,500 | $6 / endpoint / month |
| Enterprise | 2,500+ | Custom |

All tiers include: unlimited alert volume, 15-minute SLA for CRITICAL alerts, full audit log access, Discord-based analyst interface, and CrowdStrike + SentinelOne + Defender support.

---

## 3. The Pipeline

```
[Your EDR Platform]
 CrowdStrike   SentinelOne   Microsoft Defender
      │               │               │
      └───────────────┼───────────────┘
                      ▼
         ┌────────────────────────┐
         │    Ingestion Layer     │  HMAC-verified webhook
         │    POST /webhook       │  Normalises vendor schemas
         └────────────┬───────────┘
                      │
                      ▼
         ┌────────────────────────┐
         │     Message Queue      │  Decouples ingestion from processing
         └────────────┬───────────┘
                      │
                      ▼
         ┌────────────────────────┐
         │       AI Worker        │
         │                        │
         │   ┌────────────────┐   │
         │   │   Stage 1      │   │  Deterministic triage — <5ms, free, explainable
         │   │   Heuristics   │   │  Covers 80%+ of alert volume
         │   └──────┬─────────┘   │
         │          │ if ambiguous │
         │   ┌──────▼─────────┐   │
         │   │   Stage 2      │   │  LLM triage for ambiguous cases only
         │   │   LLM Triage   │   │  Structured verdict + one-sentence reasoning
         │   └──────┬─────────┘   │
         └──────────┼─────────────┘
                    │ verdict: CRITICAL | HIGH | MEDIUM | LOW | BENIGN
                    ▼
         ┌────────────────────────┐
         │      Database          │  Alert state, verdicts, action history
         └────────────┬───────────┘
                      │ if CRITICAL or HIGH
                      ▼
         ┌────────────────────────┐
         │     Discord Bot        │  Interactive alert embed, per-tenant channel
         │                        │  [APPROVE] [DENY] [INVESTIGATE]
         └────────────┬───────────┘
                      │ human approves
                      ▼
         ┌────────────────────────┐
         │   Containment Proxy    │  Open-source, MIT licensed, publicly auditable
         │   (vyrox-proxy)        │  HMAC-verified, rate-limited
         └────────────┬───────────┘
                      │
               ┌──────┴──────┐
               ▼             ▼
           EDR API       Audit Log
           (action)    (append-only,
                        every action
                        permanently
                        recorded)
```

### Stage 1 — Heuristics Engine

The first triage stage is deterministic. It runs a set of pattern-based rules derived from real-world red team TTPs and public threat intelligence. No LLM dependency. Verdict in under 5ms.

Alerts that score above a high-confidence threshold are classified immediately. Alerts that score below a low-confidence threshold are classified as benign and closed. Only the ambiguous middle band proceeds to Stage 2.

This design keeps the LLM reserved for cases where pattern matching alone is insufficient — keeping operating costs near zero at early scale and keeping every high-confidence decision explainable without reference to a model.

### Stage 2 — LLM Triage

Ambiguous alerts are passed to a small language model with a structured system prompt focused on security triage. The model returns a verdict, a confidence score, and a one-sentence reasoning string. The reasoning is surfaced in the Discord embed so your analyst can evaluate the AI's logic before approving any action.

The LLM produces a recommendation. A human approves or denies it. The LLM never directly triggers execution.

### Human-in-the-Loop

Every CRITICAL and HIGH verdict generates an interactive Discord embed in your designated channel. The analyst sees the alert summary, triage reasoning, MITRE ATT&CK tactic, and the recommended containment action before making any decision.

Three options are always available:
- **Approve** — sends a signed execution request to the containment proxy
- **Deny** — closes the alert, logs the decision
- **Investigate** — opens the full raw alert payload for deeper review before deciding

LOW severity alerts above a configurable confidence threshold can be set to auto-approve. This is off by default and requires explicit opt-in per tenant.

---

## 4. Component Overview

| Component | Technology | Purpose |
|---|---|---|
| Ingestion webhook | Python, FastAPI | Receives and validates EDR webhook payloads |
| Message queue | Redis | Decouples ingestion from triage worker |
| AI worker | Python | Orchestrates the two-stage triage pipeline |
| Heuristics engine | Python | Stage 1 — deterministic pattern-based triage |
| LLM client | Python | Stage 2 — LLM triage for ambiguous alerts |
| Database | PostgreSQL (managed) | Persists alert state, verdicts, action history |
| Discord bot | Python, py-cord | Human approval interface, per-tenant channels |
| Containment proxy | Rust (Axum) | Executes approved actions against EDR APIs |
| Audit log | Append-only JSONL | Permanent record of every action |
| Tenant dashboard | Next.js | Read-only SOC metrics and alert history per tenant |

### Public Repositories

| Repository | Purpose |
|---|---|
| `vyrox-proxy` | Containment proxy — MIT licensed, fully auditable |
| `vyrox-docs` | Architecture, API reference, security whitepaper |
| `vyrox-landing` | Marketing site |
| `vyrox-simulator` | Alert simulation scripts for integration testing and demos |
| `.github` | Organisation profile, security policy, responsible disclosure |

### Private Repositories

The triage intelligence, multi-tenant infrastructure, detection patterns, red team playbooks, and customer data are maintained in private repositories. The open-core model is intentional: the execution layer that touches your endpoints is public and auditable. The detection intelligence that makes triage decisions is proprietary — that is the operational moat that lets a small team operate at the scale of a 50-person MSSP.

---

## 5. The Open-Core Model

The containment proxy (`vyrox-proxy`) is MIT licensed and publicly available on GitHub.

This is a deliberate trust decision, not a marketing one. The proxy is the component that executes actions on your infrastructure — isolating hosts, killing processes, quarantining network access. Before any security team allows an external service to execute containment actions on their endpoints, they should be able to read the code that does it.

The proxy does one thing: it receives a cryptographically signed instruction from the Vyrox backend, verifies it, rate-limits it, executes the corresponding EDR API call, and writes an audit entry. There is no intelligence in the proxy. It cannot initiate actions. It only responds to verified, human-approved requests.

What remains proprietary is the detection intelligence — the heuristics patterns, the triage logic, the red team knowledge encoded in the classification engine, and the operational infrastructure that runs a multi-tenant MDR service. That is the moat. Not the execution plumbing.

---

## 6. Security Design

### HMAC-SHA256 Request Signing

Every request between Vyrox services — from the ingestion webhook to the worker, and from the Discord bot to the proxy — is signed with HMAC-SHA256 using a shared secret. Unsigned requests are rejected at the boundary before any processing occurs.

The proxy adds replay protection: requests with an approval timestamp older than 30 seconds are rejected with HTTP 410. A captured request cannot be replayed later to trigger an unintended action.

### Append-Only Audit Log

Every action executed by the proxy is written to an append-only JSONL audit log with SHA-256 chaining (each entry includes the hash of the previous entry). The log records the action type, the target host, the alert that triggered it, the analyst who approved it, the timestamp, and the EDR vendor response.

The log is never modified or deleted by application code. Tenants can export their full audit log at any time via the dashboard or API. It is the authoritative source of truth for post-incident review, compliance reporting, and SOC 2 audit evidence.

### Rate Limiting

The proxy enforces a per-tenant rate limit on execution requests. This prevents a misconfiguration or compromised credential from triggering a large number of containment actions in a short window.

### Human Approval by Default

The system requires explicit human approval for all CRITICAL and HIGH severity actions. Auto-approval is available only for LOW severity alerts above a high confidence threshold, requires explicit per-tenant configuration, and is always recorded in the audit log with the same detail as manually approved actions.

No action is ever taken without being logged. There is no silent execution path.

### Tenant Isolation

Every alert, verdict, action, and audit entry is scoped to a `tenant_id`. Tenant data is isolated at the database level. API keys are per-tenant. Discord channels are per-tenant. A misconfiguration in one tenant's pipeline cannot affect another's.

### Webhook Signature Verification

Incoming webhooks from CrowdStrike, SentinelOne, and Microsoft Defender are verified against their respective signing mechanisms before the payload is parsed. Payloads that fail verification are rejected immediately and logged. They never enter the triage pipeline.

---

## 7. SLA & Operational Commitments

| Metric | Commitment |
|---|---|
| CRITICAL alert triage | < 15 minutes from ingestion to Discord embed |
| HIGH alert triage | < 30 minutes from ingestion to Discord embed |
| Service uptime | 99.9% monthly (ingestion + triage + notification) |
| Audit log availability | 100% — logs are customer-owned and exportable at any time |
| False positive rate | < 5% on containment actions (tracked per tenant, published in dashboard) |
| Analyst response time | < 5 minutes for human escalations during covered hours |

SLA credits are issued automatically for breaches. Full SLA terms are in [SLA.md](./SLA.md).

---

## 8. Design Decisions

### Why Rust for the proxy?

The proxy is the only component that executes actions on customer infrastructure. Memory safety is a genuine security requirement here, not a preference. Rust provides memory safety without a garbage collector — no GC pauses during time-sensitive containment actions. The binary is small, starts fast, and has a minimal attack surface.

Publishing the proxy as MIT-licensed code is an argument to CISOs: "The code that touches your endpoints is public, memory-safe, and carries no hidden dependencies."

### Why a two-stage triage pipeline?

A pure LLM approach has three problems in a security context: it is slow, it is expensive at scale, and its decisions are not auditable without careful prompt engineering. A pure rules-based approach handles known TTPs well but misses novel or ambiguous signals.

The two-stage design captures the strengths of both. The heuristics engine handles clear cases quickly, cheaply, and with full explainability. The LLM handles ambiguous cases where pattern matching alone is insufficient. The result is a system that is fast, cost-efficient, and produces human-readable reasoning for every verdict — which is what you need when an analyst has 60 seconds to make a containment decision.

### Why managed service instead of self-hosted software?

Self-hosted security software creates operational burden on the customer: deployment, upgrades, tuning, on-call rotation. The customers who need this product most — Series A companies and mid-market enterprises without a dedicated security team — do not want to operate it. They want the outcome: their alerts handled, their SLA met, their compliance requirements documented. The managed service model delivers that, and it creates a structural advantage: every alert we triage makes our heuristics and LLM prompts better, which benefits every customer simultaneously. A self-hosted model cannot do that.

### Why human-in-the-loop for execution?

SOC teams have been burned by automation that acted on false positives. Isolating a production host or killing a process based on a wrong verdict is a significant operational incident. The human approval step is not a limitation of the technology — it is a feature. It is what allows a security team to trust the system enough to use it in production.

The goal is not to remove humans from the loop. The goal is to reduce the number of decisions a human needs to make from 300 per shift to the 12 that actually require their judgment — and make those 12 decisions faster and better-informed than any current alternative.

### Why per-endpoint pricing?

Per-alert pricing creates an adversarial relationship: customers want fewer alerts, we'd earn less if we resolve them faster. Per-endpoint pricing aligns incentives: we earn more as customers grow, and we're incentivised to resolve alerts as efficiently as possible because our operating costs scale with alert volume, not headcount. It also makes budgeting predictable — a CISO can tie the cost directly to the number they already report: endpoints under management.

---

## 9. Integrating with Vyrox

Integration requires three things: a webhook configured in your EDR console, a Discord bot installed in your server, and a one-time onboarding call to configure your alert routing preferences and containment policies.

**Integration time for a CrowdStrike tenant: approximately 15 minutes.**

The full integration guide is in [QUICKSTART.md](./QUICKSTART.md).

The webhook payload schema for CrowdStrike, SentinelOne, and Microsoft Defender is documented in [API_REFERENCE.md](./API_REFERENCE.md).

The security architecture, HMAC design, and audit log specification are covered in [SECURITY_WHITEPAPER.md](./SECURITY_WHITEPAPER.md).

The containment proxy source code is at [github.com/vyrox-security/vyrox-proxy](https://github.com/vyrox-security/vyrox-proxy).

---

## 10. $1M ARR Growth Strategy

Vyrox targets $1M ARR within 4 years through a phased growth model. The strategy combines direct sales with channel partnerships to reach the mid-market at scale.

### Revenue Targets

| Year | Target ARR | Endpoints (at $6/endpoint) | Key Milestone |
|------|------------|---------------------------|---------------|
| 1 | $500K | ~8,300 | Product-market fit, first 20 pilot customers |
| 2 | $750K | ~12,500 | Self-serve onboarding live, NPS > 40 |
| 3 | $1M | ~16,700 | MSP channel active, 100+ customers |

### Growth Levers

**1. Self-Serve Onboarding (Year 2)**
- API-first architecture allowing programmatic integration
- No sales call required for standard integrations
- Automated provisioning and configuration
- Target: 80% of new customers onboard without human interaction

**2. MSP Channel Strategy (Year 3)**
- White-label option for Managed Service Providers
- Wholesale pricing: 50% of retail price for MSPs
- Multi-tenant dashboard for MSP management
- Target: 30% of revenue from channel by Year 4

**3. Product-Led Growth**
- Free tier for startups (< 50 endpoints)
- Usage-based upsell triggers
- In-app upgrade paths
- Self-serve customer support portal

**4. Expansion Revenue**
- Land-and-expand model within accounts
- Endpoint growth tracked monthly
- Proactive upsell when customer hits tier thresholds

### Scaling Architecture Requirements

To support $1M ARR and beyond, the architecture must handle:

| Requirement | Specification |
|-------------|---------------|
| Customer count | 200+ tenants |
| Alert volume | 10M+ alerts/month |
| API response time | < 200ms p99 |
| Multi-region | US + EU data residency |
| Uptime | 99.95% SLA |

The system is designed for horizontal scaling through:
- Stateless API services behind load balancers
- Redis cluster for queue and cache
- Database read replicas for reporting
- CDN for static assets and documentation

---

*Questions or issues? Open an issue in [vyrox-security/.github](https://github.com/vyrox-security/.github) or contact us at security@vyrox.dev.*
