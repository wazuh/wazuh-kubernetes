# Environment Variables

This page documents the runtime environment variables used by the Wazuh Kubernetes deployment in this repository.

Environment variables are defined directly in the workload manifests under `wazuh/` and, for credentials, are populated from Kubernetes Secrets.

## How variables are provided

Variables are provided in two ways:

- **Literal values in manifests**: Set with `value` in the container `env` section.
- **Secret-backed values**: Set with `valueFrom.secretKeyRef` and resolved from files under `wazuh/secrets/`.

For security, use custom secret values in your environment.

## Wazuh manager variables

Defined in:

- `wazuh/wazuh_managers/wazuh-master-sts.yaml`
- `wazuh/wazuh_managers/wazuh-worker-sts.yaml`

| Variable | Purpose | Source | Required | Default/current value |
| --- | --- | --- | --- | --- |
| `WAZUH_INDEXER_HOSTS` | Indexer endpoint used by managers. | Literal | Yes | `wazuh-indexer:9200` |
| `WAZUH_NODE_NAME` | Manager node identifier in the Wazuh cluster. | Literal (master), downward API (worker pod name) | Yes | Master: `master`; Worker: pod metadata name |
| `WAZUH_NODE_TYPE` | Declares manager role in cluster mode. | Literal | Yes | Master: `master`; Worker: `worker` |
| `WAZUH_REMOTE_BIND_ADDR` | Bind address `remoted` listens on for agent traffic. Written to `<remote><https><bind_addr>` and `<remote><legacy><local_ip>`. | Literal | Yes | `0.0.0.0` |
| `WAZUH_CLUSTER_BIND_ADDR` | Bind address for cluster communications. | Literal | Yes | `0.0.0.0` |
| `WAZUH_CLUSTER_NODES` | Cluster service name used for peer discovery. | Literal | Yes | `wazuh-cluster` |
| `INDEXER_USERNAME` | Indexer authentication username. | Secret `indexer-cred` | Yes | `wazuh-manager` |
| `INDEXER_PASSWORD` | Indexer authentication password. | Secret `indexer-cred` | Yes | `wazuh-manager` (shipped default) |
| `SSL_CERTIFICATE_AUTHORITIES` | CA certificate path used for indexer TLS. | Literal | Yes | `/etc/ssl/root-ca.pem` |
| `SSL_CERTIFICATE` | Client certificate path used for indexer TLS. | Literal | Yes | `/etc/ssl/filebeat.pem` |
| `SSL_KEY` | Client key path used for indexer TLS. | Literal | Yes | `/etc/ssl/filebeat-key.pem` |
| `API_USERNAME` | Wazuh API authentication username. | Secret `wazuh-api-cred` (master only) | Yes | `wazuh-wui` |
| `API_PASSWORD` | Wazuh API authentication password. | Secret `wazuh-api-cred` (master only) | Yes | `wazuh-wui` (shipped default) |
| `WAZUH_CLUSTER_KEY` | Shared key for manager cluster membership. | Secret `wazuh-cluster-key` | Yes | `123a45bc67def891gh23i45jk67l8mn9` (shipped default) |

### Manager customization notes

- Keep `WAZUH_NODE_TYPE` and `WAZUH_NODE_NAME` aligned with each StatefulSet role.
- Leave `WAZUH_REMOTE_BIND_ADDR` at `0.0.0.0`. The packaged configuration binds `remoted` to `127.0.0.1`, which inside a pod leaves ports `1517` and `1514` reachable only from the pod itself, so no agent could connect. Binding on all interfaces is scoped to the pod network namespace: what is actually reachable stays governed by the Services and the NetworkPolicies.
- Update `WAZUH_INDEXER_HOSTS` only if your Indexer service name/port differs from the default.
- Do not hardcode credentials in manifests; update the corresponding Secrets instead.
- The passwords above are the values the images ship, and every one of them equals its own username. Change them right after the first deployment: see [Credentials](../credentials.md).
- `WAZUH_CLUSTER_KEY` is rewritten into `<cluster><key>` of `/var/wazuh-manager/etc/wazuh-manager.conf` on every container start, so the value in the Secret always wins over what is on the persistent volume. It has to be 32 characters and identical on every manager node, which is why it is best set before the first deployment: changing it later means restarting the master and the workers together, and the nodes still on the old key cannot sync in the meantime. See [The cluster key and the agent enrollment password](../credentials.md#the-cluster-key-and-the-agent-enrollment-password).

## Wazuh indexer variables

Defined in:

- `wazuh/indexer_stack/wazuh-indexer/cluster/indexer-sts.yaml`

| Variable | Purpose | Source | Required | Default/current value |
| --- | --- | --- | --- | --- |
| `bootstrap.memory_lock` | Prevents indexer memory from being swapped. | Literal | Yes | `"true"` |
| `network.host` | Bind address for indexer node network interface. | Literal | Yes | `0.0.0.0` |
| `node.name` | Node name from pod metadata. | Downward API | Yes | Pod metadata name |
| `cluster.initial_cluster_manager_nodes` | Initial manager node list for cluster bootstrap. | Literal | Yes | `wazuh-indexer-0,wazuh-indexer-1,wazuh-indexer-2` |
| `discovery.seed_hosts` | Seed hosts for node discovery. | Literal (base and overlays may override) | Yes | Base: `wazuh-indexer-cluster` |
| `node.max_local_storage_nodes` | Maximum local storage nodes for shared storage path. | Literal | Optional | `3` |
| `plugins.security.allow_default_init_securityindex` | Enables initial security index bootstrap behavior. | Literal | Optional | `true` |
| `NODES_DN` | Distinguished names allowed for indexer nodes. | Literal | Yes | Certificate DNs for indexer nodes |
| `OPENSEARCH_JAVA_OPTS` | Java heap and JVM options for indexer process. | Literal | Yes | `-Xms1024m -Xmx1024m` |
| `DISCOVERY_SERVICE` | Headless service used for peer discovery. | Literal | Yes | `wazuh-indexer-cluster` |
| `KUBERNETES_NAMESPACE` | Runtime namespace from pod metadata. | Downward API | Yes | Pod metadata namespace |
| `DISABLE_INSTALL_DEMO_CONFIG` | Skips demo config installation in startup script. | Literal | Yes | `true` |

### Indexer customization notes

- `OPENSEARCH_JAVA_OPTS` is the primary memory tuning variable for performance sizing.
- For local/single-node deployments, overlays can change `discovery.seed_hosts` (for example in `envs/local-env/indexer-resources.yaml`).
- Dotted variable names (such as `discovery.seed_hosts`) are intentional and used by the container startup scripts.

## Wazuh dashboard variables

Defined in:

- `wazuh/indexer_stack/wazuh-dashboard/dashboard-deploy.yaml`

| Variable | Purpose | Source | Required | Default/current value |
| --- | --- | --- | --- | --- |
| `OPENSEARCH_HOSTS` | HTTPS endpoint for Wazuh Indexer. | Literal | Yes | `https://wazuh-indexer:9200` |
| `INDEXER_USERNAME` | Indexer authentication username for dashboard. | Secret `indexer-cred` | Yes | `wazuh-manager` |
| `INDEXER_PASSWORD` | Indexer authentication password for dashboard. | Secret `indexer-cred` | Yes | `wazuh-manager` (shipped default) |
| `DASHBOARD_USERNAME` | Dashboard internal service username. | Secret `dashboard-cred` | Yes | `kibanaserver` |
| `DASHBOARD_PASSWORD` | Dashboard internal service password. | Secret `dashboard-cred` | Yes | `kibanaserver` (shipped default) |
| `SERVER_SSL_ENABLED` | Enables HTTPS on dashboard server. | Literal | Yes | `"true"` |
| `SERVER_SSL_CERTIFICATE` | Dashboard TLS certificate path. | Literal | Yes | `/usr/share/wazuh-dashboard/certs/wazuh-dashboard.pem` |
| `SERVER_SSL_KEY` | Dashboard TLS key path. | Literal | Yes | `/usr/share/wazuh-dashboard/certs/wazuh-dashboard-key.pem` |
| `OPENSEARCH_SSL_CERTIFICATE_AUTHORITIES` | CA path used for indexer TLS verification. | Literal | Yes | `/usr/share/wazuh-dashboard/certs/root-ca.pem` |
| `WAZUH_API_URL` | Wazuh manager API endpoint used by dashboard. | Literal | Yes | `https://wazuh-api` |
| `API_USERNAME` | Wazuh API authentication username for dashboard. | Secret `wazuh-api-cred` | Yes | `wazuh-wui` |
| `API_PASSWORD` | Wazuh API authentication password for dashboard. | Secret `wazuh-api-cred` | Yes | `wazuh-wui` (shipped default) |

### Dashboard customization notes

- If you change service names, update `OPENSEARCH_HOSTS` and `WAZUH_API_URL` accordingly.
- Keep TLS-related variables consistent with mounted certificate paths.
- Rotate credentials by updating Secrets and restarting the workloads that read them. Updating a Secret is only half of it: the account inside the Wazuh indexer or the Wazuh API has to be changed too. See [Credentials](../credentials.md).

## Secret-backed variable mapping

The following Secret manifests provide values for environment variables:

- `wazuh/secrets/indexer-cred-secret.yaml`
  - `INDEXER_USERNAME`, `INDEXER_PASSWORD`
- `wazuh/secrets/wazuh-api-cred-secret.yaml`
  - `API_USERNAME`, `API_PASSWORD`
- `wazuh/secrets/dashboard-cred-secret.yaml`
  - `DASHBOARD_USERNAME`, `DASHBOARD_PASSWORD`
- `wazuh/secrets/wazuh-cluster-key-secret.yaml`
  - `WAZUH_CLUSTER_KEY`

A Secret consumed with `valueFrom.secretKeyRef` is read into the environment when the container starts, so after changing a value you have to re-apply your overlay **and** restart the workloads that read it:

```bash
kubectl -n wazuh rollout restart statefulset/wazuh-manager-master
kubectl -n wazuh rollout restart statefulset/wazuh-manager-worker
kubectl -n wazuh rollout restart deployment/wazuh-dashboard
```

`wazuh/secrets/wazuh-authd-pass-secret.yaml` is absent from the list above because it is mounted as a file at `/wazuh-config-mount/etc/authd.pass`, not exposed as an environment variable. The container copies it to `/var/wazuh-manager/etc/authd.pass` at every start, so it too is applied by restarting the manager StatefulSets.

> **Important**: changing a Secret does not change the account inside the Wazuh indexer or the Wazuh API. Both halves are covered in [Credentials](../credentials.md).
