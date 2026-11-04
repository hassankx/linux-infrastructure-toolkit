# Senior DevOps / SRE Interview Cheat Sheet: 10 Production Scenarios

Practical, interview-ready responses for senior DevOps, platform engineering, Linux infrastructure, and SRE roles.

**Answer pattern:** Impact → Investigate → Evidence → Mitigate → Verify → Prevent. Adapt examples to systems you have actually operated. Commands below are diagnostic examples: replace placeholders and verify namespace, context, permissions, and production impact before executing changes.

## 1. Deployment succeeds but traffic reaches the old version

**Say:** “A successful rollout is not proof that users hit the new version. I follow the request path from the public endpoint back to the workload.”

1. Confirm image **digest**, rollout state, labels and ready replicas.
2. Verify Service selector and EndpointSlices point at intended pods.
3. Inspect Ingress/Gateway/LB rules, canary weights, mesh routes and blue/green switches.
4. Inspect CDN, proxy and application caching.
5. Verify externally using a version endpoint/header and request tracing.

```bash
kubectl rollout status deployment/myapp -n production
kubectl get deploy myapp -n production -o yaml
kubectl get pods -n production -o wide --show-labels
kubectl get svc myapp -n production -o yaml
kubectl get endpointslices -n production -l kubernetes.io/service-name=myapp
kubectl get ingress -n production
```

**Takeaway:** The user-facing response is the final source of truth, not CI/CD success.

## 2. Pods are healthy but users get 504 Gateway Timeout

**Say:** “Pod readiness is one signal. A 504 often occurs at a proxy while waiting for a slow or unreachable upstream.”

1. Establish affected routes, regions, timeframe and error rate.
2. Trace edge/CDN → load balancer/Ingress → Service/EndpointSlice → pod → downstream dependencies.
3. Correlate ingress logs, application logs, distributed traces and p95/p99 latency.
4. Check connection pools, slow queries, throttling, DNS and network policy.
5. Mitigate the bottleneck and confirm user-visible error rate recovers.

```bash
kubectl get pods,svc,endpointslices -n production
kubectl describe ingress myapp -n production
kubectl logs deployment/myapp -n production --since=15m
kubectl top pods -n production
kubectl get events -n production --sort-by=.lastTimestamp
```

**Takeaway:** Increasing a proxy timeout might conceal an unhealthy dependency rather than solve it.

## 3. AWS spending triples overnight, no deployment

**Say:** “I treat this as both a cost anomaly and a possible security event.”

1. Break down cost by account, service, region and usage type in Cost Explorer/CUR (billing data can lag).
2. Look for autoscaling, NAT/data transfer, log ingestion, storage requests, managed databases and retries.
3. Review CloudTrail, IAM activity, resource changes and security alerts.
4. Safely contain unauthorized or nonessential usage without destroying critical workloads.
5. Set budgets, anomaly detection, tagging/ownership and preventive guardrails.

```bash
aws ec2 describe-instances --query 'Reservations[].Instances[].[InstanceId,State.Name]'
aws cloudtrail lookup-events --max-results 20
```

**Takeaway:** “No deployment” does not mean “no change in consumption or access.”

## 4. CI/CD takes 40+ minutes; target under 10 without more hardware

**Say:** “First measure stage durations and the critical path. Optimize repeated work rather than delete quality controls.”

- Cache dependencies and Docker layers; use deterministic cache keys.
- Parallelize independent tests; remove redundant jobs.
- Use incremental builds and targeted tests with a risk-based full-test policy.
- Build once, then promote the same signed/immutable artifact.
- Reduce checkout, artifact transfer, runner queue time and serial waits.
- Compare median and p95 runtime before and after, plus defect escape rate.

```bash
docker buildx build \
  --cache-from type=registry,ref=registry.example.com/app:cache \
  --cache-to type=registry,ref=registry.example.com/app:cache,mode=max \
  -t registry.example.com/app:build-123 .
```

**Takeaway:** Ten minutes is a measured target, not permission to skip security or essential tests.

## 5. Infrastructure green; developers say the product is slow

**Say:** “I believe neither color nor opinion alone. I reproduce the user journey and gather end-to-end evidence.”

- Measure p50/p95/p99 latency, errors, throughput and saturation.
- Compare regions, endpoints, tenant segments and recent changes.
- Check CPU **throttling** (not just usage), thread pools, GC, database locks, queue depth and downstream calls.
- Use distributed traces and synthetic user checks to find the latency hop.
- Fix and validate against user-facing service-level indicators (SLIs).

```bash
vmstat 1 5
iostat -xz 1 5
ss -s
curl -s -o /dev/null -w 'total=%{time_total}\n' https://example.com/
```

**Takeaway:** Green host dashboards can coexist with a broken user experience.

## 6. Terraform drift threatens critical live infrastructure

**Say:** “I do not blindly force desired state over production.”

1. Confirm state backend, workspace, locking and access.
2. Inspect the proposed plan and differentiate legitimate out-of-band changes from accidental drift.
3. Decide to codify the actual state, carefully revert the manual change, or import/move state as appropriate.
4. Assess replacement/downtime risk and obtain normal change approvals.
5. Apply a reviewed, narrowly scoped plan in a controlled window and verify service.

```bash
terraform state list
terraform plan -refresh-only
terraform plan -out=tfplan
terraform show tfplan
```

**Takeaway:** A plan showing destructive replacement is a warning, not an instruction to proceed.

## 7. Rollback script fails with an SLA deadline approaching

**Say:** “I declare or escalate the incident, establish a decision owner, and prioritize safe restoration.”

1. Confirm impact and freeze unrelated production changes.
2. Identify the failed rollback step and last known-good artifact/configuration.
3. Choose a supported alternative: Kubernetes rollout undo, blue/green traffic switch or verified DR process.
4. Validate compatibility, especially for **database/schema** changes.
5. Track error rate and latency while communicating impact and recovery status.

```bash
kubectl rollout history deployment/myapp -n production
# Execute only when the prior revision is known-good and compatible:
kubectl rollout undo deployment/myapp -n production
kubectl rollout status deployment/myapp -n production
```

**Takeaway:** SLA pressure does not justify an unsafe, irreversible production command.

## 8. A secret was pushed to GitHub and already cloned

**Say:** “Assume exposure persists outside Git, even if history is rewritten.”

1. Revoke/rotate the credential immediately; deploy replacement through a secret manager.
2. Check access logs and scope of potential compromise.
3. Escalate to security and follow incident, notification and evidence-retention processes.
4. Remove secret from current code and history where practical, but **never treat deletion as remediation**.
5. Add secret scanning, push protection, short-lived credentials and least privilege.

```bash
git log --all --oneline
# Search only in an authorized local clone; avoid printing real secrets into logs:
git grep -n 'EXPOSED_PATTERN' $(git rev-list --all)
```

**Takeaway:** Rotation first, Git cleanup second.

## 9. Upgrade succeeds in staging but production CoreDNS breaks

**Say:** “I restore name resolution first, then determine which production-specific difference triggered it.”

1. Pause further upgrade activity and establish the affected scope.
2. Check CoreDNS pods/logs, ConfigMap, kube-dns Service and EndpointSlices.
3. Test service DNS from affected pods and compare working versus failing nodes.
4. Check CoreDNS/add-on compatibility, CNI, network policy, upstream resolvers and node resolv.conf.
5. Restore a tested, compatible DNS configuration/add-on using the platform’s supported procedure.
6. Validate internal/external lookups and application health before continuing upgrades.

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system deployment/coredns
kubectl get configmap coredns -n kube-system -o yaml
kubectl get svc kube-dns -n kube-system
kubectl get endpointslices -n kube-system
kubectl exec -n production <pod-name> -- nslookup kubernetes.default.svc.cluster.local
```

**Takeaway:** Do not assume a control-plane upgrade can simply be downgraded.

## 10. Describe a failure **you** introduced

**Say:** “I will give a specific real example, own the decision, explain recovery, and show what permanently changed.”

Use a **truthful STAR** story:

- **Situation:** What production change were you making and why?
- **Task:** What were you responsible for?
- **Action:** What assumption or mistake caused the failure? When did you recognize it? How did you contain and recover?
- **Result:** How was recovery verified, who was informed and what prevention was introduced (peer review, canary, change testing, rollback rehearsal, better alerts)?

**Fill-in answer, not a claimed personal incident:**

> “During [real maintenance/change], I changed [component] based on [assumption]. That led to [measured impact]. I took ownership, [immediate containment], and restored service by [verified recovery action]. The post-incident review identified [root cause]. We introduced [specific control], and verified its effectiveness through [evidence].”

**Takeaway:** Accountability, detection, recovery and learning matter more than pretending you never made a mistake.

---

## Rapid-fire interview reminders

| Concept | Strong senior-level behavior |
| --- | --- |
| Blast radius | Assess who and what will be affected before changing production |
| Debugging | State hypothesis, collect evidence, test, revise |
| Reliability | Measure user-facing SLIs, not just machine status |
| Recovery | Know last good version, rollback limitations and validation |
| Security | Contain credentials before cleaning up repositories |
| Change management | Preserve state, document risk and review destructive changes |
| Incident leadership | Communicate impact, decisions, ownership and follow-up |

**Practice:** Deliver each response in 60–90 seconds: impact → first checks → discriminating evidence → safe mitigation → proof of recovery → prevention.

> Educational material. Sample commands are not a production runbook; inspect your environment and approval process first.
