# Kubernetes Policy Enforcement with Kyverno

**Course Project Report**  
March 2026

---

## 1. Introduction

### 1.1 Background

Kubernetes clusters are often shared between multiple teams. When anyone can run `kubectl apply`, it's easy for misconfigured workloads to slip through. Common issues include using `nginx:latest` (which can change without you noticing), forgetting CPU/memory limits so one pod hogs the whole node, or running privileged containers that can escape to the host. The goal of this project was to automatically reject bad workloads before they get stored in etcd.

### 1.2 Problem Statement

How do you stop non-compliant Kubernetes workloads from being deployed without manually reviewing every single manifest? Manual review doesn't scale when you have many teams and frequent deployments.

### 1.3 Objectives

- Set up Kyverno as an admission controller on a local cluster
- Write policies that enforce security and best practices
- Show that non-compliant workloads get rejected automatically
- Make it reproducible with a simple `make` command

---

## 2. Methods

### 2.1 Architecture

Kyverno works as a ValidatingAdmissionWebhook. The flow is:

1. User runs `kubectl apply`
2. Request hits the API server
3. After auth, it goes through mutating webhooks, then validating webhooks (where Kyverno sits)
4. Kyverno checks the resource against all ClusterPolicies
5. If it passes → resource gets persisted to etcd
6. If it fails → request is rejected and the user gets an error

We chose Kyverno because policies are plain YAML, no Rego or custom Go code. It runs in-cluster as a normal Deployment and supports validate, mutate, generate, and image verification.

### 2.2 Environment

- **Minikube** — local single-node cluster
- **Helm** — to install Kyverno
- **kubectl** — for applying resources
- **Makefile** — to automate setup and testing

Setup is done with `make start`, which starts Minikube, adds the Kyverno Helm repo, installs Kyverno, waits for it to be ready, and applies all policies. There's retry logic (up to 20 times) because the webhooks need a bit of time to register.

**Makefile (excerpt):**

```makefile
POLICY_DIR=policies
TEST_DIR=test

start: configure
	minikube start
	helm repo add kyverno https://kyverno.github.io/kyverno/ || true
	helm repo update
	helm upgrade --install kyverno kyverno/kyverno -n kyverno --create-namespace
	kubectl wait --for=condition=available deployment --all -n kyverno --timeout=120s
	@echo "Waiting for Kyverno webhooks to be ready..."; \
	for i in $$(seq 1 20); do \
		kubectl apply -f $(POLICY_DIR) 2>&1 && break; \
		echo "Retry $$i/20..."; \
		sleep 5; \
	done

apply:
	kubectl apply -f $(POLICY_DIR)

test:
	kubectl apply -f $(TEST_DIR)/deployment.yaml
```

### 2.3 Policies Implemented

**Policy 1: Disallow `latest` image tag** (`policy.yaml`)

The `latest` tag is mutable — the image content can change between pulls. That's a supply-chain risk (compromised registry could swap it) and breaks reproducibility. The policy uses pattern `"!*:latest"` to reject any image with that tag. Pinned tags like `nginx:1.25.3` are fine.

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-latest-tag
spec:
  validationFailureAction: Enforce
  rules:
    - name: check-image-tag
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "latest tag is not allowed"
        pattern:
          spec:
            containers:
              - image: "!*:latest"
```

**Policy 2: Require `app` label** (`policy-requires-labels.yaml`)

Labels are needed for monitoring and service discovery. Pods without an `app` label are rejected. The pattern checks `metadata.labels.app: "?*"` (any non-empty value).

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-app-label
spec:
  validationFailureAction: Enforce
  rules:
    - name: check-label
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "app label is required"
        pattern:
          metadata:
            labels:
              app: "?*"
```

**Policy 3: Require CPU and memory limits** (`policy-resources.yaml`)

Containers without limits can starve other workloads on the same node (noisy neighbour). The policy requires both `resources.limits.memory` and `resources.limits.cpu` to be set.

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resources
spec:
  validationFailureAction: Enforce
  rules:
    - name: check-resources
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "CPU and memory limits are required"
        pattern:
          spec:
            containers:
              - resources:
                  limits:
                    memory: "?*"
                    cpu: "?*"
```

All three policies use `validationFailureAction: Enforce`, so violations are blocked, not just logged.

### 2.4 Test Workload

`test/deployment.yaml` is a Deployment that deliberately violates the policies: it uses `nginx:latest` and has no resource limits. It does have the `app: nginx` label, so it would fail on policies 1 and 3.

**Non-compliant deployment** (`test/deployment.yaml`):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest   # VIOLATION: latest tag
        # VIOLATION: no resources.limits
```

**Compliant example** (would pass all policies):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.25.3
        resources:
          limits:
            cpu: "200m"
            memory: "128Mi"
```

---

## 3. Results

### 3.1 Installation and Setup

Running `make start` successfully brought up Minikube, installed Kyverno, and applied the policies. Kyverno pods came up in the `kyverno` namespace. Policy application sometimes needed a retry or two while webhooks were registering.

**Manual installation steps** (equivalent to `make start`):

```bash
minikube start
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm upgrade --install kyverno kyverno/kyverno -n kyverno --create-namespace
kubectl wait --for=condition=available deployment --all -n kyverno --timeout=120s
kubectl apply -f policies/
```

**Verify policies are loaded:**

```bash
kubectl get clusterpolicy
```

### 3.2 Policy Rejection

When running `make test` (which applies the test deployment):

```
Error from server: admission webhook "validate.kyverno.svc-fail" denied the request:

resource Deployment/default/nginx-test was blocked due to the following policies:

disallow-latest-tag:
  check-image-tag: latest tag is not allowed

require-resources:
  check-resources: CPU and memory limits are required
```

The request never reaches etcd. The deployment is rejected at the API layer before any pods are scheduled.

### 3.3 Policy Coverage

| Policy               | What it blocks                    | Action   |
|----------------------|-----------------------------------|----------|
| disallow-latest-tag  | Images with `:latest` tag         | Enforce  |
| require-app-label    | Pods without `app` label          | Enforce  |
| require-resources    | Pods without CPU/memory limits    | Enforce  |

A compliant workload would need: pinned image (e.g. `nginx:1.25.3`), `app` label, and both CPU and memory limits set.

---

## 4. Discussion

### 4.1 Findings

Kyverno was straightforward to install via Helm. No custom code — just YAML policies. The error messages are clear: you get the policy name and the specific rule that failed. Because it's an admission webhook, enforcement is cluster-wide and users can't bypass it by applying manifests directly.

Policies are auditable and fit well with GitOps (e.g. ArgoCD or Flux) since they're just files in a repo.

### 4.2 Limitations

- Policies only match `Pod` resources. Deployments create Pods via the template, so they get checked, but if we wanted to match Deployment directly we'd need to add that to the `match` section.
- No image vulnerability scanning — we're not checking for CVEs, just the `latest` tag.
- This demo uses a single Minikube node. Production would need Kyverno in HA mode (multiple replicas) to avoid a single point of failure.
- In a brownfield cluster with existing workloads, you'd want to run in `Audit` mode first to see what would fail, then switch to `Enforce`.

### 4.3 Future Work

- **Image verification** — use cosign with Kyverno's `verifyImages` to require signed images
- **Vulnerability scanning** — integrate Trivy Operator and block images with known CVEs
- **Mutation rules** — auto-inject default resource limits and security context instead of just rejecting
- **Network policies** — generate NetworkPolicies per namespace
- **CI integration** — run `kyverno test` in GitHub Actions to validate policies before merge

---

## 5. Conclusion

Kubernetes admission controllers, implemented here with Kyverno, provide a preventive layer that stops non-compliant workloads before they run. No runtime overhead — the decision happens at admission time.

We implemented three policies: image tag pinning, mandatory labels, and resource limits. The setup is reproducible with `make start` and `make test`. The main takeaway is to shift security left: enforce at admission rather than trying to fix things at runtime. Policies are code — they should be versioned, reviewed, and tested like any other part of the stack.

---

## References

- [Kyverno Documentation](https://kyverno.io/docs/)
- [Kubernetes Admission Controllers](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/)
- [Helm Charts — Kyverno](https://artifacthub.io/packages/helm/kyverno/kyverno)
