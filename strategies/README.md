# Six ways to replace running software

Every strategy below answers the same question differently:
**how many users see the broken version before you find out it is broken?**

| Strategy | Mechanism | Downtime | Extra capacity | Blast radius before detection | Rollback |
|---|---|---|---|---|---|
| **Big bang / Recreate** | Delete all old pods, then create new | Yes, seconds to minutes | 1x | 100% of users | Another outage |
| **Rolling** | Replace pods a few at a time | No | ~1.1x | 100%, just spread over time | Roll the old version forward again |
| **Blue / Green** | Two full stacks, flip the router | No | 2x | 0% during test, 100% after cut | Flip the router back. Seconds. |
| **Canary** | Weighted split, 5% → 10% → 25% → … | No | ~1.2x | Only the current weight | Set weight to 0 |
| **A/B** | Route by header/cookie/user attribute | No | ~1.2x | Only the matched cohort | Remove the match rule |
| **Shadow / mirror** | Copy traffic to new version, discard responses | No | 2x | 0% — nobody sees the response | Stop mirroring |

## The distinctions people get wrong

**Canary vs A/B is not "how much traffic".** It is *how users are selected*.
Canary selects randomly — a user may hit v1 then v2 then v1 on three
consecutive requests. That is fine when you are asking *"does the new build
crash?"* It is useless when you are asking *"do people buy more with the new
checkout button?"* — for that you need the same person in the same bucket for
the length of the experiment, which is what a cookie or user-ID hash buys you.

Canary is an **engineering** control, judged by error rate and latency.
A/B is a **product** experiment, judged by conversion. They look identical in
YAML and mean completely different things.

**Blue/green is not safer than canary, it is faster to undo.** Blue/green
gives you a sub-second rollback because the old stack never went away, but the
moment you cut over, 100% of users are exposed. Canary limits exposure but its
rollback takes as long as draining the current weight. Pick based on which
risk you actually have — an expensive-to-detect bug or an expensive-to-recover
one.

**Rolling update is not a safety feature.** It gives you zero *downtime*, not
zero *risk*. A rolling update of a bad build ends with 100% bad pods, exactly
like a big bang, just more slowly and with a confusing half-broken window in
the middle. Everything above the rolling row on that table exists because
rolling update alone does not protect anyone.

## Where the automation goes

```
                Kubernetes gives you           Flagger adds
                ────────────────────           ────────────────────
Big bang        strategy: Recreate             —
Rolling         strategy: RollingUpdate        —
Blue/Green      (hand-flip a Service selector) provider: kubernetes + iterations
Canary          (nothing)                      stepWeight + maxWeight
A/B             (nothing)                      iterations + match
Shadow          (nothing)                      analysis.mirror: true (mesh only)
```

Rows 1 and 2 are built into the Deployment controller. Rows 3–6 need something
that can watch metrics and change routing — that is the entire job description
of Flagger.

## Automated rollback: the actual point of all this

A canary that a human has to watch is just a slow deploy. The value appears
when the *decision* is automated:

```yaml
analysis:
  threshold: 5              # allow 5 bad checks
  metrics:
    - name: request-success-rate
      thresholdRange: { min: 99 }
  webhooks:
    - name: acceptance-test
      type: pre-rollout      # gate BEFORE any user traffic
```

Three independent gates, each of which can abort the release with no human
in the loop:

1. **pre-rollout webhook** — a smoke test against canary pods at 0% traffic.
   Fails → nobody was ever exposed.
2. **metric thresholds** — success rate and latency, evaluated every interval
   against real traffic. `threshold: 5` failures in a row → roll back.
3. **progressDeadlineSeconds** — the rollout is simply taking too long
   (pods not becoming ready, metrics never arriving) → roll back.

Rolling back means: set canary weight to 0, scale the canary Deployment to 0,
leave `podinfo-primary` untouched. Since primary was never modified, "rollback"
is not a redeploy — it is just ceasing to send traffic somewhere. That is why
it takes seconds and cannot itself fail.

And critically: **Flagger rolls back the cluster, not Git.** Git still says
"deploy the new version". Argo CD still syncs it. Flagger keeps refusing to
promote it. The failed release sits there visible and un-promoted until a
human fixes the code — which is the correct outcome, and a good thing to point
at when someone asks what GitOps is *for*.
