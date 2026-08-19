# GitOps with Argo CD and Flagger — student lab

**Time:** 2 hours · **Region:** `ap-south-1` · **App:** podinfo (the Chiya Shop again)

You already have: `aws` logged in, `terraform`, `helm`, `kubectl`, `git`, `curl`.

---

## Part 0 — Start the clock (5 min)

The cluster takes ~15 minutes to build. Start it **now** and we will talk
theory while AWS works.

```bash
git clone https://github.com/sagyam/gitops-lab.git
cd terraform

$EDITOR terraform.tfvars          # set student_handle to YOUR handle

terraform init
terraform apply -auto-approve
```

Leave it running. Open a second terminal for everything else.

> Every resource is prefixed with your handle. We share one AWS account.
> If you name your cluster `test`, you will destroy someone else's afternoon.

---

## Part 1 — What GitOps actually claims (while Terraform runs)

Two ideas, and everything else is plumbing.

**1. Git is the desired state, not a record of what you typed.**
The cluster is not "whatever the last person ran". It is "whatever `main`
says", continuously.

**2. The cluster pulls; you do not push.**

```
  Push CD (Jenkins, GH Actions)      Pull CD (Argo CD)
  ─────────────────────────────      ──────────────────────────
  CI has cluster credentials         cluster has read-only Git creds
  CI runs kubectl apply              agent inside cluster reconciles
  drift is invisible                 drift is a first-class alert
  cluster must be reachable from CI  cluster can be firewalled off
```

You already know a reconciliation loop: `terraform plan` compares desired
(HCL) to actual (AWS) and produces a diff. Argo CD is the same loop with
`main` as the desired state and the Kubernetes API as actual — except it runs
every 30 seconds forever instead of when you feel like it.

**Where the boundary sits in this lab:**

| Layer | Reconciler | Trigger |
|---|---|---|
| VPC, EKS, node group | Terraform | you run `apply` |
| argocd, ingress-nginx, flagger | Helm, by hand, once | day-0 bootstrap |
| podinfo | Argo CD | `git push` |
| how podinfo is *replaced* | Flagger | pod spec change |

The Helm row is the bootstrap paradox: something must install the thing that
installs everything else. In production you would then have Argo manage those
Helm releases too, and it manages itself — but you still had to do the first
install by hand.

---

## Part 2 — Bootstrap (15 min)

When `terraform apply` finishes:

```bash
cd ..
aws eks update-kubeconfig --region ap-south-1 --name <handle>-gitops
kubectl get nodes            # expect 2 Ready

./bootstrap/install.sh       # ~5 min, mostly waiting on AWS load balancers
./scripts/urls.sh
```

Export what it prints:

```bash
export ARGOCD_HOST=...
export INGRESS_HOST=...
export PODINFO_VHOST=podinfo.chiya.shop
```

Open `http://$ARGOCD_HOST` and log in as `admin`. It is empty. Good.

> **If a Service is stuck in `<pending>`:** the subnets are missing their
> `kubernetes.io/role/elb` tag. Look at `terraform/network.tf` — the tag is
> there for exactly this reason.

---

## Part 3 — Your first Application (15 min)

Point Argo CD at your repo. Edit `argocd/application-podinfo.yaml` and change
`repoURL` to your fork, then:

```bash
kubectl apply -f argocd/application-podinfo.yaml
```

Watch the UI. Within seconds Argo CD clones your repo, reads
`apps/podinfo/`, and creates the namespace, Deployment, Service and two
Ingresses. Nothing else was applied by hand.

```bash
kubectl -n chiya get all
curl http://$INGRESS_HOST/            # browser works too
```

Read the Application spec while it syncs. Three lines carry the weight:

```yaml
automated:
  prune: true      # YAML deleted from Git -> object deleted from cluster
  selfHeal: true   # cluster edited by hand -> put back
```

Without `prune`, Git is append-only and dead resources pile up forever.
Without `selfHeal`, Argo notices drift and politely does nothing about it.

---

## Part 4 — Prove the loop (15 min)

### 4a. Drift from the cluster side

```bash
kubectl -n chiya scale deploy/podinfo --replicas=5
kubectl -n chiya get pods -w
```

Count them. Watch them go back to 2. You did not fix that. Argo CD watches
Kubernetes resources, saw the live state stop matching Git, and reverted it —
usually within a couple of seconds, because this is an event, not a poll.

Try harder:

```bash
kubectl -n chiya delete deploy/podinfo
kubectl -n chiya get deploy -w
```

It comes back.

**This is the single most useful property of GitOps and the hardest one to
internalise:** the console, `kubectl edit`, and the intern with admin are all
now write-only against a surface that immediately forgets them. The only way
to change the cluster is to change Git.

### 4b. Drift from the Git side

```bash
$EDITOR apps/podinfo/deployment.yaml
# change PODINFO_UI_MESSAGE to "Namaste from v2 - masala chiya"
# change PODINFO_UI_COLOR   to "#c94f1e"

git commit -am "chiya: v2, now with masala"
git push
```

Now watch two things at once:

```bash
kubectl -n chiya get pods -w        # terminal 1
curl http://$INGRESS_HOST/          # terminal 2, repeatedly
```

Up to 30 seconds later (our polling interval; default is 3 minutes) Argo CD
notices, syncs, and Kubernetes performs a **rolling update**: `maxSurge: 1`
means one extra pod appears, `maxUnavailable: 0` means no pod leaves until its
replacement is Ready. Zero downtime, and for a moment both versions are live.

Refresh the browser a few times during the roll. You will see both colours.
Sit with that for a second — **during every rolling update you have ever done,
users were hitting two versions of your code simultaneously.** If v2 changed a
JSON field name, half the requests broke and nothing alerted.

That window is the reason the rest of this lab exists.

> **Faster than 30s?** Add a GitHub webhook to
> `http://$ARGOCD_HOST/api/webhook`. Then push-to-sync is ~1 second. Polling
> is the fallback, not the design.

---

## Part 5 — Strategies (15 min, at the whiteboard)

Read [`strategies/README.md`](strategies/README.md). The table is the lesson;
the rest is commentary. Come back with an answer to:

> Rolling update gives zero downtime. So why is anyone still building
> canary tooling?

---

## Part 6 — Canary with automated rollback (30 min)

### 6a. Hand the Service to Flagger

One commit, two changes — they must land together:

```bash
cp strategies/canary.yaml apps/podinfo/canary.yaml
git rm apps/podinfo/service.yaml

git commit -m "flagger: podinfo canary"
git push
```

**Why remove the Service?** Flagger flips the apex Service's selector between
`podinfo-primary` and `podinfo-canary` — that is the traffic switch. If Git
also declares that Service, Argo CD reverts the selector, Flagger sets it
again, and you have built an infinite loop. Two reconcilers, one field, no
owner. Never do this to yourself in production.

Watch Flagger take over:

```bash
kubectl -n chiya get canary -w
kubectl -n chiya get deploy,svc,ing
```

Flagger has created `podinfo-primary` (a copy of your Deployment), scaled your
`podinfo` Deployment to **0**, and created `podinfo`, `podinfo-primary`,
`podinfo-canary` Services plus a `podinfo-canary` Ingress. Status: `Initialized`.

> Note `ignoreDifferences` in the Application. Git says `replicas: 2`, Flagger
> says 0. We told Argo CD that Flagger owns that field. Delete those four
> lines afterwards if you want to watch the fight — it is instructive and it
> will not stop on its own.

### 6b. A good release

Terminal 1:
```bash
./scripts/watch-canary.sh
```

Terminal 2:
```bash
export INGRESS_HOST=...   # if not already
./scripts/traffic.sh
```

Terminal 3 — ship it:
```bash
$EDITOR apps/podinfo/deployment.yaml     # message -> "v3 - butter tea"
git commit -am "chiya: v3" && git push
```

Now narrate what you see:

1. Argo CD syncs the Deployment. Flagger notices its pod spec hash changed.
2. `Progressing`. The **pre-rollout webhook** runs a smoke test against canary
   pods at **0% traffic**. Failure here means no user is ever exposed.
3. Weight goes 10 → 20 → 30 → 40 → 50. In terminal 2 you can watch the ratio
   of v2:v3 responses change. That is the `canary-weight` annotation on the
   cloned Ingress, nothing more exotic.
4. At each step Flagger queries Prometheus for success rate and P99 latency
   over the last 30s and compares against `thresholdRange`.
5. `Promoting` — `podinfo-primary` is updated to the new spec.
6. `Succeeded`, weight back to 0, canary scaled down.

```bash
kubectl -n chiya describe canary podinfo | tail -30
kubectl -n chiya get ing podinfo-canary -o yaml | grep -A3 annotations
```

### 6c. A bad release, and nobody gets paged

Start a new rollout, then poison it while the analysis is running:

```bash
# terminal 3
$EDITOR apps/podinfo/deployment.yaml    # message -> "v4 - broken"
git commit -am "chiya: v4" && git push

# the moment status flips to Progressing, in terminal 4:
./scripts/traffic.sh /status/500
```

`/status/500` makes podinfo return HTTP 500. Because those requests flow
through the canary Ingress, they land in nginx's metrics, and
`request-success-rate` for the canary falls below 99.

Watch the events:

```
Halt podinfo.chiya advancement success rate 87.50% < 99%
Halt podinfo.chiya advancement success rate 61.11% < 99%
...
Rolling back podinfo.chiya failed checks threshold reached 5
Canary failed! Scaling down podinfo.chiya
```

Stop the traffic script. Check the public URL — it never stopped serving v3.

**What just happened:** exposure peaked at whatever weight the canary had
reached, roughly 10–20% of requests, for under two minutes, and the system
recovered without a human. Compare that with the rolling update in Part 4,
where the same bug reaches 100% of users and stays there until somebody
notices.

**What did NOT happen:** Git was not changed. `main` still says v4. Argo CD is
still faithfully syncing v4. Flagger simply refuses to promote it, and will
keep refusing. The failed release stays visible until a human fixes the code —
which is exactly right. Automation reverted the *cluster*; only a person gets
to revert *intent*.

---

## Part 7 — The other shapes (10 min)

Same Deployment, same Ingress, different `analysis` block.

**Blue/green** — `cp strategies/bluegreen.yaml apps/podinfo/canary.yaml`

`provider: kubernetes` and `iterations: 6`. No weights at all: run the checks
six times while green serves 0% real traffic, then flip the Service selector
100% in one step. Rollback = flip it back, sub-second, because blue was never
touched.

**A/B** — `cp strategies/ab-test.yaml apps/podinfo/canary.yaml`

`match:` on an `x-canary: insider` header. Test it:

```bash
curl -H "Host: $PODINFO_VHOST" http://$INGRESS_HOST/ | grep message
curl -H "Host: $PODINFO_VHOST" -H "x-canary: insider" http://$INGRESS_HOST/ | grep message
```

Two different answers, deterministically, from the same URL. Swap `headers`
for `cookies` and the assignment sticks per browser — which is the only way an
A/B *experiment* means anything.

**Big bang** — see `strategies/recreate-bigbang.yaml`. Two lines in the
Deployment and no tooling at all, because it makes no attempt to be safe.

---

## Part 8 — Destroy (5 min) — NOT OPTIONAL

Kubernetes-created load balancers are invisible to Terraform. If you skip
straight to `terraform destroy`, the VPC delete hangs on ENIs held by NLBs
Terraform does not know exist, and you leave billable orphans behind.

```bash
kubectl -n chiya delete canary --all
kubectl delete ns chiya argocd ingress-nginx --wait=true

# confirm the NLBs are gone before continuing
aws elbv2 describe-load-balancers --region ap-south-1 \
  --query 'LoadBalancers[].LoadBalancerName'

cd terraform
terraform destroy -auto-approve
```

Then verify nothing of yours remains:

```bash
aws eks list-clusters --region ap-south-1
```

---

## Takeaways

1. GitOps is a reconciliation loop, the same shape as `terraform plan`, run
   continuously. Argo CD reconciles application state; Terraform reconciles
   infrastructure. Different scopes, identical idea.
2. Pull beats push because drift becomes observable instead of invisible.
3. `selfHeal` makes manual cluster edits pointless — that is the feature.
4. Rolling update solves downtime, not risk. Every strategy above it exists to
   limit how many users meet a bad build.
5. Canary randomises *who*; A/B chooses *who*. Same YAML, different question.
6. Two controllers must never own the same field. `ignoreDifferences` and
   deleting `service.yaml` are both about establishing ownership.
7. Automated rollback reverts the cluster, never Git. Machines fix state;
   humans fix intent.
