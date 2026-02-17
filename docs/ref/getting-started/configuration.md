# Configuration

This page describes the main configuration options for deploying Wazuh using this repository. It explains how to adjust the manifests for your environment before applying the Kustomize overlays

## Configuration overview

The deployment is organized in two layers:

- **Base manifests**: Located in `wazuh/`. They define the Wazuh namespace, storage class, ingress, services, StatefulSets, Deployments, and Secrets
- **Environment overlays**: Located in `envs/eks/` and `envs/local-env/`. They reuse the base manifests and apply environment‑specific patches (storage, resources, replicas)

Select the overlay that matches your environment and customize the files in `envs/<environment>/` before running `kubectl apply -k`

For deployment steps, refer to:

- EKS clusters: [Usage: AWS EKS Deployment](usage/deployment/eks.md)
- Local clusters: [Usage: Local Deployment](usage/deployment/local.md)

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

Default credentials and keys are provided as Kubernetes Secrets under `wazuh/secrets/`. These values are meant to be customized before any production deployment.

Main secrets:

- `wazuh/secrets/wazuh-api-cred-secret.yaml`
  Wazuh API username and password.
- `wazuh/secrets/dashboard-cred-secret.yaml`
  Wazuh dashboard (Kibana) username and password.
- `wazuh/secrets/indexer-cred-secret.yaml`
  Wazuh indexer username and password.

## Persistence configuration

When customizing your Wazuh Kubernetes deployment, certain files and directories must be persisted to retain your changes across pod restarts and recreations. This is critical for maintaining custom configurations, user credentials, and security settings.

### PersistentVolumeClaims and ConfigMaps

Kubernetes uses PersistentVolumeClaims (PVCs) and ConfigMaps to persist data outside of pod lifecycles:

- **PersistentVolumeClaims**: Used for stateful data like logs, queues, and Indexer data. When a pod is deleted and recreated, data in PVCs remains intact.
- **ConfigMaps**: Used for configuration files. ConfigMaps can be mounted as files in pods and updated independently of the pod lifecycle.

The Wazuh deployment already uses PVCs for critical directories like `/var/ossec/etc`, `/var/ossec/logs`, and `/var/lib/wazuh-indexer`. For additional configuration files, use ConfigMaps as described above.

> **Important**: When creating ConfigMaps for configuration files, ensure the file content is properly formatted and validated before applying. Malformed configuration files can prevent pods from starting.

For more information on Kubernetes storage concepts, refer to the official Kubernetes documentation:

- [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
