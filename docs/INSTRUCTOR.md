# Instructor runbook — GitOps (2 hours)

## Timing

| Time | Block | Mode | Notes |
|---|---|---|---|
| 0:00–0:05 | `terraform apply` kicked off | hands-on | **Do this first.** ~15 min of AWS wall clock you get for free. |
| 0:05–0:20 | GitOps concepts | talk | Push vs pull, reconciliation, drift. Callback to Terraform module. |
| 0:20–0:35 | Bootstrap: helm installs, get URLs | hands-on | Slowest part is NLB provisioning, 2–4 min. |
| 0:35–0:50 | First Argo `Application`, podinfo live | hands-on | Everyone should have two working URLs by 0:50. |
| 0:50–1:05 | Drift demos + rolling update | hands-on | The `scale --replicas=5` moment is the hook. |
| 1:05–1:20 | Strategy taxonomy | talk | `strategies/README.md` table. |
| 1:20–1:50 | Flagger canary, good release then bad | hands-on | Budget 8 min for the takeover, 5 min per rollout. |
| 1:50–1:57 | Blue/green + A/B as config variants | demo | Show YAML; run the A/B curl only. |
| 1:57–2:00 | `terraform destroy` | hands-on | Enforce it. Watch for stragglers. |

If you are running late, cut Part 7 entirely and show the two YAML diffs on a
slide. Never cut Part 8.

## Pre-flight, the day before (30 min, do not skip)

Run the whole lab once, end to end, in the shared account.

1. **Verify the podinfo tag exists.** The manifests use
   `ghcr.io/stefanprodan/podinfo:6.14.0`.
   ```bash
   docker buildx imagetools inspect ghcr.io/stefanprodan/podinfo:6.14.0
   ```
   If it 404s, pick a current tag and `sed -i` it across `apps/`.
   Note the lab drives releases with **env var changes, not tag bumps**, so
   you only need one tag to exist.

2. **Verify the EKS version.**
   ```bash
   aws eks describe-cluster-versions --region ap-south-1 \
     --query 'clusterVersions[].clusterVersion'
   ```
   Update `variables.tf` if `1.33` has aged out.

3. **Verify the Flagger CRD URL resolves** (it tracks `main`):
   ```bash
   curl -sfI https://raw.githubusercontent.com/fluxcd/flagger/main/artifacts/flagger/crd.yaml
   ```

4. **Check account quotas.** Each student consumes 1 VPC, 1 IGW, 2 EIP-free
   public subnets, 2 EC2 instances, and **2 NLBs**. Default VPC quota is 5 per
   region and default EC2-VPC ELB quota is 50. With more than 4 students you
   will hit the VPC limit before anything else — either raise the quota or use
   the shared-cluster mode below.

5. **Cost sanity.** Per student per hour, ap-south-1, roughly:
   EKS control plane $0.10 + 2× t3.large ~$0.19 + 2× NLB ~$0.05 ≈ **$0.35/hr**.
   Two hours ≈ $0.70/student. Cheap — *if it gets destroyed*.

## Two delivery modes

**Mode A — cluster per student (default, written into `LAB.md`).**
Best learning. Needs quota headroom. Everyone's `terraform apply` runs
concurrently at 0:00, which is fine; EKS control planes build in parallel.

**Mode B — one shared cluster, you provision it before class.**
Use when quota or budget is tight. Changes:
- You run `terraform apply` and `bootstrap/install.sh` the night before.
- Each student forks the repo and applies **their own** `Application` with
  `metadata.name: podinfo-<handle>` and `destination.namespace: chiya-<handle>`.
- Namespace and Ingress host become `chiya-<handle>` / `podinfo-<handle>.chiya.shop`.
- Everything is `sed`-able; there are only four occurrences of `chiya`
  in `apps/`.
- Trade-off: nobody watches an EKS cluster get built, and Flagger's Canary
  names must be unique per namespace (they will be).

## The five talking points that make this land

1. **"You already know this loop."** `terraform plan` = desired vs actual =
   diff. Argo CD is that, every 30 seconds, forever. Land this hard — it
   converts GitOps from a new topic into a familiar one.

2. **The `scale --replicas=5` moment.** Do this live before you explain it.
   Let them watch the pods disappear. *Then* say: your console access, your
   `kubectl edit`, and your most confident colleague are all now write-only.

3. **The rolling-update reveal.** During Part 4b, get them to refresh the
   browser and see two colours. Ask: "how many of your production rolling
   updates served two incompatible API versions at once, and how would you
   have known?" This is the emotional pivot into Flagger — without it, canary
   looks like ceremony.

4. **Two reconcilers, one field.** Deleting `service.yaml` and adding
   `ignoreDifferences` are the same lesson: every field needs exactly one
   owner. If you have five spare minutes and a brave mood, remove
   `ignoreDifferences` live and let them watch the replica count oscillate.

5. **"Flagger rolls back the cluster, not Git."** Most students assume the
   rollback reverts the commit. It does not, and it should not. Machines fix
   state; humans fix intent. This is the sentence they should leave with.

## Known failure modes and what to say

| Symptom | Cause | Fix |
|---|---|---|
| Service stuck `<pending>` | subnet missing `kubernetes.io/role/elb` | tags are in `network.tf`; check the student edited nothing |
| `terraform apply` times out on coredns addon | addon raced ahead of nodes | `depends_on` handles it; if hit, `terraform apply` again |
| Canary stuck "waiting for metrics" | nginx metrics off, or no traffic | check `controller.metrics.enabled` and the loadtester pod is Running |
| Canary stuck `Initializing` forever | Deployment has no Ready pods | `kubectl describe` the pods; usually a bad image tag |
| Argo shows `OutOfSync` on replicas | `ignoreDifferences` missing/typo'd | that is the lesson — use it |
| `podinfo` Service selector flapping | student did not `git rm service.yaml` | that is also the lesson |
| Replica oscillation after canary | same, plus missing `ignoreDifferences` | see above |
| `terraform destroy` hangs on VPC | NLBs still exist, ENIs pinned | delete the namespaces first, per Part 8 |
| Argo login fails | using `https://` | we set `server.insecure: true`; it is plain `http://` |

## Post-class sweep (run it, every time)

```bash
aws eks list-clusters --region ap-south-1
aws elbv2 describe-load-balancers --region ap-south-1 \
  --query 'LoadBalancers[].[LoadBalancerName,VpcId]' --output table
aws ec2 describe-vpcs --region ap-south-1 \
  --filters Name=tag:Project,Values=gitops-lab \
  --query 'Vpcs[].[VpcId,Tags[?Key==`Owner`].Value|[0]]' --output table
```

Anything listed has an `Owner` tag. Chase that person.

## Natural follow-ons

- **Argo CD manages Argo CD** — the app-of-apps pattern, and moving the three
  Helm releases into Git so nothing is bootstrapped by hand twice.
- **GitHub webhook** instead of 30s polling; ties back to the Actions module.
- **Custom Flagger metrics** via `MetricTemplate` — canary on business KPIs,
  not just 5xx. Direct callback to the o11y module's Prometheus.
- **Sealed Secrets / External Secrets** — the obvious "but what about
  passwords in Git" question, which someone will ask in Part 3.
