# Vyrox Development Log

This document serves as our public build journal. While the main architecture documentation describes the system as it stands, this log describes how we got here. Building in public is a trust exercise. We intend to be transparent about our technical decisions, the trade-offs we accept, and the occasional 2am mistakes we make.

## 2026-04-26: Day 1 - Ingestion Pipeline Foundation

We started where all good security tools start: ingesting telemetry without dropping it. The goal for Day 1 was simple: build a webhook endpoint for CrowdStrike and SentinelOne, verify their signatures securely, and push them to a Redis queue.

**Decisions Made:**
*   **HMAC-SHA256 for CrowdStrike:** We opted for a strict 32-byte hex secret requirement to ensure entropy. Constant-time equality checks are enforced via `hmac.compare_digest` because timing attacks are real, even on webhooks.
*   **Replay Protection:** We implemented a 30-second window check for incoming requests. If an attacker captures a payload, they have half a minute to use it.
*   **Async Queueing:** We used an Upstash Redis queue via `redis-py` asyncio to ensure the FastAPI worker never blocks. Webhooks must return `202 Accepted` immediately.

**Lessons Learned:**
*   Mocking Redis for testing is straightforward until you start using specific pipeline mechanics. We used `fakeredis` to keep our CI fast and stateless while retaining confidence in our queuing logic.
*   Pydantic V2 `BaseSettings` is incredibly strict, which is exactly what we want. The service will aggressively refuse to start if the environment is misconfigured. Fail early, fail loudly.

## What's Next?

With telemetry successfully landing in our queue, the next challenge is triaging it. We are moving onto the Python background worker that will pull these alerts, run them through our deterministic heuristics engine, and orchestrate the LLM triage for ambiguous cases. 

Expect fewer webhooks and more logic trees in the next update.
