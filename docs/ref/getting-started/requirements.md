# Requirements

This page outlines the prerequisites and resource requirements for deploying Wazuh on Kubernetes. Ensure your cluster meets these requirements before proceeding with the deployment.

## Prerequisites

### Kubernetes Cluster

- A running Kubernetes cluster
- `kubectl` command-line tool configured to communicate with your cluster
- `kustomize` for applying manifests (built into kubectl 1.14+)

### Storage Class

A StorageClass must be configured in your cluster to provision persistent volumes for Wazuh components:

- **Local environments**: Uses local storage provisioners (e.g., `microk8s.io/hostpath`, `k8s.io/minikube-hostpath`)
- **Amazon EKS**: Requires Amazon EBS CSI driver with appropriate IAM role configuration

For EKS deployments using Kubernetes 1.23 or higher, you must configure an IAM role for the Amazon EBS CSI driver. Refer to the [AWS documentation](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html) for detailed instructions.

## Resource Requirements

### Minimum Cluster Resources

Your Kubernetes cluster must have at least the following resources available:

- **CPU**: 2 CPU cores
- **Memory**: 3 GiB RAM
- **Storage**: 2 GiB persistent storage

Production environments may require additional CPU, memory, and storage depending on the workload and number of monitored agents.
