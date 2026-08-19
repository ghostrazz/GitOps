# Troubleshooting

## Argo CD

**Application stuck `Unknown` / `ComparisonError`**
Repo URL wrong, branch wrong, or the repo is private. For a private repo:
`argocd repo add https://github.com/you/repo --username you --password <PAT>`
or add a `repo-creds` Secret in the `argocd` namespace.

**Push doesn't sync**
Default poll is 3 minutes; we set 30s in `argocd-values.yaml`. Force it:
`argocd app get podinfo --hard-refresh`. For instant sync, add a GitHub
webhook to `http://$ARGOCD_HOST/api/webhook`.

**Permanently `OutOfSync` on a field nobody edited**
A controller in the cluster is writing that field (Flagger, an HPA, a mutating
webhook, a defaulting admission plugin). Either stop declaring it in Git or
add it to `ignoreDifferences`. Do not "fix" it by disabling `selfHeal`.

**`selfHeal` is on but drift persists**
`selfHeal` only reverts fields Argo tracks. Fields added by a mutating webhook
after apply are invisible to it.

## Load balancers

**Service `<pending>` forever**
```bash
kubectl -n ingress-nginx describe svc ingress-nginx-controller | tail -20
```
Almost always subnet discovery. The subnets need
`kubernetes.io/role/elb=1` and `kubernetes.io/cluster/<name>=shared`.

**NLB exists but connections hang**
Target registration takes 2–4 minutes after creation. Check target health:
```bash
aws elbv2 describe-target-health --region ap-south-1 --target-group-arn <arn>
```

## Flagger

**Canary stuck `Initializing`**
Flagger will not initialize until the source Deployment has Ready pods.
`kubectl -n chiya describe pod -l app=podinfo`.

**"waiting for metrics" / analysis never advances**
Three causes, in order of likelihood:
1. No traffic. The `load-test` rollout webhook drives it — check
   `kubectl -n chiya get pods -l app=flagger-loadtester`.
2. nginx metrics off. `controller.metrics.enabled: true` and the scrape
   annotations must both be present.
3. Prometheus can't see nginx:
   ```bash
   kubectl -n ingress-nginx port-forward svc/flagger-prometheus 9090:9090
   # then query: nginx_ingress_controller_requests
   ```

**Canary triggers when you didn't expect it**
Flagger hashes the whole pod spec. A resource limit change, an annotation on
the pod template, or an env var edit all count as a new release. Only the pod
template — changing `spec.replicas` does not.

**Replica count oscillating between 0 and 2**
Argo CD and Flagger both writing `/spec/replicas`. Add the
`ignoreDifferences` block from `argocd/application-podinfo.yaml`.

**Service selector flapping**
`apps/podinfo/service.yaml` still in Git. Delete it — Flagger owns the apex
Service once a Canary exists.

## Teardown

**`terraform destroy` hangs on the VPC (15+ min)**
ENIs from load balancers Terraform doesn't know about. Delete the namespaces
first. If already stuck:
```bash
aws ec2 describe-network-interfaces --region ap-south-1 \
  --filters Name=vpc-id,Values=<vpc-id> \
  --query 'NetworkInterfaces[].[NetworkInterfaceId,Description]' --output table
```
Delete the load balancers those ENIs belong to, then re-run destroy.

**Namespace stuck `Terminating`**
A finalizer, usually the Argo CD `resources-finalizer` or a Flagger CRD whose
controller is already gone. Delete the Canary objects before the namespace, or:
```bash
kubectl get ns chiya -o json | jq '.spec.finalizers=[]' \
  | kubectl replace --raw /api/v1/namespaces/chiya/finalize -f -
```
