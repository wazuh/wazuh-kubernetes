# Security

This section summarizes security recommendations for Wazuh Kubernetes deployments. Apply the controls that match your environment and risk profile.

## Credentials and secrets

- Do not use default credentials. The default values for the Wazuh API, Dashboard, and Indexer credentials are stored in `wazuh/secrets/`.
- Update the base64-encoded values in the following secret files before deploying to production:
  - `wazuh/secrets/wazuh-api-cred-secret.yaml` - Wazuh API username and password
  - `wazuh/secrets/dashboard-cred-secret.yaml` - Dashboard username and password
  - `wazuh/secrets/indexer-cred-secret.yaml` - Indexer username and password
  - `wazuh/secrets/wazuh-authd-pass-secret.yaml` - Authd password for agent enrollment
  - `wazuh/secrets/wazuh-cluster-key-secret.yaml` - Cluster communication key
- For production deployments, consider using external secret management solutions integrated with Kubernetes.
- Rotate credentials regularly and after any suspected exposure.

## Certificates and TLS

- Protect the generated certificates created by the `wazuh-certs-tool.sh` script. Limit filesystem permissions and do not commit them to version control.
- The deployment uses TLS for:
  - Indexer cluster communication (node-to-node)
  - Indexer API access (dashboard and manager connections)
  - Manager-to-indexer communication
  - Dashboard HTTPS access (when using ingress with TLS)
- Certificates are stored as Kubernetes Secrets and mounted into pods at runtime.
- For production deployments, use certificates signed by a trusted Certificate Authority (CA) rather than self-signed certificates.
- Ensure certificate DNS names match the service names and external endpoints used in your deployment.

## Network exposure

- Restrict access to exposed service ports using Kubernetes NetworkPolicies, cloud provider security groups, and firewall rules.
- The deployment includes NetworkPolicies in `wazuh/base/` and `envs/eks/network-policies/`:
  - `default-deny-all.yaml` - Denies all traffic by default
  - `Allow-DNS-np.yaml` - Permits DNS resolution
  - EKS-specific policies for ingress controller access
- Review and customize NetworkPolicies for your environment before deployment.
- Do not expose internal-only endpoints to untrusted networks. In particular:
  - **Indexer API** (port `9200`): Restrict to manager and dashboard pods only
  - **Wazuh API** (port `55000`): Limit access to dashboard and administrative networks
  - **Cluster communication** (port `1516`): Keep internal to the cluster
- Use Ingress resources with TLS termination for external access to the dashboard.
- Consider using a service mesh (e.g., Istio, Linkerd) for additional network security controls and mTLS between services.

## RBAC and service accounts

- Apply the principle of least privilege to Kubernetes RBAC roles and service accounts.
- Review the default service accounts used by Wazuh pods and create custom ServiceAccounts with minimal permissions if needed.
- Restrict `kubectl` access to the `wazuh` namespace to authorized administrators only.
- Use Kubernetes audit logging to monitor access to secrets and sensitive resources.
- Consider using Pod Security Standards or Pod Security Policies to restrict pod capabilities:
  - The indexer requires `SYS_CHROOT` capability and privileged init containers for `vm.max_map_count`
  - The manager requires `SYS_CHROOT` capability
  - Review and minimize capabilities based on your security requirements

## Storage and persistent volumes

- Ensure PersistentVolumes are backed by encrypted storage:
  - For EKS: Use encrypted EBS volumes (configured in `envs/eks/storage-class.yaml`)
  - For other cloud providers: Enable encryption in the StorageClass configuration
  - For on-premises: Use encrypted storage backends
- Set appropriate `reclaimPolicy` on StorageClasses:
  - `Retain` for production data (prevents accidental deletion)
  - `Delete` only for development environments
- Restrict access to PersistentVolumes at the storage layer (filesystem permissions, volume encryption).
- Regularly back up PersistentVolumes containing critical data.

## Host and cluster hardening

- Run Kubernetes on hardened nodes (patched OS, minimal installed packages, restricted SSH access).
- Keep Kubernetes and node components up to date with security patches.
- Use private node pools or networks for sensitive workloads.
- Enable Kubernetes audit logging and monitor for suspicious activity.
- Consider using container security scanning tools to detect vulnerabilities in Wazuh images.
- Apply resource limits to prevent resource exhaustion attacks (already configured in the deployment manifests).
- Use namespace isolation and resource quotas to limit the impact of compromised workloads.
