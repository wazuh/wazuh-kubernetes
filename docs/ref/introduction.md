# Introduction to the Reference Manual

This reference manual provides comprehensive documentation for deploying and managing Wazuh on Kubernetes clusters. It covers deployment architecture, configuration management with Kustomize, compatibility requirements, and step-by-step instructions for both cloud and local environments.

## Description

This repository enables you to deploy a complete Wazuh stack on a Kubernetes cluster. It provides manifests and Kustomize overlays for deploying Wazuh managers, indexers, and dashboards with high availability and persistent storage.

### Key Features

- **Kustomize-based configuration**: Modular and reusable manifests organized with Kustomize for environment-specific customization without template duplication
- **Multi-environment support**: Pre-configured overlays for Amazon EKS clusters and local development environments (Minikube, Kind)
- **High availability**: StatefulSet controllers for Wazuh managers and indexers with pod anti-affinity rules for distributing workloads across nodes
- **Persistent storage**: Automatic provisioning of persistent volumes for data retention across pod restarts
- **Secure by default**: TLS/SSL certificate management, secrets handling, and network isolation via Kubernetes namespaces
- **Production-ready components**:
  - Wazuh manager cluster (master and worker nodes) for security event processing
  - Wazuh indexer cluster for data storage and search capabilities
  - Wazuh dashboard for visualization and management interface
