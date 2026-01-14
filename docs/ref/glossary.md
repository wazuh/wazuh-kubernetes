# Glossary

This section defines key terms used in the Wazuh Kubernetes documentation.

## NetworkPolicy

A Kubernetes resource that controls how pods are allowed to communicate with each other and with external endpoints. In this deployment, NetworkPolicy objects are used to enforce default-deny behavior and to explicitly allow only the ingress and egress traffic required by the Wazuh managers, indexers, and dashboard.

## Ingress controller

A Kubernetes component that processes Ingress resources and configures the underlying load balancer or proxy to route external traffic into the cluster. In this deployment, an Nginx-based Ingress controller exposes the Wazuh dashboard and related HTTP(S) endpoints to users outside the cluster.

## Ingress resource

A Kubernetes API resource that defines application-level routing rules for HTTP(S) traffic entering the cluster. In this deployment, the Ingress resource maps a DNS host (for example, the Wazuh dashboard URL) to the corresponding Kubernetes Service, providing a single external entry point for the Wazuh web interface.

## Overlay (Kustomize overlay)

A Kustomize configuration that modifies a set of base manifests for a specific environment. In this repository, overlays such as the EKS and local environment variants adjust storage classes, resource requests, replicas, and networking configuration while reusing the common Wazuh base manifests.
