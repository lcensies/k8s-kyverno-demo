# Kubernetes Policy Enforcement Demo with Kyverno

## Overview

This repository demonstrates how to implement and enforce Kubernetes security and best practices using **Kyverno**.

The goal of this project is to show how a **Kubernetes policy engine** can automatically validate and control workloads running in a cluster.

In this demo we:

* Deploy **Kyverno** as a Kubernetes policy engine
* Define security and best-practice policies
* Apply them to the cluster
* Demonstrate how non-compliant workloads are automatically rejected

This project can be used as a **simple presentation / proof-of-concept** showing how policy enforcement works in Kubernetes environments.

---

# Architecture

```
Developer → kubectl apply → Kubernetes API Server
                               │
                               ▼
                         Kyverno Admission Controller
                               │
                ┌──────────────┴──────────────┐
                │                             │
        Policy Valid ✓                 Policy Violation ✗
                │                             │
                ▼                             ▼
          Deployment Created          Request Rejected
```

Kyverno works as an **admission controller** in Kubernetes.
Every resource created in the cluster is evaluated against defined policies.

---

# Technologies Used

* Kubernetes
* Kyverno
* kubectl
* Helm
* Makefile automation

---

# Project Structure

```
k8s-kyverno-demo
│
├── Makefile
│
├── policies
│   ├── policy-no-latest.yaml
│   ├── policy-require-label.yaml
│   └── policy-resources.yaml
│
├── test
│   └── bad-deployment.yaml
│
└── README.md
```

---

# Policies Implemented

## 1 Disallow `latest` image tag

Using the `latest` tag is considered a bad practice because it makes deployments non-deterministic.

Policy goal:

* Prevent containers from running images with the `latest` tag.

Example violation:

```
image: nginx:latest
```

Example compliant image:

```
image: nginx:1.25
```

---

## 2 Require application labels

Labels are critical for:

* observability
* monitoring
* service discovery
* resource grouping

Policy goal:

Ensure all workloads contain the `app` label.

Example required metadata:

```
metadata:
  labels:
    app: my-service
```

---

## 3 Require CPU and memory limits

In production Kubernetes clusters it is important to define resource limits to avoid resource starvation.

Policy goal:

All containers must define:

* CPU limits
* Memory limits

Example:

```
resources:
  limits:
    cpu: "500m"
    memory: "256Mi"
```

---

# Installation

## 1 Start Kubernetes cluster

Example using **Minikube**:

```
minikube start
```

Check cluster status:

```
kubectl get nodes
```

---

## 2 Install Kyverno

Add Helm repository:

```
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
```

Install Kyverno:

```
helm install kyverno kyverno/kyverno -n kyverno --create-namespace
```

Verify installation:

```
kubectl get pods -n kyverno
```

---

# Applying Policies

All policies can be applied using the Makefile:

```
make apply
```

This command applies all policies from the `policies` directory.

Verify:

```
kubectl get clusterpolicy
```

---

# Testing Policy Enforcement

To test the policies, a deliberately incorrect deployment is provided.

This deployment violates the **no latest tag policy**.

Run:

```
make test
```

Expected result:

```
Error from server: admission webhook denied the request
latest tag is not allowed
```

This demonstrates that Kyverno correctly prevents non-compliant workloads.

---

# Cleanup

Remove test deployment:

```
make clean
```

---

# Example Workflow

Typical developer workflow with policies enabled:

1. Developer creates a Kubernetes manifest
2. Manifest is applied using `kubectl`
3. Kyverno intercepts the request
4. Policies are evaluated
5. Resource is either:

   * **accepted**
   * **rejected**

---

# Why Policy Engines Are Important

Policy engines provide:

* Security enforcement
* Compliance controls
* Governance automation
* Standardized cluster configurations

Without policy enforcement developers could accidentally deploy insecure workloads.

---

# Key Benefits of Kyverno

* Kubernetes-native policy definitions
* YAML based policies
* Easy integration
* Supports validation, mutation and generation rules

---

# Conclusion

This project demonstrates how **Kyverno can enforce Kubernetes best practices automatically**.

By implementing policy validation at the cluster level we ensure that:

* insecure deployments are prevented
* best practices are enforced
* cluster governance is maintained

This approach is commonly used in **production Kubernetes environments** to improve security and reliability.

---

# Possible Extensions

Future improvements could include:

* image vulnerability policies
* namespace isolation rules
* network policy enforcement
* automatic label mutation
* GitOps integration

---

# Demo Summary

This repository demonstrates:

✔ Installing a Kubernetes policy engine
✔ Defining cluster security policies
✔ Enforcing deployment best practices
✔ Automating validation with Kyverno

---

