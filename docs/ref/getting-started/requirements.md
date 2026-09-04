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

## Network ports

The Wazuh manager pods listen on the following ports:

- `1517/TCP`: Agent communication and enrollment for Wazuh 5.x agents. Since 5.0.0 the agent enrolls over the same HTTPS channel it uses to report, so this is the only port a 5.x agent needs. Served by every manager node (master and workers) through the `wazuh-agents` Service.
- `1514/TCP`: Agent communication for Wazuh 4.x agents (legacy `remoted`). Kept for backward compatibility, not used by 5.x agents. Served by the worker nodes through the `wazuh-events` Service.
- `1515/TCP`: Agent enrollment for Wazuh 4.x agents (`wazuh-authd`). Kept for backward compatibility, not used by 5.x agents. Served by the master node through the `wazuh-registration` Service.
- `55000/TCP`: Wazuh API, served by the master node through the `wazuh-api` Service.
- `1516/TCP`: Cluster communication between manager nodes. Only needed between the manager pods, never exposed outside the cluster.

Ports `1517`, `1514` and `1515` are published outside the cluster by the Traefik ingress controller, which forwards them as raw TCP. Traefik takes no part in the encryption, so a 5.x agent validates the manager certificate end to end over `1517`.

## Resource Requirements

### Minimum Cluster Resources

Production environments may require additional CPU, memory, and storage depending on the workload and number of monitored agents.

#### EKS

To deploy Wazuh on Kubernetes on AWS EKS, the cluster should have at least the following resources available:

- 4 CPU units
- 8 Gi of memory

#### Locally

To deploy Wazuh on Kubernetes locally, the cluster should have at least the following resources available:

- 2 CPU units
- 4.5 Gi of memory
