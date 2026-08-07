# Compatibility

This section provides information about the compatibility of the Wazuh Kubernetes deployment with different platforms and configurations.

## Supported platforms

### Kubernetes versions

- Kubernetes 1.23 or higher is recommended for optimal compatibility with storage drivers and features.
- Earlier versions may work but are not officially tested or supported.

### Cloud platforms and distributions

- **Amazon EKS**: Supported with the Amazon EBS CSI driver for persistent storage.
- **Local Kubernetes distributions**: Including Minikube, MicroK8s, and kind for development and testing.
- **Other managed Kubernetes services**: Google GKE, Azure AKS, and similar platforms should work with appropriate storage class configurations.

### Storage class requirements

A compatible StorageClass must be available in your cluster:

- **Local environments**: Local storage provisioners such as `microk8s.io/hostpath`, `k8s.io/minikube-hostpath`, or `standard`.
- **Amazon EKS**: Requires the Amazon EBS CSI driver with appropriate IAM role configuration for Kubernetes 1.23+.
- **Other cloud providers**: Use the respective CSI drivers (e.g., GCE Persistent Disk for GKE, Azure Disk for AKS).

The storage class must support dynamic volume provisioning and should provide low-latency storage, especially for the Wazuh Indexer component.

### Container runtime

- Compatible with any Kubernetes-compliant container runtime (i.e., containerd or CRI-O).
- No specific runtime dependencies or restrictions.

## Resource constraints

For detailed information on resource requirements and recommendations, refer to the [Requirements](../getting-started/requirements.md) section.

### Network requirements

- The cluster must support NetworkPolicies if network segmentation is desired.
- Ingress controller required for external access to the Wazuh Dashboard (e.g., Traefik, NGINX Ingress).
- DNS resolution must be functional within the cluster for service discovery.
