# Vyrox Devlog

what we're building, day by day. honest engineering notes, newest on top.
not marketing, just what actually shipped.

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
