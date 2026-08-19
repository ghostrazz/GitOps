# GitOps lab — Argo CD + Flagger on EKS

A 2-hour bootcamp module. Terraform builds an EKS cluster, three Helm charts
are installed by hand exactly once, and from that point every change to the
application happens through `git push`.

- **Students start here:** [`LAB.md`](LAB.md)
- **Instructors start here:** [`INSTRUCTOR.md`](INSTRUCTOR.md)
- **Deployment strategy reference:** [`strategies/README.md`](strategies/README.md)

## Layout

```
terraform/                 VPC + EKS + node group + addons (raw resources)
bootstrap/                 day-0 Helm installs, run once by hand
  install.sh
  argocd-values.yaml
  ingress-nginx-values.yaml
  flagger-values.yaml
  loadtester-values.yaml
apps/podinfo/              <- Argo CD syncs THIS folder
  namespace.yaml
  deployment.yaml
  service.yaml             (deleted in Part 6 — Flagger takes ownership)
  ingress.yaml             vhost route, cloned by Flagger for canary weights
  ingress-public.yaml      catch-all route, browser-friendly
argocd/
  application-podinfo.yaml the one object applied by hand
strategies/                canary / bluegreen / ab-test / recreate
scripts/                   urls.sh, watch-canary.sh, traffic.sh
```

## Who reconciles what

```
Terraform  ──> VPC, EKS, nodes            (you run apply)
Helm       ──> argocd, nginx, flagger     (once, by hand, day 0)
Argo CD    ──> everything in apps/        (git push)
Flagger    ──> how apps/ is rolled out    (pod spec change)
```

The rule that keeps this from exploding: **exactly one controller owns each
field.** Flagger owns the Deployment's `replicas` and the apex Service, so Git
does not declare them. That is what `ignoreDifferences` and the deleted
`service.yaml` are for.

## Quick start

```bash
cd terraform && cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars      # set student_handle
terraform init && terraform apply -auto-approve

aws eks update-kubeconfig --region ap-south-1 --name <handle>-gitops
cd .. && ./bootstrap/install.sh && ./scripts/urls.sh

# edit argocd/application-podinfo.yaml -> your repoURL
kubectl apply -f argocd/application-podinfo.yaml
```

## Teardown

Delete the Kubernetes namespaces **before** `terraform destroy`, or the VPC
delete will hang on ENIs held by load balancers Terraform never created.

```bash
kubectl delete ns chiya argocd ingress-nginx
cd terraform && terraform destroy -auto-approve
```

## Assumptions

`aws` authenticated, `terraform >= 1.6`, `helm 3`, `kubectl`, `git`, `curl`.
Region `ap-south-1`. One shared AWS account, so every resource name is
prefixed with `student_handle`.
