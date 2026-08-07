# Glossary

This section defines key terms used in the Wazuh Kubernetes documentation.

## ClusterIP Service

A Kubernetes Service type that exposes an internal virtual IP reachable only from within the cluster. In this deployment, services such as `wazuh-api`, `wazuh-events`, `wazuh-registration`, and `dashboard` use this internal-only model for component-to-component communication.

## Headless Service

A Kubernetes Service with `clusterIP: None` that provides direct DNS records for each pod instead of a single virtual IP. In this deployment, headless services support stable peer discovery for stateful components such as clustered managers and indexers.

## Ingress resource

A Kubernetes API resource that defines HTTP(S) routing rules from external traffic to internal Services. In this repository, the external exposure path is primarily implemented with Traefik CRDs (`IngressRouteTCP` and `MiddlewareTCP`), so Ingress is useful as a general concept and compatibility reference.

## Ingress controller

A Kubernetes component that watches ingress-related resources and configures a reverse proxy or load balancer. In this deployment, Traefik acts as the ingress controller and handles external routing to Wazuh endpoints.

## IngressRouteTCP

A Traefik custom resource that defines TCP entrypoints, matching rules, and backend service routing. In this repository, `IngressRouteTCP` objects expose Wazuh dashboard and manager ports while preserving protocol-specific behavior.

## Init container

A container that runs before application containers in the same pod to prepare runtime prerequisites. In this deployment, init containers are used for setup tasks such as seeding persistent configuration, fixing volume permissions, and applying required kernel tuning.

## Kustomization

A Kustomize configuration file (`kustomization.yml`) that declares resources, generators, and patches to build final manifests. This repository uses Kustomization files as the main deployment entrypoints for base and environment-specific stacks.

## MiddlewareTCP

A Traefik custom resource used to apply middleware to TCP routes (for example, source IP allow lists). In this deployment, `MiddlewareTCP` (`ip-allowlist`) is attached to TCP routes and can be tightened to trusted source ranges as needed.

## NetworkPolicy

A Kubernetes resource that controls how pods are allowed to communicate with each other and with external endpoints. In this deployment, NetworkPolicy objects are used to enforce default-deny behavior and to explicitly allow only the ingress and egress traffic required by the Wazuh managers, indexers, and dashboard.

## Overlay (Kustomize overlay)

A Kustomize configuration that modifies a set of base manifests for a specific environment. In this repository, overlays such as the EKS and local environment variants adjust storage classes, resource requests, replicas, and networking configuration while reusing the common Wazuh base manifests.

## PersistentVolumeClaim (PVC)

A Kubernetes claim for persistent storage requested by a pod. In this deployment, PVCs back stateful data for Wazuh managers and indexers so data survives pod restarts and rescheduling.

## Secret

A Kubernetes object used to store sensitive data such as credentials, passwords, and keys. In this repository, secrets provide authentication and trust material for manager, indexer, dashboard, and inter-service communication.

## StatefulSet

A Kubernetes workload controller for stateful applications that require stable pod identity and ordered lifecycle operations. In this deployment, StatefulSets run manager and indexer nodes that depend on stable naming and persistent volumes.

## StorageClass

A Kubernetes resource that defines classes of storage with specific provisioner and parameters. In this repository, `wazuh-storage` is customized by environment overlays to match local or cloud storage backends.

## Traefik CRD

A Traefik Custom Resource Definition that extends Kubernetes with Traefik-native routing objects. This deployment uses Traefik CRDs such as `IngressRouteTCP` and `MiddlewareTCP` to publish Wazuh endpoints.
