# Introduction

[![Slack](https://img.shields.io/badge/slack-join-blue.svg)](https://wazuh.com/community/join-us-on-slack/)
[![Email](https://img.shields.io/badge/email-join-blue.svg)](https://groups.google.com/forum/#!forum/wazuh)
[![Documentation](https://img.shields.io/badge/docs-view-green.svg)](https://documentation.wazuh.com)
[![Documentation](https://img.shields.io/badge/web-view-green.svg)](https://wazuh.com)

# Wazuh Kubernetes Documentation

## Amazon EKS development

To deploy a cluster on Amazon EKS cluster read the instructions on [usage.md](ref/getting-started/usage/usage.md).
Note: For Kubernetes version 1.23 or higher, the assignment of an IAM Role is necessary for the CSI driver to function correctly. Within the AWS documentation you can find the instructions for the assignment: https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html
The installation of the CSI driver is mandatory for new and old deployments if you are going to use Kubernetes 1.23 for the first time or you need to upgrade the cluster.

## Local development

To deploy a cluster on your local environment (like Minikube, Kind or Microk8s) read the instructions on [local-environment.md](ref/getting-started/usage/local-environment.md).

## Diagram

![Wazuh Kubernetes Architecture](wazuh-namespace.png)

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
    │   └── local-env
    │       ├── indexer-resources.yaml
    │       ├── kustomization.yml
    │       ├── storage-class.yaml
    │       └── wazuh-resources.yaml
    ├── instructions.md
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

## Docs requirements

To work with this documentation, you need **mdBook** installed. For installation instructions, refer to the [mdBook documentation](https://rust-lang.github.io/mdBook/).

## Usage

- To build the documentation, run:

  ```bash
  ./build.sh
  ```

  The output will be generated in the `book` directory.

- To serve the documentation locally for preview, run:

  ```bash
  ./server.sh
  ```

  The documentation will be available at [http://127.0.0.1:3000](http://127.0.0.1:3000).
