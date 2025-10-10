# Wazuh Kubernetes

[![Slack](https://img.shields.io/badge/slack-join-blue.svg)](https://wazuh.com/community/join-us-on-slack/)
[![Email](https://img.shields.io/badge/email-join-blue.svg)](https://groups.google.com/forum/#!forum/wazuh)
[![Documentation](https://img.shields.io/badge/docs-view-green.svg)](https://documentation.wazuh.com)
[![Documentation](https://img.shields.io/badge/web-view-green.svg)](https://wazuh.com)

Deploy a Wazuh cluster with a basic indexer and dashboard stack on Kubernetes.

## Branches

* `main` branch contains the latest code, be aware of possible bugs on this branch.

## Documentation

## Amazon EKS development

To deploy a cluster on Amazon EKS cluster read the instructions on [eks_instructions.md](eks_instructions.md).
Note: For Kubernetes version 1.23 or higher, the assignment of an IAM Role is necessary for the CSI driver to function correctly. Within the AWS documentation you can find the instructions for the assignment: https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html
The installation of the CSI driver is mandatory for new and old deployments if you are going to use Kubernetes 1.23 for the first time or you need to upgrade the cluster.

## Google GKE development

To deploy a cluster on Google Kubernetes Engine (GKE), use the GKE-specific configuration on [gke_instructions.md](gke_instructions.md).

```bash
kubectl apply -k envs/gke/
```

The GKE environment includes:

* **GKE-optimized storage**: Uses `pd.csi.storage.gke.io` provisioner with `pd-balanced` disks and regional replication for high availability
* **LoadBalancer services**: Exposes Wazuh services via GCP Load Balancers for external access
* **Regional persistent disks**: Provides better availability and durability for your Wazuh data

Make sure your GKE cluster has the necessary permissions and that the Compute Engine Persistent Disk CSI driver is enabled (it's enabled by default in GKE clusters version 1.18.10-gke.2100 and later).

## Local development

To deploy a cluster on your local environment (like Minikube, Kind or Microk8s) read the instructions on [local-environment.md](local-environment.md).

## Directory structure

    ├── CHANGELOG.md
    ├── cleanup.md
    ├── envs
    │   ├── eks
    │   │   ├── dashboard-resources.yaml
    │   │   ├── indexer-resources.yaml
    │   │   ├── kustomization.yml
    │   │   ├── storage-class.yaml
    │   │   ├── wazuh-master-resources.yaml
    │   │   └── wazuh-worker-resources.yaml
    │   ├── gke
    │   │   ├── dashboard-resources.yaml
    │   │   ├── dashboard-svc.yaml
    │   │   ├── indexer-resources.yaml
    │   │   ├── kustomization.yml
    │   │   ├── storage-class.yaml
    │   │   ├── wazuh-master-resources.yaml
    │   │   ├── wazuh-master-svc.yaml
    │   │   ├── wazuh-worker-resources.yaml
    │   │   └── wazuh-workers-svc.yaml
    │   └── local-env
    │       ├── indexer-resources.yaml
    │       ├── kustomization.yml
    │       ├── storage-class.yaml
    │       └── wazuh-resources.yaml
    ├── eks_instructions.md
    ├── gke_instructions.md
    ├── LICENSE
    ├── local-environment.md
    ├── README.md
    ├── upgrade.md
    ├── VERSION.json
    └── wazuh
        ├── base
        │   ├── storage-class.yaml
        │   └── wazuh-ns.yaml
        ├── certs
        │   ├── dashboard_http
        │   │   └── generate_certs.sh
        │   └── indexer_cluster
        │       └── generate_certs.sh
        ├── indexer_stack
        │   ├── wazuh-dashboard
        │   │   ├── dashboard_conf
        │   │   │   └── opensearch_dashboards.yml
        │   │   ├── dashboard-deploy.yaml
        │   │   └── dashboard-svc.yaml
        │   └── wazuh-indexer
        │       ├── cluster
        │       │   ├── indexer-api-svc.yaml
        │       │   └── indexer-sts.yaml
        │       ├── indexer_conf
        │       │   ├── internal_users.yml
        │       │   └── opensearch.yml
        │       └── indexer-svc.yaml
        ├── kustomization.yml
        ├── secrets
        │   ├── dashboard-cred-secret.yaml
        │   ├── indexer-cred-secret.yaml
        │   ├── wazuh-api-cred-secret.yaml
        │   ├── wazuh-authd-pass-secret.yaml
        │   └── wazuh-cluster-key-secret.yaml
        └── wazuh_managers
            ├── wazuh-cluster-svc.yaml
            ├── wazuh_conf
            │   ├── master.conf
            │   └── worker.conf
            ├── wazuh-master-sts.yaml
            ├── wazuh-master-svc.yaml
            ├── wazuh-workers-svc.yaml
            └── wazuh-worker-sts.yaml

## Contribute

If you want to contribute to our project please don't hesitate to send a pull request. You can also join our users [mailing list](https://groups.google.com/d/forum/wazuh) or the [Wazuh Slack community channel](https://wazuh.com/community/join-us-on-slack/) to ask questions and participate in discussions.

## Credits and Thank you

Based on the previous work from JPLachance [coveo/wazuh-kubernetes](https://github.com/coveo/wazuh-kubernetes) (2018/11/22).

## License and copyright

WAZUH
Copyright (C) 2016, Wazuh Inc.  (License GPLv2)

## References

* [Wazuh website](http://wazuh.com)
