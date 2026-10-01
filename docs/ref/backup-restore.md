# Backup and restore

For backup and restore procedures, refer to the documentation for each component:

- [Wazuh manager](https://github.com/wazuh/wazuh/blob/v5.0.1/docs/ref/backup-restore.md)
- [Wazuh agent](https://github.com/wazuh/wazuh-agent/blob/v5.0.1/docs/ref/backup-restore.md)

## Kubernetes-specific considerations

When backing up Wazuh deployments on Kubernetes, also consider:

### PersistentVolume backups

- Wazuh manager, indexer and dashboard state is stored in PersistentVolumes:
  - Indexer: the indices, the security index (internal users and their passwords) and the `.initialized` marker
  - Manager master: the Wazuh API user database, `rbac.db`, under `api/configuration`
  - Manager master and workers: the manager keystore, `queue/keystore`, with the `wazuh-manager` indexer password
  - Dashboard: its keystore (`opensearch.password`, `wazuh_core.hosts.default.password`, `wazuh_ai_assistant.encryptionKey`) and `opensearch_dashboards.yml`, on the `wazuh-dashboard-config` claim
- Use your storage provider's snapshot or backup capabilities:
  - **AWS EBS**: EBS snapshots via AWS Backup or manual snapshots
  - **GCP Persistent Disk**: Disk snapshots
  - **Azure Disk**: Disk snapshots
  - **On-premises**: Storage backend-specific backup tools
- Consider using Kubernetes backup tools like Velero for automated PV backups.

### Secrets and configuration

Back up the following files, from which kustomize generates the Secrets:

- `wazuh/config/credentials/*.env` - The deployment's passwords, including any rotated with `password-tool.sh`. Without them `kubectl apply -k` fails, and generating them again produces passwords that do not match the ones stored on the volumes
- `wazuh/secrets/wazuh-authd-pass-secret.yaml` - Agent enrollment password
- `wazuh/secrets/wazuh-cluster-key-secret.yaml` - Cluster communication key
- `wazuh/config/{indexer,manager,dashboard,root-ca}/certs/` - What the `*-certs` Secrets are generated from
- `wazuh/wazuh-certificates/` - Output of `wazuh-certs-tool.sh`, including `root-ca.key`, needed to issue new certificates

Also back up any custom ConfigMaps you have created for configuration file persistence.

Store backups securely and encrypt them: the credentials files and the private keys are in clear text.

### Restore

Restore the PersistentVolume snapshots and `wazuh/config/credentials/*.env` from the same point in
time. A password rotated after the snapshot is in the files but not on the volumes, or the other way
round, and the component that consumes it fails to authenticate. Put the files back before running
`kubectl apply -k`. Deleting a claim instead of restoring it makes its pod take its credentials again
from the Secret.

### Manifest files

- Maintain version-controlled copies of all Kubernetes manifests, including customizations in `envs/`.
- This allows you to recreate the deployment configuration even if the cluster is lost.
