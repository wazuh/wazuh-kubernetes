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
| `WAZUH_CLUSTER_BIND_ADDR` | Bind address for cluster communications. | Literal | Yes | `0.0.0.0` |
| `WAZUH_CLUSTER_NODES` | Cluster service name used for peer discovery. | Literal | Yes | `wazuh-cluster` |
| `INDEXER_USERNAME` | Indexer authentication username. | Secret `indexer-cred` | Yes | `<indexer-username>` |
| `INDEXER_PASSWORD` | Indexer authentication password. | Secret `indexer-cred` | Yes | `<indexer-password>` |
| `SSL_CERTIFICATE_AUTHORITIES` | CA certificate path used for indexer TLS. | Literal | Yes | `/etc/ssl/root-ca.pem` |
| `SSL_CERTIFICATE` | Client certificate path used for indexer TLS. | Literal | Yes | `/etc/ssl/filebeat.pem` |
| `SSL_KEY` | Client key path used for indexer TLS. | Literal | Yes | `/etc/ssl/filebeat-key.pem` |
| `API_USERNAME` | Wazuh API authentication username. | Secret `wazuh-api-cred` | Yes | `<wazuh-api-username>` |
| `API_PASSWORD` | Wazuh API authentication password. | Secret `wazuh-api-cred` | Yes | `<wazuh-api-password>` |
| `WAZUH_CLUSTER_KEY` | Shared key for manager cluster membership. | Secret `wazuh-cluster-key` | Yes | `<wazuh-cluster-key>` |

### Manager customization notes

- Keep `WAZUH_NODE_TYPE` and `WAZUH_NODE_NAME` aligned with each StatefulSet role.
- Update `WAZUH_INDEXER_HOSTS` only if your Indexer service name/port differs from the default.
- Do not hardcode credentials in manifests; update the corresponding Secrets instead.

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
| `INDEXER_USERNAME` | Indexer authentication username for dashboard. | Secret `indexer-cred` | Yes | `<indexer-username>` |
| `INDEXER_PASSWORD` | Indexer authentication password for dashboard. | Secret `indexer-cred` | Yes | `<indexer-password>` |
| `DASHBOARD_USERNAME` | Dashboard internal service username. | Secret `dashboard-cred` | Yes | `<dashboard-username>` |
| `DASHBOARD_PASSWORD` | Dashboard internal service password. | Secret `dashboard-cred` | Yes | `<dashboard-password>` |
| `SERVER_SSL_ENABLED` | Enables HTTPS on dashboard server. | Literal | Yes | `"true"` |
| `SERVER_SSL_CERTIFICATE` | Dashboard TLS certificate path. | Literal | Yes | `/usr/share/wazuh-dashboard/certs/wazuh-dashboard.pem` |
| `SERVER_SSL_KEY` | Dashboard TLS key path. | Literal | Yes | `/usr/share/wazuh-dashboard/certs/wazuh-dashboard-key.pem` |
| `OPENSEARCH_SSL_CERTIFICATE_AUTHORITIES` | CA path used for indexer TLS verification. | Literal | Yes | `/usr/share/wazuh-dashboard/certs/root-ca.pem` |
| `WAZUH_API_URL` | Wazuh manager API endpoint used by dashboard. | Literal | Yes | `https://wazuh-api` |
| `API_USERNAME` | Wazuh API authentication username for dashboard. | Secret `wazuh-api-cred` | Yes | `<wazuh-api-username>` |
| `API_PASSWORD` | Wazuh API authentication password for dashboard. | Secret `wazuh-api-cred` | Yes | `<wazuh-api-password>` |

### Dashboard customization notes

- If you change service names, update `OPENSEARCH_HOSTS` and `WAZUH_API_URL` accordingly.
- Keep TLS-related variables consistent with mounted certificate paths.
- Rotate credentials by updating Secrets and redeploying workloads.

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

After changing Secret values, re-apply your overlay and restart affected pods if required.
