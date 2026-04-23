# Vyrox — Architecture Overview

> **Document:** `vyrox-docs/ARCHITECTURE.md`
> **Version:** 0.1.0
> **Last Updated:** 2026-04-23
> **Visibility:** Public

---

## Table of Contents

1. [What Vyrox Does](#1-what-vyrox-does)
2. [The Pipeline](#2-the-pipeline)
3. [Component Overview](#3-component-overview)
4. [The Open-Core Model](#4-the-open-core-model)
5. [Security Design](#5-security-design)
6. [Design Decisions](#6-design-decisions)
7. [Integrating with Vyrox](#7-integrating-with-vyrox)

---

## 1. What Vyrox Does

Vyrox is an autonomous AI SOC analyst. It ingests security alerts from EDR platforms, triages them through a two-stage pipeline, and surfaces only the alerts that require a human decision — with a one-click approval flow and a complete audit trail of every action taken.

The problem it solves: a typical SOC analyst handles 150–300 alerts per shift. Upward of 70% are false positives they can identify on sight. Vyrox handles that 70% automatically, so analysts spend their time on the threats that actually matter.

**The pipeline in four words:** Ingest → Triage → Approve → Execute.

---

## 2. The Pipeline

```
[EDR Vendors]
 CrowdStrike   SentinelOne
      │               │
      └──────┬─────────┘
             ▼
  ┌──────────────────────┐
  │   Ingestion Layer    │  HMAC-verified webhook
  │   POST /webhook      │  Normalises vendor schemas
  └──────────┬───────────┘
             │
             ▼
  ┌──────────────────────┐
  │     Message Queue    │  Decouples ingestion from processing
  └──────────┬───────────┘
             │
             ▼
  ┌──────────────────────┐
  │      AI Worker       │
  │                      │
  │   ┌──────────────┐   │
  │   │  Stage 1     │   │  Deterministic triage — fast, free, explainable
  │   │  Heuristics  │   │  Covers 80%+ of alert volume
  │   └──────┬───────┘   │
  │          │ if ambiguous
  │   ┌──────▼───────┐   │
  │   │  Stage 2     │   │  LLM triage for ambiguous cases only
  │   │  LLM Triage  │   │  Structured verdict output
  │   └──────┬───────┘   │
  └──────────┼───────────┘
             │ verdict: CRITICAL | HIGH | MEDIUM | LOW | BENIGN
             ▼
  ┌──────────────────────┐
  │      Database        │  Persists alerts, verdicts, action history
  └──────────┬───────────┘
             │ if CRITICAL or HIGH
             ▼
  ┌──────────────────────┐
  │      Slack Bot       │  Interactive alert card
  │                      │  [APPROVE] [DENY] [INVESTIGATE]
  └──────────┬───────────┘
             │ human approves
             ▼
  ┌──────────────────────┐
  │  Containment Proxy   │  Open-source, MIT licensed, publicly auditable
  │  (vyrox-proxy)       │  HMAC-verified, rate-limited
  └──────────┬───────────┘
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

The first triage stage is deterministic. It runs a set of pattern-based rules derived from real-world red team TTPs and public threat intelligence. It has no dependency on an LLM and produces a verdict in under 5ms.

Alerts that score above a high-confidence threshold are classified immediately — no LLM call required. Alerts that score below a low-confidence threshold are classified as benign and closed. Only the ambiguous middle band proceeds to Stage 2.

This design means the LLM is used sparingly — reserved for the genuinely uncertain cases. It keeps costs near zero at early scale and keeps every high-confidence decision explainable without reference to a model.

### Stage 2 — LLM Triage

Ambiguous alerts are passed to a small language model with a structured system prompt focused on security triage. The model returns a verdict, a confidence score, and a one-sentence reasoning string. The reasoning is surfaced to the analyst in the Slack card so they can evaluate the AI's logic before approving any action.

The LLM is never used for execution decisions. It produces a recommendation. A human approves or denies it.

### Human-in-the-Loop

Every CRITICAL and HIGH verdict generates an interactive Slack message. The analyst sees the alert summary, the triage reasoning, the MITRE ATT&CK tactic, and the recommended containment action before making any decision.

Three options are always available:
- **Approve** — sends a signed execution request to the containment proxy
- **Deny** — closes the action, logs the decision
- **Investigate** — opens the full raw alert payload for deeper review before deciding

LOW severity alerts above a configurable confidence threshold can be set to auto-approve. This is off by default and requires explicit opt-in per tenant.

---

## 3. Component Overview

| Component | Technology | Purpose |
|---|---|---|
| Ingestion webhook | Python, FastAPI | Receives and validates EDR webhook payloads |
| Message queue | Redis | Decouples ingestion from triage worker |
| AI worker | Python | Orchestrates the two-stage triage pipeline |
| Heuristics engine | Python | Stage 1 — deterministic pattern-based triage |
| LLM client | Python | Stage 2 — LLM triage for ambiguous alerts |
| Database | SQLite | Persists alert state, verdicts, action history |
| Slack bot | Python, Slack Bolt | Human approval interface |
| Containment proxy | Rust (Axum) | Executes approved actions against EDR APIs |
| Audit log | Append-only JSONL | Permanent record of every action |

### Public Repositories

| Repository | Purpose |
|---|---|
| `vyrox-proxy` | Containment proxy — MIT licensed, fully auditable |
| `vyrox-docs` | Architecture, API reference, security whitepaper |
| `vyrox-landing` | Marketing site |
| `vyrox-simulator` | Alert simulation scripts for integration testing |
| `.github` | Organisation profile, security policy, issue templates |

### Private Repositories

The triage intelligence, infrastructure configuration, red team test cases, and design partner data are maintained in private repositories. The open-core model is intentional: the execution layer that touches your endpoints is public and auditable. The detection intelligence that makes triage decisions is proprietary.

---

## 4. The Open-Core Model

The containment proxy (`vyrox-proxy`) is MIT licensed and publicly available on GitHub.

This is a deliberate trust decision, not a marketing one. The proxy is the component that executes actions on your infrastructure — isolating hosts, killing processes, quarantining network access. Before any security team allows an external tool to execute containment actions on their endpoints, they should be able to read the code that does it.

The proxy does one thing: it receives a cryptographically signed instruction from the Vyrox backend, verifies it, rate-limits it, executes the corresponding EDR API call, and writes an audit entry. There is no intelligence in the proxy. It cannot initiate actions. It only responds to verified, human-approved requests.

What remains proprietary is the detection intelligence — the heuristics patterns, the triage logic, the red team knowledge encoded in the classification engine. That is the moat, not the execution plumbing.

---

## 5. Security Design

### HMAC-SHA256 Request Signing

Every request between Vyrox services — from the ingestion webhook to the worker, and from the Slack bot to the proxy — is signed with HMAC-SHA256 using a shared secret. Unsigned requests are rejected at the boundary before any processing occurs.

The proxy adds replay protection: requests with an approval timestamp older than 30 seconds are rejected with HTTP 410. This means a captured request cannot be replayed later to trigger an unintended action.

### Append-Only Audit Log

Every action executed by the proxy is written to an append-only JSONL audit log. The log records the action type, the target host, the alert that triggered it, the analyst who approved it, the timestamp, and the EDR vendor response.

The log is never modified or deleted by application code. It is the source of truth for post-incident review, compliance reporting, and SOC 2 audit evidence.

### Rate Limiting

The proxy enforces a per-tenant rate limit on execution requests. This prevents a misconfiguration or compromised credential from triggering a large number of containment actions in a short window.

### Human Approval by Default

The system is designed to require explicit human approval for all CRITICAL and HIGH severity actions. Auto-approval is available only for LOW severity alerts above a high confidence threshold, requires explicit configuration, and is always recorded in the audit log with the same detail as manually approved actions.

No action is ever taken without being logged. There is no silent execution path.

### Webhook Signature Verification

Incoming webhooks from CrowdStrike and SentinelOne are verified against their respective signing mechanisms before the payload is parsed. Payloads that fail verification are rejected immediately and logged. They never enter the triage pipeline.

---

## 6. Design Decisions

### Why Rust for the proxy?

The proxy is the only component in the system that executes actions on customer infrastructure. Memory safety is a genuine security requirement here, not a preference. Rust provides memory safety without a garbage collector, which means no GC pauses during time-sensitive containment actions. The binary is small, starts fast, and has a minimal attack surface.

The decision to write the proxy in Rust and publish it as MIT-licensed code is also an argument to CISOs: "The code that touches your endpoints is public, memory-safe, and carries no hidden dependencies."

### Why a two-stage triage pipeline?

A pure LLM approach has three problems in a security context: it is slow, it is expensive at scale, and its decisions are not easily auditable. A pure rules-based approach covers known TTPs well but struggles with novel or ambiguous signals.

The two-stage design captures the strengths of both. The heuristics engine handles the clear cases quickly, cheaply, and with full explainability. The LLM handles the ambiguous cases where pattern matching alone is insufficient. The result is a system that is fast, cost-efficient, and produces human-readable reasoning for every verdict.

### Why human-in-the-loop for execution?

SOC teams have been burned by automation that acted on false positives. Isolating a production host or killing a process based on a wrong verdict is a significant operational incident. The human approval step is not a limitation of the technology — it is a feature. It is what allows a security team to trust the system enough to deploy it in production.

The goal is not to remove humans from the loop. The goal is to reduce the number of decisions a human needs to make from 300 per shift to the 12 that actually require their judgment.

### Why SQLite?

For a single-tenant deployment at early scale, SQLite is the correct choice. It is zero-operational-overhead, version-controlled, and handles thousands of alert writes per second on a single writer. The ORM layer abstracts the database from the application logic — migration to a client-server database requires a configuration change, not a rewrite.

---

## 7. Integrating with Vyrox

Integration requires three things: a webhook endpoint configured in your EDR console, a Slack app installed in your workspace, and a running instance of the containment proxy.

**Integration time for a CrowdStrike tenant: approximately 15 minutes.**

The full integration guide is in [QUICKSTART.md](./QUICKSTART.md).

The webhook payload schema for CrowdStrike and SentinelOne is documented in [API_REFERENCE.md](./API_REFERENCE.md).

The security architecture, HMAC design, and audit log specification are covered in [SECURITY_WHITEPAPER.md](./SECURITY_WHITEPAPER.md).

---

*Questions or issues? Open an issue in [vyrox-security/.github](https://github.com/vyrox-security/.github) or contact us at the address in our security policy.*