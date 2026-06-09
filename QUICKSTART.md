# Quickstart

This walks an OSS contributor from `git clone` to a signed alert
hitting a local proxy. About ten minutes. No customer-side
credentials. No EDR account. Nothing leaves your machine.

If you are an operator integrating a real EDR, see the design partner
playbook, your company contact has the link. The public docs cover
the open path only.

## What you need

- `git`
- `cargo` (Rust 1.75+ recommended; whatever the proxy's `Cargo.toml`
  pins is fine)
- `bash`, `openssl`, `curl`. Standard on macOS and most Linuxes.
- About a hundred megabytes of disk for the Rust build cache.

You do not need Python, Node, Docker, or a Discord account.

## Step 1: Clone the open components

Three repositories. Each clones into its own directory.

```bash
git clone https://github.com/vyrox-security/vyrox-proxy.git
git clone https://github.com/vyrox-security/vyrox-simulator.git
git clone https://github.com/vyrox-security/vyrox-docs.git
```

The docs repo is this one. The other two are MIT licensed.

## Step 2: Build the proxy

```bash
cd vyrox-proxy
cargo build
```

First build pulls the dependency tree (about ninety crates). Future
builds are quick. The final binary is at
`target/debug/vyrox-proxy`.

## Step 3: Run the proxy with DRY_RUN

The proxy refuses to start without a HMAC secret. Generate one for
local use only; do not reuse it anywhere else.

```bash
export VYROX_HMAC_SECRET=$(openssl rand -hex 32)
export AUDIT_LOG_PATH=./local-audit
export DRY_RUN=true
export BIND_ADDR=127.0.0.1:3000

mkdir -p "$AUDIT_LOG_PATH"
./target/debug/vyrox-proxy
```

The proxy listens on `127.0.0.1:3000`. `DRY_RUN=true` is the default
so even if you forget to set it, the proxy will not call any EDR API.

Check it is alive in another shell:

```bash
curl -s http://127.0.0.1:3000/health
# {"status":"ok"}
```

## Step 4: Fire a signed execution request

The proxy accepts `POST /execute` with an HMAC-SHA256 signed body.
Smallest valid request:

```bash
SECRET="$VYROX_HMAC_SECRET"
TS=$(date +%s)
BODY=$(cat <<EOF
{"request_id":"$(uuidgen | tr A-Z a-z)","tenant_id":"local-test","alert_id":"alt-1","action_type":"HOST_ISOLATION","host":"workstation-01","approved_by":"local-test","approved_at":$TS}
EOF
)
SIG="sha256=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | sed 's/^.*= //')"

curl -s -X POST http://127.0.0.1:3000/execute \
  -H "Content-Type: application/json" \
  -H "X-Vyrox-Signature: $SIG" \
  --data-binary "$BODY"
# {"status":"dry_run","dry_run":true}
```

The proxy verifies your signature, writes an audit entry, then
short-circuits because `DRY_RUN=true`. Look at the audit file:

```bash
ls local-audit/
# audit-2026-05-23.jsonl

cat local-audit/audit-*.jsonl
```

You will see one JSONL entry with `dry_run: true`, a `hash`, and a
`previous_hash` of sixty four zeros (the genesis sentinel). The
format spec is in [`AUDIT_CHAIN.md`](AUDIT_CHAIN.md).

## Step 5: Run the alert simulator

The simulator generates signed payloads for a Vyrox ingestion
endpoint. There is no public Vyrox ingestion service to point it at,
but you can replay against the simulator's own `--dry-run` mode to
see what the wire format looks like:

```bash
cd ../vyrox-simulator

./simulate.sh mimikatz --dry-run
# Prints the signed payload to stdout.
```

If you have a private vyrox stack running (worker plus ingestion plus
the bot), point the simulator at it:

```bash
VYROX_URL=http://localhost:8001/webhook \
  VYROX_HMAC_SECRET=$(cat ../vyrox/.env | grep CROWDSTRIKE_WEBHOOK_SECRET | cut -d= -f2) \
  ./simulate.sh mimikatz
```

For the open path, `--dry-run` is enough to see how an alert payload
looks before it hits ingestion.

## Step 6: Read the docs

You now have a running proxy and a signed-payload generator. The
next thing to do depends on what you came for.

- **Adding an EDR adapter.** Start at [`ADAPTERS.md`](ADAPTERS.md).
  The full contract is there.
- **Understanding the security model.** Start at
  [`ARCHITECTURE.md`](ARCHITECTURE.md), then
  [`THREAT_MODEL.md`](THREAT_MODEL.md).
- **Verifying the audit chain on your own.** Start at
  [`AUDIT_CHAIN.md`](AUDIT_CHAIN.md). The reference verifier in
  Python is thirty lines.
- **Calling the API.** Start at [`API_REFERENCE.md`](API_REFERENCE.md).

## Troubleshooting

### `401 Unauthorized`

The proxy rejected your signature. Two common causes:

- The shell ate your `\n` somewhere and the body bytes you signed are
  not what you sent. Use `--data-binary` (not `-d`) on the curl
  command and quote the heredoc.
- You signed with a different secret than the proxy is using. Re-run
  the export and the proxy boot in the same shell.

### `410 Gone`

Your timestamp is outside the thirty second replay window. Refresh
`TS=$(date +%s)` and regenerate the body and signature.

### Proxy refuses to start

The proxy panics on boot if `VYROX_HMAC_SECRET` is unset. Set it
before launch. The proxy also panics if you set one of
`TLS_CERT_PATH` and `TLS_KEY_PATH` but not the other; either set both
(for TLS) or neither (for plain HTTP behind a reverse proxy).

### Audit file is empty

You probably hit 401 before any audit write. The proxy writes audit
entries only after the HMAC check passes. If you see a request in
the logs but no audit entry, that is the reason.

## What is not in the open path

The full Vyrox stack contains four more processes: ingestion, worker,
Discord bot, and the heuristics engine. Those live in private
repositories. The pipeline shape is documented in
[`ARCHITECTURE.md`](ARCHITECTURE.md) so a reader can understand the
whole system; the implementations are not public.

A contributor adding a new EDR adapter does not need the private
side. The adapter recipe in [`ADAPTERS.md`](ADAPTERS.md) covers what
you write, the contracts you must respect, and the tests you must
ship. A reviewer with private access merges your PR; you do not need
the private code on disk.

## Next steps

- Read [`CONTRIBUTING.md`](CONTRIBUTING.md) for the patch workflow,
  test conventions, and reviewer expectations.
- Read [`ARCHITECTURE.md`](ARCHITECTURE.md) for the system overview
  and the six critical rules.
- Read [`AUDIT_CHAIN.md`](AUDIT_CHAIN.md) if you want to write a
  verifier or a compliance pipeline against the audit log.
