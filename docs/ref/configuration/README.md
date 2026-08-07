# Configuration

This page describes the main configuration options for deploying Wazuh using this repository. It explains how to adjust the manifests for your environment before applying the Kustomize overlays

## Configuration overview

The deployment is organized in two layers:

- **Base manifests**: Located in `wazuh/`. They define the Wazuh namespace, storage class, ingress, services, StatefulSets, Deployments, and Secrets
- **Environment overlays**: Located in `envs/eks/` and `envs/local-env/`. They reuse the base manifests and apply environment‑specific patches (storage, resources, replicas)

Select the overlay that matches your environment and customize the files in `envs/<environment>/` before running `kubectl apply -k`

For deployment steps, refer to:

- EKS clusters: [Usage: AWS EKS Deployment](../installation.md#eks-deployment)
- Local clusters: [Usage: Local Deployment](../installation.md#local-deployment)
