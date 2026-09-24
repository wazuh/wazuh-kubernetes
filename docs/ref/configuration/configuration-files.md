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
  - Local: `envs/local-env/wazuh-resources.yaml` reduces the number of Wazuh manager worker replicas

## Ingress and external access

External access to the Wazuh dashboard is provided through an Ingress resource

- The base ingress is defined in `wazuh/base/wazuh-ingress.yaml`
- The `rules.host` field must be updated with the fully qualified domain name (FQDN) or host you will use to access the dashboard

Typical values:

- **EKS**: DNS name of the load balancer created by the ingress controller
- **Local environment**: `localhost` or another local hostname

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

Default credentials and keys are provided as Kubernetes Secrets under `wazuh/secrets/`. These values are meant to be customized before any production deployment, and the accounts behind them have to be changed inside the components as well. See [Credentials](../credentials.md) for the full procedure.

Main secrets:

- `wazuh/secrets/wazuh-api-cred-secret.yaml`
  Wazuh API `wazuh-wui` service account, read by the manager master and the dashboard.
- `wazuh/secrets/dashboard-cred-secret.yaml`
  Wazuh indexer `kibanaserver` service account the dashboard authenticates to the indexer with. This is not the login of the dashboard web interface.
- `wazuh/secrets/indexer-cred-secret.yaml`
  Wazuh indexer `wazuh-manager` service account, read by the manager master and the manager workers.
- `wazuh/secrets/wazuh-authd-pass-secret.yaml`
  Agent enrollment password, mounted as a file rather than an environment variable. It guards the enrollment `remoted` serves on port `1517` and the legacy `authd` port `1515`.
- `wazuh/secrets/wazuh-cluster-key-secret.yaml`
  Shared key for manager cluster membership, on port `1516`.

The last two are not accounts inside an image and `password-tool.sh` does not cover them: the managers read them from the Secret on every container start. **Change them before the first `kubectl apply -k`** — see [The cluster key and the agent enrollment password](../credentials.md#the-cluster-key-and-the-agent-enrollment-password), which also covers changing either one on a deployment that is already running.

> **Important**: these Secrets hold what the pods *present*. The Wazuh indexer StatefulSet reads no credential Secret at all, so editing `indexer-cred` does not change the password the indexer *accepts*.

## Persistence configuration

When customizing your Wazuh Kubernetes deployment, certain files and directories must be persisted to retain your changes across pod restarts and recreations. This is critical for maintaining custom configurations, user credentials, and security settings.

### PersistentVolumeClaims and ConfigMaps

Kubernetes uses PersistentVolumeClaims (PVCs) and ConfigMaps to persist data outside of pod lifecycles:

- **PersistentVolumeClaims**: Used for stateful data like logs, queues, and Indexer data. When a pod is deleted and recreated, data in PVCs remains intact.
- **ConfigMaps**: Used for configuration files. ConfigMaps can be mounted as files in pods and updated independently of the pod lifecycle.

The Wazuh deployment already uses PVCs for every directory that has to outlive a pod:

| Workload | Path | What it holds |
| --- | --- | --- |
| Manager master and worker | `/var/wazuh-manager/etc` | Configuration, `client.keys`, `authd.pass`, certificates |
| Manager master and worker | `/var/wazuh-manager/api/configuration` | Wazuh API configuration and its user database |
| Manager master and worker | `/var/wazuh-manager/logs` | Manager logs |
| Manager master and worker | `/var/wazuh-manager/queue` | Agent state, queues and the manager databases |
| Manager master and worker | `/var/wazuh-manager/var/multigroups` | Generated multigroup shared configuration |
| Manager master and worker | `/var/wazuh-manager/data` | Detection content: ruleset, IoC databases, GeoIP and time zone data |
| Indexer | `/var/lib/wazuh-indexer` | Indices |
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
  ships and no environment variable covers stays at the value the claim was seeded with. Delete
  the claim to pick those up, and set the passwords again afterwards.

For additional configuration files, use ConfigMaps as described above.

> **Important**: When creating ConfigMaps for configuration files, ensure the file content is properly formatted and validated before applying. Malformed configuration files can prevent pods from starting.

For more information on Kubernetes storage concepts, refer to the official Kubernetes documentation:

- [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
