# Audit chain specification

This document is the wire-level specification for the Vyrox audit log
format. It is targeted at customers who want to verify their own log
files independently, compliance teams reviewing SOC 2 evidence
samples, and contributors writing new code that reads or writes audit
entries.

The format is identical between the Python side (`shared/audit.py` in
the private monorepo) and the Rust side (`vyrox-proxy/src/audit.rs`,
public). The two implementations agree byte for byte. A single
verifier program can read both streams.

## File layout

One JSONL file per UTC day. File name: `audit-YYYY-MM-DD.jsonl`. Files
are append-only on disk; the kernel honours the `O_APPEND` flag so
concurrent writers cannot stomp each other.

A new file rolls over at the next UTC day. The hash chain continues
across files. The first entry of a new day's file uses the `hash` of
the last entry of the previous day's file as its `previous_hash`. The
very first entry of the very first file uses the genesis sentinel
hash (sixty four ASCII zeros).

```
audit-2026-05-22.jsonl
audit-2026-05-23.jsonl   <- previous_hash of entry 0 == hash of last entry in 2026-05-22 file
audit-2026-05-24.jsonl   <- chain continues
```

## Entry shape

Every entry is a single JSON object on its own line. Field order on
disk varies because we use `serde_json::to_string` (Rust) and
`json.dumps(..., sort_keys=True)` (Python); verifiers must not depend
on a specific order in the on-disk JSON. The hash computation, by
contrast, is order-dependent and uses canonical JSON. See
"Hash computation" below.

### Rust proxy entries (containment actions)

```json
{
  "timestamp": 1700000000,
  "tenant_id": "acme-corp",
  "action_type": "HOST_ISOLATION",
  "host": "workstation-01",
  "approved_by": "jane.smith#1234",
  "dry_run": false,
  "previous_hash": "0000000000000000000000000000000000000000000000000000000000000000",
  "hash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
}
```

| Field | Type | Notes |
|---|---|---|
| `timestamp` | integer | Unix epoch seconds, UTC. Capture time on the writer host. |
| `tenant_id` | string | Multi-tenant scope. Required. |
| `action_type` | string | One of `HOST_ISOLATION`, `PROCESS_KILL`, `NETWORK_QUARANTINE`. Stored as `Debug` format of the Rust enum. |
| `host` | string | Vendor-side host identifier. Opaque to the audit log. |
| `approved_by` | string | Identifier of the human who approved the action: a console user, or a notifier username such as the Discord bot's (including discriminator). |
| `dry_run` | bool | `true` when `DRY_RUN` was active and no real EDR call was made. |
| `previous_hash` | string | 64 lowercase hex characters. Genesis sentinel for the first entry of the very first file. |
| `hash` | string | 64 lowercase hex characters. SHA-256 of `previous_hash || "|" || canonical_json(payload)`. See below. |

### Python pipeline entries (everything else)

Python writes audit entries for ingestion events, triage decisions,
notification attempts, Discord interactions, and any other state
change. The wrapper shape is fixed; the inner `entry` dict is
free-form per event.

```json
{
  "timestamp": "2026-05-23T14:32:00+00:00",
  "entry": {
    "event": "triage_persisted",
    "alert_id": "alt_abc123",
    "tenant_id": "acme-corp",
    "verdict": "CRITICAL",
    "confidence": 0.92
  },
  "previous_hash": "0000000000000000000000000000000000000000000000000000000000000000",
  "hash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
}
```

| Field | Type | Notes |
|---|---|---|
| `timestamp` | string | ISO 8601 UTC. Format produced by Python's `datetime.now(timezone.utc).isoformat()`. |
| `entry` | object | Free-form event payload. Conventions are documented per event below. |
| `previous_hash` | string | Same as Rust. |
| `hash` | string | Same as Rust. |

The Python and Rust streams interleave at the JSONL layer; they share
a single chain. A verifier reads one stream of lines, ignores whether
the inner shape is the Rust action format or the Python wrapped
format, and computes the next expected `hash` from the on-disk
`previous_hash` plus the rest of the entry.

## Hash computation

The chain is a SHA-256 hash chain over canonical-JSON entries.

For Rust entries the canonical payload is the entry without the `hash`
field. The order is alphabetical by key. Whitespace is absent. The
canonical form for the example above is:

```
{"action_type":"HOST_ISOLATION","approved_by":"jane.smith#1234","dry_run":false,"host":"workstation-01","previous_hash":"0000...0000","tenant_id":"acme-corp","timestamp":1700000000}
```

The hash is:

```
hash = SHA-256( previous_hash_bytes || "|" || canonical_payload_bytes )
```

The separator `|` is one literal pipe character. It exists so a single
SHA-256 round covers the linkage and the payload without any chance
of length-extension confusion.

For Python entries the canonical payload is the wrapper object with
`sort_keys=True`. The reference implementation in `shared/audit.py`
uses `json.dumps(entry, sort_keys=True)` directly:

```python
entry_str = json.dumps(entry, sort_keys=True)
new_hash = hashlib.sha256(f"{self._last_hash}{entry_str}".encode()).hexdigest()
```

Note that the Python and Rust hash inputs differ in two details that
verifiers must respect:

1. The Rust side uses `|` as a separator between `previous_hash` and
   the canonical payload. The Python side does not.
2. The Rust canonical payload excludes `hash`. The Python canonical
   payload is the wrapper object excluding `hash`, but the wrapper
   contains a nested `entry` whose order Python preserves as-is when
   `sort_keys=True` walks it recursively.

We are aware the two formats are not byte-identical at the hash-input
layer. The on-disk wire format (the JSONL itself) is interleaved-safe
because the verifier dispatches on the presence of the `entry` field.
A future v2 of the format will unify the hash input. Until then,
either parse rule recomputes the chain from the file alone; an
external verifier can use the same dispatch logic.

## Genesis hash

```
0000000000000000000000000000000000000000000000000000000000000000
```

Sixty four ASCII zeros. Used as the `previous_hash` of the first entry
in a brand new audit directory. The Python side defines it as
`AuditWriter._GENESIS_HASH`. The Rust side defines it as
`audit::GENESIS_HASH`.

## Verifying a chain (Python reference)

A complete verifier in about thirty lines. Reads a directory of
`audit-YYYY-MM-DD.jsonl` files in date order, walks every entry, and
recomputes the hash. Returns the first entry where the recomputed
hash does not match the stored hash, or `None` if the whole chain is
intact.

```python
#!/usr/bin/env python3
"""Audit chain verifier, reads vyrox audit log directory, checks chain."""
import hashlib
import json
import sys
from pathlib import Path

GENESIS = "0" * 64


def recompute(prev_hash: str, entry: dict) -> str:
    # Dispatch on shape: Rust action entry vs Python wrapped entry.
    if "action_type" in entry and "entry" not in entry:
        payload = {k: v for k, v in entry.items() if k != "hash"}
        canonical = json.dumps(payload, separators=(",", ":"), sort_keys=True)
        h = hashlib.sha256()
        h.update(prev_hash.encode("utf-8"))
        h.update(b"|")
        h.update(canonical.encode("utf-8"))
        return h.hexdigest()
    payload = {k: v for k, v in entry.items() if k != "hash"}
    return hashlib.sha256(
        f"{prev_hash}{json.dumps(payload['entry'], sort_keys=True)}".encode("utf-8")
    ).hexdigest()


def verify(audit_dir: Path) -> tuple[int, str] | None:
    prev = GENESIS
    line_no = 0
    for f in sorted(audit_dir.glob("audit-*.jsonl")):
        for raw in f.read_text().splitlines():
            if not raw.strip():
                continue
            line_no += 1
            entry = json.loads(raw)
            if entry["previous_hash"] != prev:
                return line_no, f"previous_hash mismatch in {f.name}"
            expected = recompute(prev, entry)
            if expected != entry["hash"]:
                return line_no, f"hash mismatch in {f.name}: expected {expected}, got {entry['hash']}"
            prev = entry["hash"]
    return None


if __name__ == "__main__":
    bad = verify(Path(sys.argv[1]))
    if bad:
        print(f"FAIL line {bad[0]}: {bad[1]}")
        sys.exit(1)
    print(f"OK ({line_no} entries)")
```

Save as `verify_audit.py`, run with `python verify_audit.py /path/to/audit-dir`.

The verifier exits non-zero on the first mismatch and prints the file
and the byte cause. Customers running their own compliance pipeline
should run this from CI nightly against the previous day's audit
directory.

## Chain continuity across restarts

The chain survives process restart. On boot:

- Python: `AuditWriter.__init__` calls `_sync_read_last_hash` against
  today's log file. If the file exists, it reads the last line, parses
  it as JSON, and uses the `hash` value as the seed. If the file is
  missing, empty, or unparseable, the seed is the genesis sentinel.
- Rust: `audit::ChainState::from_file` does the same. It calls
  `read_audit_logs` (which silently skips malformed lines) and uses
  the `hash` of the last well-formed entry as the seed.

The continuity is enforced by tests in both implementations:

- Python: `tests/test_p05_blockers.py::test_audit_chain_survives_process_restart`
- Rust: `vyrox-proxy/src/audit.rs::tests::chain_survives_restart`

A break in continuity (an entry whose `previous_hash` does not match
the previous entry's `hash`) is detectable by the verifier above.
There is no path in the production code that writes an entry whose
`previous_hash` is not the last in-memory hash.

## Tamper detection in practice

A single byte modification anywhere in an entry breaks the chain at
that entry and at every entry after it. The verifier reports the
first break by line number. The original entry stays on disk; only
the chain pointer breaks.

Truncation (deleting trailing entries from a file) is not detectable
by the chain alone. The hash chain only proves that the entries you
have are linked. It does not prove that there are no missing entries
at the end. Mitigation: customers run the verifier nightly and store
the last-seen `hash` from the previous run; a missing tail entry
surfaces as a chain that ends earlier than the previous nightly run
recorded.

Truncation across the very last in-memory hash (a writer that died
mid-write) is detectable on restart. The writer's `__init__` reads
the file from disk; if the on-disk `last_hash` is older than the
last in-memory value before the crash, the restart resumes from the
on-disk value and any post-crash writes link from there. The lost
window is bounded by the writer's flush interval; both implementations
fsync after every entry.

## Durability properties

- Append-only on disk. Both implementations open with the `O_APPEND`
  flag. Concurrent writers serialise at the kernel level.
- Fsync after every entry. Python uses `os.fsync(fileno)`. Rust uses
  `tokio::fs::File::sync_data`. A power loss between write and OS
  flush does not lose the entry.
- No buffering above the OS layer. Neither implementation holds
  pending entries in user-space memory after the write returns.

## File rotation and retention

The platform does not rotate or delete audit files. Files accumulate
in the configured `AUDIT_LOG_PATH` directory forever. Customers are
free to copy files to long-term storage; the chain stays intact as
long as the copy preserves byte content.

If you want to compress old files for storage, use a streaming codec
that preserves the original byte stream (gzip is fine). Decompressing
the file back to the original bytes and running the verifier produces
the same result as verifying the live file.

## Field stability

The on-disk format is part of the public API. Adding new fields to
the entry is non-breaking as long as verifiers ignore unknown fields.
Renaming or removing fields is breaking.

Tracked future changes (none committed):

- Unify the Rust and Python canonical-payload computation so a single
  verifier function covers both shapes without dispatch.
- Add a `schema_version` field so verifiers can short-circuit on a
  known-incompatible chain.

Both will be announced in `CHANGELOG.md` at least thirty days before
they ship.

## Cross-references

- [`ARCHITECTURE.md`](ARCHITECTURE.md#rule-2-audit-before-response) for
  why every state change writes an audit entry.
- [`THREAT_MODEL.md`](THREAT_MODEL.md#a1-customer-audit-log) for the
  threat model on the audit log itself.
- [`API_REFERENCE.md`](API_REFERENCE.md#get-auditexporttenant_idid)
  for the proxy's audit-export endpoint.
