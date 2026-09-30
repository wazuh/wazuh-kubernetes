# Security

This section summarizes security recommendations for Wazuh Kubernetes deployments. Apply the controls that match your environment and risk profile.

## Credentials and secrets

- **No default passwords.** The images ship none. `tools/utils/deployment/credentials-conf.sh` generates random passwords for each deployment before its first start, and each component stores them on that start. Change them later with `password-tool.sh`. [Credentials](credentials.md) has the procedure.
- `wazuh/config/credentials/*.env` holds the deployment's passwords in clear text. It is in `.gitignore`: keep it out of your commits and restrict access to it.
- The pods receive those files as Secrets, copied by an init container into a root-only file: the passwords are not in the pod spec or the container environment, and the service users cannot read them. Anyone who can read Secrets in the `wazuh` namespace can, so restrict that permission.
- Two Secrets under `wazuh/secrets/` hold shared keys:
  - `wazuh/secrets/wazuh-authd-pass-secret.yaml` - Password of the legacy `authd` enrollment on port `1515`, for Wazuh 4.x agents
  - `wazuh/secrets/wazuh-cluster-key-secret.yaml` - Cluster communication key
- **Set the cluster key and the legacy enrollment password before you deploy.** These last two are not accounts inside an image, so `password-tool.sh` does not cover them: the managers read them from the Secrets on every container start. Both ship with a public value meant to be replaced (`REPLACETHISCLUSTERKEYBEFOREDEPLO` and `password`), and changing the cluster key on a running deployment degrades the manager cluster until every manager pod has restarted on the new key. See [The cluster key and the legacy enrollment password](credentials.md#the-cluster-key-and-the-legacy-enrollment-password).
- A base64 value in a Secret manifest is encoding, not encryption. Keep changed values out of version control and restrict read access to the deployment directory.
- For production deployments, consider using external secret management solutions integrated with Kubernetes.
- Rotate credentials regularly and after any suspected exposure. `tools/tests/check-default-credentials.sh` asserts that no account authenticates with its own username as its password.

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
  - **Cluster communication** (port `1516`): Keep internal to the cluster. The key in `wazuh/secrets/wazuh-cluster-key-secret.yaml` is what a node has to present to join the manager cluster
  - **Agent communication and enrollment** (port `1517`): Reachable by your agents only. Wazuh 5.x agents enroll on it with a token minted through the Wazuh API, so the API credentials are what protects it from unwanted registrations
  - **Legacy enrollment** (port `1515`): Only for Wazuh 4.x agents, protected by the password in `wazuh/secrets/wazuh-authd-pass-secret.yaml`
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
