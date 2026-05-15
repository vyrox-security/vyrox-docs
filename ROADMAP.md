# Vyrox Product Roadmap

> **Document:** `vyrox-docs/ROADMAP.md`
> **Version:** 1.0.0
> **Last Updated:** 2026-05-15
> **Visibility:** Public

---

## Vision

Build the most efficient AI-native Managed Detection and Response (MDR) service that delivers enterprise-grade security at a fraction of traditional MSSP costs.

---

## Guiding Principles

1. **Automation-first**: Automate everything that can be automated; humans decide only on exceptions
2. **Transparency**: Open-source the execution layer; keep intelligence proprietary
3. **Customer outcomes**: Measure success by MTTD, MTTR, and false positive rate — not features shipped
4. **Bootstrapped growth**: Sustainable unit economics from day one; profit beforeVC

---

## Roadmap Phases

### Phase 1: Foundation (Q1 2026)

**Goal**: Prove the core pipeline works in production

| Feature | Status | Description |
|---------|--------|-------------|
| Multi-EDR ingestion | ✅ Done | CrowdStrike, SentinelOne, Microsoft Defender webhooks |
| Heuristics engine | ✅ Done | Deterministic pattern matching, < 5ms per alert |
| LLM triage | ✅ Done | OpenRouter integration for ambiguous alerts |
| Discord integration | ✅ Done | Real-time alert notifications, approval workflows |
| Containment proxy | ✅ Done | vyrox-proxy (MIT licensed), auto-remediation |

**Q1 2026 Deliverables**:
- [ ] Production-ready multi-tenant deployment
- [ ] Customer dashboard v1 (alert timeline, metrics)
- [ ] SOC 2 Type I certification
- [ ] 10+ pilot customers

---

### Phase 2: Scale (Q2 2026)

**Goal**: Product hardening and operational excellence

| Feature | Status | Description |
|---------|--------|-------------|
| Auto-remediation expand | 🔄 In Progress | Network quarantine, user suspension |
| Self-serve onboarding | 📋 Planned | No founder needed to onboard customers |
| Compliance reports | 📋 Planned | SOC 2, HIPAA audit log exports |
| MSP channel | 📋 Planned | White-label option for MSPs |

**Q2 2026 Deliverables**:
- [ ] 20+ paying customers
- [ ] Full self-serve onboarding
- [ ] Enterprise tier with SLA guarantees
- [ ] Automated compliance reporting

---

### Phase 3: Growth (Q3-Q4 2026)

**Goal**: Accelerate customer acquisition and expand capabilities

| Feature | Status | Description |
|---------|--------|-------------|
| Vertical templates | 📋 Planned | Industry-specific detection patterns |
| API-first architecture | 📋 Planned | Programmatic access for advanced customers |
| Threat intelligence | 📋 Planned | Integrated threat feeds |
| EU data residency | 📋 Planned | EU region deployment option |

**Q4 2026 Deliverables**:
- [ ] 50+ customers
- [ ] Multi-region support (US + EU)
- [ ] SOC 2 Type II certification
- [ ] Partner ecosystem (MSPs, integrators)

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