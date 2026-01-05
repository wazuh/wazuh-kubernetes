# Introduction

[![Slack](https://img.shields.io/badge/slack-join-blue.svg)](https://wazuh.com/community/join-us-on-slack/)
[![Email](https://img.shields.io/badge/email-join-blue.svg)](https://groups.google.com/forum/#!forum/wazuh)
[![Documentation](https://img.shields.io/badge/docs-view-green.svg)](https://documentation.wazuh.com)
[![Documentation](https://img.shields.io/badge/web-view-green.svg)](https://wazuh.com)

# Wazuh Kubernetes Documentation

## Amazon EKS development

To deploy a cluster on Amazon EKS read the instructions on [Usage guide](ref/getting-started/usage/usage.md).
Note: For Kubernetes version 1.23 or higher, the assignment of an IAM Role is necessary for the CSI driver to function correctly. Within the AWS documentation you can find the instructions for the assignment: https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html
The installation of the CSI driver is mandatory for new and old deployments if you are going to use Kubernetes 1.23 for the first time or you need to upgrade the cluster.

## Local development

To deploy a cluster on your local environment (like Minikube, Kind or Microk8s) read the instructions on [local-environment.md](ref/getting-started/usage/local-environment.md).

## Diagram

![Wazuh Kubernetes Architecture](wazuh-namespace.png)

## Directory structure

├── docs
│   ├── dev
│   │   ├── run-tests.md
│   │   └── setup.md
│   ├── ref
│   │   ├── getting-started
│   │   ├── glossary.md
│   │   └── introduction.md
│   ├── README.md
│   ├── SUMMARY.md
│   ├── book.toml
│   ├── build.sh
│   ├── server.sh
│   └── wazuh-namespace.png
├── envs
│   ├── eks
│   │   ├── network-policies
│   │   ├── dashboard-resources.yaml
│   │   ├── indexer-resources.yaml
│   │   ├── kustomization.yml
│   │   ├── storage-class.yaml
│   │   ├── wazuh-master-resources.yaml
│   │   └── wazuh-worker-resources.yaml
│   └── local-env
│       ├── indexer-resources.yaml
│       ├── kustomization.yml
│       ├── storage-class.yaml
│       └── wazuh-resources.yaml
├── nginx
│   └── nginx-ingress-controller.yaml
├── tests
│   ├── conftest.py
│   └── k8s_pytest.py
├── tools
│   └── repository_bumper.sh
├── wazuh
│   ├── base
│   │   ├── Allow-DNS-np.yaml
│   │   ├── default-deny-all.yaml
│   │   ├── storage-class.yaml
│   │   ├── wazuh-ingress.yaml
│   │   └── wazuh-ns.yaml
│   ├── indexer_stack
│   │   ├── wazuh-dashboard
│   │   └── wazuh-indexer
│   ├── secrets
│   │   ├── dashboard-cred-secret.yaml
│   │   ├── indexer-cred-secret.yaml
│   │   ├── wazuh-api-cred-secret.yaml
│   │   ├── wazuh-authd-pass-secret.yaml
│   │   └── wazuh-cluster-key-secret.yaml
│   ├── wazuh_managers
│   │   ├── manager-egress-external.yaml
│   │   ├── manager-egress.yaml
│   │   ├── wazuh-api-svc.yaml
│   │   ├── wazuh-cluster-svc.yaml
│   │   ├── wazuh-events-svc.yaml
│   │   ├── wazuh-master-ingress.yaml
│   │   ├── wazuh-master-sts.yaml
│   │   ├── wazuh-registration-svc.yaml
│   │   ├── wazuh-worker-egress.yaml
│   │   └── wazuh-worker-sts.yaml
│   └── kustomization.yml
├── CHANGELOG.md
├── LICENSE
├── README.md
├── SECURITY.md
└── VERSION.json

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
