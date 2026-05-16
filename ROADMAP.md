# Vyrox Product Roadmap

> **Document:** `vyrox-docs/ROADMAP.md`
> **Version:** 2.0.0
> **Last Updated:** 2026-05-15
> **Visibility:** Public

---

## Vision

**From MDR to AI Security Copilot** — Vyrox is evolving from an alert triage service to an autonomous security operations platform that runs your SOC 24/7.

**The new promise:** "We'll run your security operations the way a SOC team would — at a fraction of the traditional cost."

---

## Guiding Principles

1. **Autonomous operations**: The goal is 24/7 coverage without human intervention on routine tasks
2. **Automation-first**: Automate everything that can be automated; humans decide only on exceptions
3. **Transparency**: Open-source the execution layer; keep intelligence proprietary
4. **Customer outcomes**: Measure success by security posture improvement — not alerts processed
5. **Bootstrapped growth**: Sustainable unit economics from day one; profit before VC
6. **Outcome-based pricing**: Align on security outcomes, not just monitoring endpoints

---

## Roadmap Phases

### Phase 1: Foundation (Q1-Q2 2026)

**Goal**: Transform from alert triage to continuous monitoring

| Feature | Status | Description |
|---------|--------|-------------|
| Multi-EDR ingestion | ✅ Done | CrowdStrike, SentinelOne, Microsoft Defender webhooks |
| Heuristics engine | ✅ Done | Deterministic pattern matching, < 5ms per alert |
| LLM triage | ✅ Done | OpenRouter integration for ambiguous alerts |
| Discord integration | ✅ Done | Real-time alert notifications, approval workflows |
| Containment proxy | ✅ Done | vyrox-proxy (MIT licensed), auto-remediation |
| Continuous Dashboard | 🔄 In Progress | Security posture overview, not just alerts |
| Vulnerability Surface Map | 📋 Planned | External attack surface scanning |
| Automated Playbook Engine | 🔄 In Progress | Auto-remediate known threats |
| 24/7 Autonomous Mode | 🔄 In Progress | Coverage beyond business hours |
| Compliance Evidence Generator | 📋 Planned | Automated SOC 2/HIPAA evidence |

**Phase 1 Deliverables**:
- [ ] Production-ready multi-tenant deployment
- [ ] Security posture dashboard (not just alert timeline)
- [ ] Vulnerability surface map
- [ ] 5 core automated response playbooks
- [ ] 24/7 autonomous monitoring mode
- [ ] 10+ pilot customers
- [ ] Target: $500K ARR

---

### Phase 2: Expansion (Q3-Q4 2026)

**Goal**: Add capabilities that make it a complete SOC replacement

| Feature | Status | Description |
|---------|--------|-------------|
| Proactive Threat Hunting | 📋 Planned | Find attackers before they act |
| SIEM-Lite Log Aggregation | 📋 Planned | Centralize security events without SIEM complexity |
| Incident Response Orchestration | 📋 Planned | Runbooks, not just alerts |
| Weekly AI Security Briefing | 📋 Planned | Auto-generated threat report |
| Integration Hub | 📋 Planned | 50+ tool integrations |
| Enterprise Tier | 📋 Planned | Custom SLAs, dedicated advisor |

**Phase 2 Deliverables**:
- [ ] Proactive threat hunting (scheduled campaigns)
- [ ] Lightweight log aggregation
- [ ] Incident response playbooks
- [ ] Weekly AI-generated security briefings
- [ ] 20+ paying customers
- [ ] Full self-serve onboarding (80% of customers without human interaction)
- [ ] Enterprise tier with SLA guarantees
- [ ] Target: $1M ARR

---

### Phase 3: Scale (2027+)

**Goal**: Features that make it impossible to operate without

| Feature | Status | Description |
|---------|--------|-------------|
| Board-Level Reporting | 📋 Planned | CISO's #1 pain point — automated |
| MSP Multi-Tenant Dashboard | 📋 Planned | White-label for channel partners |
| API-First Architecture | 📋 Planned | Programmatic everything |
| EU Data Residency | 📋 Planned | GDPR compliance |
| SOC 2 Type II | 📋 Planned | Enterprise-ready certification |

**Phase 3 Deliverables**:
- [ ] 50+ customers
- [ ] MSP channel (30% of revenue)
- [ ] Multi-region support (US + EU)
- [ ] SOC 2 Type II certification
- [ ] Partner ecosystem (MSPs, integrators)
- [ ] Target: $2M ARR

---

## Open Source Contributions

We believe in open-core architecture. The following components are open source and community contributions are welcome:

| Repository | Description | License |
|------------|-------------|---------|
| [vyrox-proxy](https://github.com/vyrox-security/vyrox-proxy) | Rust containment proxy | MIT |
| [vyrox-docs](https://github.com/vyrox-security/vyrox-docs) | Public architecture docs | Proprietary |
| [vyrox-landing](https://github.com/vyrox-security/vyrox-landing) | Product website | Proprietary |

### How to Contribute

1. **vyrox-proxy**: Submit PRs for new EDR integrations, security improvements
2. **Documentation**: Improve clarity in ARCHITECTURE.md, fix typos
3. **Testing**: Report bugs, suggest edge cases

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## What We Keep Private

The following are proprietary and not open source:

- **Heuristics engine** (`vyrox-heuristics`): Detection patterns and ML models
- **LLM prompts**: Tuning and optimization for triage decisions
- **Customer data**: Security operations data is never shared
- **Pricing**: Contact sales for pricing — not published publicly

---

## Release Cadence

| Release Type | Frequency | Examples |
|--------------|------------|----------|
| Patch | As needed | Bug fixes, security patches |
| Minor | Monthly | New integrations, improvements |
| Major | Quarterly | Significant features,架构 changes |

---

## Community

- **Discord**: [Join our community](https://discord.gg/vyrox)
- **Twitter**: [@vyroxsecurity](https://twitter.com/vyroxsecurity)
- **Email**: hello@vyrox.dev

---

## Security

For security vulnerabilities, please see [SECURITY.md](SECURITY.md).

---

*Last updated: 2026-05-15*