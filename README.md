# Kubernetes Policy Enforcement with Kyverno

> Course project demonstrating automated policy enforcement in Kubernetes using Kyverno.

---

## Table of Contents

1. [Introduction](#introduction)
2. [Methods](#methods)
3. [Results](#results)
4. [Discussion](#discussion)
5. [Quick Start](#quick-start)

---

## Introduction

### Background

Modern cloud-native applications run on Kubernetes clusters shared by multiple teams. Without guardrails, developers can accidentally deploy workloads that are insecure, resource-hungry, or poorly labelled — causing outages, security incidents, and operational pain.

**Kyverno** is a Kubernetes-native policy engine that enforces rules at the admission controller level. Every resource submitted to the API server is evaluated against defined policies before being accepted or rejected. No custom code is required — policies are plain YAML.

### Problem Statement

How can a Kubernetes cluster automatically prevent non-compliant workloads from being deployed, without requiring manual code review of every manifest?

### Goals

- Deploy Kyverno as an admission controller in a local Kubernetes cluster
- Define and apply security and best-practice policies
- Demonstrate automatic rejection of non-compliant workloads
- Provide a reproducible proof-of-concept suitable for production adoption

---

## Methods

### Architecture

```
Developer → kubectl apply → Kubernetes API Server
                                   │
                                   ▼
                         Kyverno Admission Webhook
                                   │
                    ┌──────────────┴──────────────┐
                    │                             │
            Policy Valid ✓                 Policy Violation ✗
                    │                             │
                    ▼                             ▼
              Resource Created            Request Rejected
                                     (error returned to user)
```

Kyverno registers itself as a **ValidatingAdmissionWebhook**. The API server forwards every create/update request to Kyverno before persisting it to etcd. Kyverno evaluates the resource against all matching `ClusterPolicy` rules and either allows or denies the request.

### Tools & Technologies

| Tool | Purpose |
|------|---------|
| Kubernetes (Minikube) | Local cluster for testing |
| Kyverno | Policy engine / admission controller |
| Helm | Kyverno installation |
| kubectl | Cluster interaction |
| Makefile | Automation of common commands |

### Project Structure

```
k8s-kyverno-demo/
│
├── Makefile                          # Automation targets (apply / test / clean)
│
├── policies/
│   ├── policy.yaml                   # Disallow latest image tag
│   ├── policy-requires-labels.yaml   # Require app label on Pods
│   └── policy-resources.yaml         # Require CPU and memory limits
│
└── test/
    └── deployment.yaml               # Non-compliant deployment (triggers rejection)
```

### Policies Implemented

#### 1. Disallow `latest` image tag (`policy.yaml`)

Using the `latest` tag makes deployments non-deterministic — a re-pull may bring a different image version. This policy **rejects any Pod** whose container image uses the `latest` tag.

```yaml
# Violation example
image: nginx:latest

# Compliant example
image: nginx:1.25
```

#### 2. Require `app` label (`policy-requires-labels.yaml`)

Labels are essential for observability, monitoring, and service discovery. This policy **rejects any Pod** that does not carry an `app` label.

```yaml
# Required metadata
metadata:
  labels:
    app: my-service
```

#### 3. Require CPU and memory limits (`policy-resources.yaml`)

Containers without resource limits can consume all available node resources, starving neighbouring workloads. This policy **rejects any Pod** whose containers do not define both `cpu` and `memory` limits.

```yaml
resources:
  limits:
    cpu: "500m"
    memory: "256Mi"
```

### Test Workload

`test/deployment.yaml` is a deliberately non-compliant `nginx:latest` deployment used to verify that Kyverno correctly blocks policy violations.

---

## Results

### Installation

**1. Start a local Kubernetes cluster:**

```bash
minikube start
kubectl get nodes
```

**2. Install Kyverno via Helm:**

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm install kyverno kyverno/kyverno -n kyverno --create-namespace
kubectl get pods -n kyverno
```

**3. Apply all policies:**

```bash
make apply
kubectl get clusterpolicy
```

**4. Trigger a policy violation:**

```bash
make test
```

Expected output:

```
Error from server: admission webhook "validate.kyverno.svc-fail" denied the request:
resource Deployment/default/nginx-test was blocked due to the following policies:
  disallow-latest-tag:
    check-image-tag: latest tag is not allowed
```

**5. Clean up:**

```bash
make clean
```

### Observed Behaviour

| Scenario | Outcome |
|----------|---------|
| Pod with `nginx:latest` | Rejected — violates `disallow-latest-tag` |
| Pod without `app` label | Rejected — violates `require-app-label` |
| Pod without resource limits | Rejected — violates `require-resources` |
| Pod with `nginx:1.25`, correct labels, and limits | Accepted |

---

## Discussion

### Key Findings

- Kyverno enforces policies **transparently** — developers receive clear error messages explaining exactly which policy was violated and why.
- Policies are defined in **plain YAML**, requiring no custom controllers or Go code, which lowers the barrier to adoption.
- The admission webhook approach means enforcement is **cluster-wide** and cannot be bypassed by individual users.

### Limitations

- The test deployment (`nginx:latest`) violates the `disallow-latest-tag` policy. A compliant deployment is not included in this demo but can be added by specifying a pinned image tag and resource limits.
- Policies currently target `Pod` resources only. Extending to `Deployment`, `DaemonSet`, etc. requires additional `match` entries.
- This demo runs on Minikube; production setups require HA Kyverno installation with multiple replicas.

### Future Work

- Add policies for image vulnerability scanning (Kyverno + Trivy)
- Implement namespace isolation and network policy enforcement
- Add **mutation rules** to automatically inject labels or set default resource limits
- Integrate with a GitOps pipeline (ArgoCD / Flux) so policies are applied declaratively

---

## Presentation Notes

- Slides: maximum 12 (follow IMRAD structure)
- Video: 3–5 minutes demonstrating the live `make test` rejection
- Include the architecture diagram from the [Methods](#methods) section

---

## References

- [Kyverno Documentation](https://kyverno.io/docs/)
- [Kubernetes Admission Controllers](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/)
- [Helm Charts — Kyverno](https://artifacthub.io/packages/helm/kyverno/kyverno)
