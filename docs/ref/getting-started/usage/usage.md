# Usage

This section describes the procedures to deploy and/or remove the Wazuh stack using a Kubernetes cluster, trhough the manifests and Kustomize overlays provided in this repository.

## Topics

<!-- - [Deployment](deployment.md): Step-by-step instructions to deploy Wazuh on Kubernetes locally or on EKS -->
- [Deployment](deployment/deployment.md): Step-by-step instructions to deploy Wazuh on Kubernetes locally or on EKS
- [Upgrade](upgrade.md): Guidance to upgrade Wazuh components while preserving persistent data if required
- [Cleanup](cleanup.md): Steps to remove the deployment from the cluster, including uninstalling resources and handling persistent volumes when the storage class uses a `Retain` reclaim policy.
