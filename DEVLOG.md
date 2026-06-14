# Vyrox Devlog

what we're building, day by day. honest engineering notes, newest on top.
not marketing, just what actually shipped.

## 2026-06-12

big day. closed the whole code-gap audit (53 findings, the 7-agent read from
yesterday) and shipped the demo we actually need to sell. ran it as five
engineers in parallel (worker+heuristics, ingestion+audit+crypto, data+console,
the rust proxy, and frontend+CI), then did an integration pass to wire the
seams and reconcile the tests.

the headline change: DRY_RUN is gone. the old model was a global kill-switch in
the proxy, `if state.dry_run { return }`, which meant "don't really call the
EDR." problem is that's not how you run this for real, and it's not how you demo
it either. so we replaced the whole idea. the proxy now always dispatches to
whatever EDR the tenant is configured for. safety isn't a global switch anymore,
it's two things that were already true: a human still approves every containment
action, and the connector config decides where the action lands.

that unlocked the demo. we don't have sentinelone or crowdstrike or defender to
point at, and neither does a prospect on a first call. so demo-acme (shows up
everywhere as "Acme Corp") is a real tenant whose edr_base_url points at our
bundled mock EDR on port 4010. when you approve an isolation for acme, the proxy
runs the exact same path it runs for a paying customer: hmac, nonce, audit
before the call, real http to the mock, real response, real rollback. the only
difference is the fleet is simulated. we tag those actions `simulated=true` so
the audit and the evidence pack stay honest about it, but the action genuinely
executes, which matters because it means you can demo the rollback too (a
"dry run" action would have nothing to undo).

`just seed-demo` builds it: acme with a 15-host fleet (crown-jewel DC, a file
server, workstations), 10 alerts across the severities, an executed-then-rolled-
back action with a real evidence pack. `just dev-all` brings the whole stack up
with the mock EDR running and the demo seeded. log in, show a client.

one more thing worth writing down: we pinned the audit-chain serializer. the
python chain and the rust chain both have to hash records identically or the
tamper-evidence claim falls apart, and before today that only held because
someone hand-wrote the keys in alphabetical order on both sides. now both use a
canonical form (sorted keys, compact separators, utf-8, no ascii-escaping) and
there's a shared sha256 fixture both languages assert against. one out-of-order
field added later can't silently fork the chains anymore.

what we deliberately did NOT do: per-tenant proxy signing keys (SRF-07). we did
the safe half (a dedicated VYROX_PROXY_SECRET, fail closed in prod, rust mirrors
it) but left the HKDF per-tenant derivation as a fast-follow. it changes the
python<->rust signing protocol, and stacking that on top of the connector change
in the same wave was asking for a cross-repo mismatch. it's written up in the
audit doc.

gates are green everywhere: 1005 python tests, mypy --strict clean, 53
heuristics, 68 rust, frontend typecheck+lint+tests. CI now actually enforces the
70% coverage floor and mypy --strict (it didn't before, the gate only lived in
the justfile).

## 2026-06-11

closing out the v0.2.0 build. a lot landed.

rollback is real now. before, hitting rollback just wrote down that we meant to undo
something. now it actually calls the EDR to un-isolate the host or put the network
back, with a proper state machine behind it (executed, rolling back, rolled back, and
a failed state). if a rollback fails, a human gets paged loud, it never just goes
quiet. we built a fake EDR to run the whole isolate-then-un-isolate path end to end in
tests, so the code is proven before it ever touches a real customer EDR. that means we
do not need a vendor sandbox to ship it, just a ten minute check at the first pilot.

per tenant credentials went in too. each customer's EDR keys are encrypted at rest and
used only for that customer's actions. the proxy used to lean on one shared key, now it
acts as the specific tenant with their own keys.

rebuilt the console as two separate web apps, the operator console and the admin app,
so admin code never ships to the operator side. real login now, not a stand in. the
add-client wizard works the way we wanted: a partner adds a client themselves, gets the
webhook to point their EDR at, drops in the client's EDR keys, fires a test alert, and
watches it flip to active. the admin app is my side, orgs, the activation funnel,
system health, the audit log, support tools, usage.

spent the back half of the day on a full system check before building anything more.
brought the pieces up against the real database and queue and pushed a real mimikatz
alert through triage. came back critical at 0.995, which is what it should be. login
holds, the wrong token gets a 401 and a valid token with no profile gets a 403, so the
tenant isolation actually rejects people it should. evidence packs still verify. nothing
broken in the core. one annoyance, an old copy of the stack left running on the box was
holding the ports and i could not stop it, so i checked each piece against the live
database and queue directly instead of running all of it at once. the browser login
click through is the one thing left to eyeball by hand.

also purged every em dash out of the codebase. small thing, but i want it reading like
a person wrote it.

## 2026-06-10

big one. the console is now the surface. you do your work in our own web console,
see the queue, read the verdict and why, approve or deny, pull evidence. the chat
bot stays only as an optional notifier if a team wants a ping somewhere. it is not
where you operate anymore.

shipped the whole proof layer, end to end:

- evidence packs. pick a tenant and a date range and you get a report of every
  alert, what the system decided, who approved it, what ran, and the result, with
  the hash chain that proves nobody edited it after the fact.
- a bundled verifier. every pack carries a tiny standalone script. anyone can run
  it on their own machine with no access to us, and it says pass or fail and points
  at the exact line if something was tampered with.
- chain head anchoring. we publish each tenant's chain head on a schedule so even
  we cannot quietly rewrite past history.
- the pack renders as a real audit report now. cover page, verification status,
  signer fingerprint, chronology. not a json dump anymore.
- secret scrubbing runs before anything leaves the building, so a password sitting
  in a command line never ends up inside a pack.

also got the boring but load bearing stuff in:

- error tracking across every service. off by default, on the moment you give it a
  key, so dev and tests stay quiet.
- real health checks. a service only reports healthy when its dependencies are
  actually reachable, so a worker with a dead queue connection can't sit there
  silently dropping alerts.

and kicked off the foundation for the multi tenant console: the database and auth
layer, the org and tenant model, and token verification so the backend knows who is
calling and exactly what they are allowed to touch. that one is mid build.

tests stayed green the whole way. every change went in through a pull request with
review, nothing straight to main.
