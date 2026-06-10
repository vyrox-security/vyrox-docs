# Vyrox Devlog

what we're building, day by day. honest engineering notes, newest on top.
not marketing, just what actually shipped.

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
