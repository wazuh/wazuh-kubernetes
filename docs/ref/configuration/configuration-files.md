# Configuration Files

## Storage configuration

Persistent volumes are provisioned through the `wazuh-storage` `StorageClass`

- **Base definition**: The base StorageClass is defined in `wazuh/base/storage-class.yaml`
- **EKS overlay**: `envs/eks/storage-class.yaml` configures `wazuh-storage` to use AWS EBS with encrypted volumes and a `Retain` reclaim policy
- **Local overlay**: `envs/local-env/storage-class.yaml` configures `wazuh-storage` for local provisioners such as `microk8s.io/hostpath` or `k8s.io/minikube-hostpath`

Before deployment:

- Verify that the `provisioner` value matches a valid storage provisioner in your cluster (`kubectl get sc`), and in case of local deployment verify the contents of `envs/local-env/storage-class.yaml`

## Resource requests and replicas

CPU, memory, and storage settings are controlled via Kustomize patches under `envs/`

- **Indexer resources**:
  - EKS: `envs/eks/indexer-resources.yaml` adjusts `resources` and persistent volume size for the `wazuh-indexer` StatefulSet
  - Local: `envs/local-env/indexer-resources.yaml` reduces replicas and keeps modest resource requests for local development

- **Manager resources**:
  - EKS: `envs/eks/wazuh-master-resources.yaml` and `envs/eks/wazuh-worker-resources.yaml` configure CPU, memory, and persistent volume size for the Wazuh manager master and worker StatefulSets
  - Local: `envs/local-env/wazuh-resources.yaml` reduces the Wazuh manager workers to one replica. It and `envs/local-env/wazuh-master-resources.yaml` also narrow `WAZUH_INDEXER_HOSTS` of the worker and master StatefulSets to the single indexer, `wazuh-indexer-0.wazuh-indexer:9200`

## Ingress and external access

External access to the Wazuh dashboard is provided through a Traefik `IngressRouteTCP` with TLS passthrough

- The dashboard route is defined in `wazuh/base/ingressRoute-tcp-dashboard.yaml`
- The `HostSNI(...)` match must be updated with the fully qualified domain name (FQDN) you will use to access the dashboard

Typical values:

- **EKS**: DNS name of the load balancer created by the Traefik Service
- **Local environment**: leave the file empty and reach the dashboard with `kubectl port-forward`

## Network policies

Network policies restrict communication between pods to enforce security boundaries

- **Base policies**: Located in `wazuh/base/`
  - `default-deny-all.yaml`: Denies all ingress and egress traffic not explicitly allowed by other policies
  - `Allow-DNS-np.yaml`: Permits DNS resolution traffic to `kube-dns` in the `kube-system` namespace

- **EKS-specific policies**: Located in `envs/eks/network-policies/`
  - `allow-ingress-to-dashboard.yaml`: Allows ingress controller traffic to the Wazuh dashboard
  - `allow-ingress-to-manager-master.yaml`: Allows ingress controller traffic to the Wazuh manager master
  - `allow-ingress-to-manager-worker.yaml`: Allows ingress controller traffic to the Wazuh manager workers

## Credentials and secrets

The passwords of the Wazuh indexer and Wazuh API accounts are generated for each deployment by `tools/utils/deployment/credentials-conf.sh`, and reach the pods through the `indexer-credentials-<hash>`, `manager-credentials-<hash>` and `dashboard-credentials-<hash>` Secrets that `wazuh/kustomization.yml` generates from `wazuh/config/credentials/*.env`. See [Credentials](../credentials.md).

The same script generates the shared key for manager cluster membership, on port `1516`, into `wazuh/config/credentials/cluster.key`, which reaches the managers through the `wazuh-cluster-key-<hash>` Secret. It is not an account inside an image and `password-tool.sh` does not cover it: the managers read it from the Secret on every container start. See [The cluster key and the agent enrollment password](../credentials.md#the-cluster-key-and-the-agent-enrollment-password), which also covers changing it on a deployment that is already running.

The agent enrollment password is not in the manifests: the master generates a random one in `/var/wazuh-manager/etc/authd.pass` on its first start, and distributes it to the workers.

> **Important**: each component stores its passwords on its first start. Editing `config/credentials/*.env`, or the generated Secrets, afterwards does not change the accounts: [Credentials](../credentials.md#rotating-a-password-on-a-running-deployment) has the procedure.

## Persistence configuration

When customizing your Wazuh Kubernetes deployment, certain files and directories must be persisted to retain your changes across pod restarts and recreations. This is critical for maintaining custom configurations, user credentials, and security settings.

### PersistentVolumeClaims and ConfigMaps

Kubernetes uses PersistentVolumeClaims (PVCs) and ConfigMaps to persist data outside of pod lifecycles:

- **PersistentVolumeClaims**: Used for stateful data like logs, queues, and Indexer data. When a pod is deleted and recreated, data in PVCs remains intact.
- **ConfigMaps**: Used for configuration files. ConfigMaps can be mounted as files in pods and updated independently of the pod lifecycle.

The Wazuh deployment already uses PVCs for every directory that has to outlive a pod:

| Workload | Path | What it holds |
| --- | --- | --- |
| Manager master and worker | `/var/wazuh-manager/etc` | Configuration, `client.keys`, the agent enrollment password `authd.pass`, certificates |
| Manager master and worker | `/var/wazuh-manager/api/configuration` | Wazuh API configuration and its user database, `rbac.db`, on the master only |
| Manager master and worker | `/var/wazuh-manager/logs` | Manager logs |
| Manager master and worker | `/var/wazuh-manager/queue` | Agent state, queues, the manager databases, and the manager keystore (`queue/keystore`) with the `wazuh-manager` indexer password |
| Manager master and worker | `/var/wazuh-manager/var/multigroups` | Generated multigroup shared configuration |
| Manager master and worker | `/var/wazuh-manager/data` | Detection content: ruleset, IoC databases, GeoIP and time zone data |
| Indexer | `/var/lib/wazuh-indexer` | Indices, the security index (the accounts) and the `.initialized` marker |
| Dashboard | `/usr/share/wazuh-dashboard/config` | `opensearch_dashboards.yml` and the keystore |

Two of these need seeding, because a PVC starts empty where the equivalent Docker named volume
would have been filled from the image. An init container copies the content out of the image the
first time the claim is used:

- `/var/wazuh-manager/data` is not part of the manager image's permanent-data snapshot, so nothing
  would restore it at runtime. The image does refresh the subtrees it owns (`data/tzdb`,
  `data/store/schema`, `data/store/enrichment`) on every start, so upgrades still pick up new
  content.
- `/usr/share/wazuh-dashboard/config` holds `opensearch_dashboards.keystore`, which the dashboard
  entrypoint creates only when it is absent and which carries
  `wazuh_ai_assistant.encryptionKey`. Without the claim every dashboard pod would generate a new
  key and anything encrypted with the previous one would become unreadable. The claim also keeps
  `opensearch_dashboards.yml`, which the entrypoint rewrites from the environment on every start:
  the settings this deployment sets are therefore always current, but a setting a newer image
  ships and no environment variable covers stays at the value the claim was seeded with. Deleting
  the claim picks those up: the dashboard then takes its passwords again from `dashboard.env`, which
  must therefore hold the current values, and generates a new `wazuh_ai_assistant.encryptionKey`.

For additional configuration files, use ConfigMaps as described above.

> **Important**: When creating ConfigMaps for configuration files, ensure the file content is properly formatted and validated before applying. Malformed configuration files can prevent pods from starting.

For more information on Kubernetes storage concepts, refer to the official Kubernetes documentation:

- [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
