# Wazuh Kubernetes

[![Slack](https://img.shields.io/badge/slack-join-blue.svg)](https://wazuh.com/community/join-us-on-slack/)
[![Email](https://img.shields.io/badge/email-join-blue.svg)](https://groups.google.com/forum/#!forum/wazuh)
[![Documentation](https://img.shields.io/badge/docs-view-green.svg)](https://documentation.wazuh.com)
[![Documentation](https://img.shields.io/badge/web-view-green.svg)](https://wazuh.com)

Deploy a Wazuh cluster with a basic Elastic stack on Kubernetes .

## Documentation

The [instructions.md](instructions.md) file describes how to deploy Wazuh on Kubernetes.

## Directory structure

    ├── CHANGELOG.md
    ├── cleanup.md
    ├── instructions.md
    ├── LICENSE
    ├── README.md
    ├── upgrade.md
    ├── VERSION
    ├── envs
    │   ├── eks
    │   │   ├── elastic-resources.yaml
    │   │   ├── kibana-resources.yaml
    │   │   ├── kustomization.yml
    │   │   ├── storage-class.yaml
    │   │   ├── wazuh-master-resources.yaml
    │   │   └── wazuh-worker-resources.yaml
    │   └── local-env
    │       ├── elastic-resources.yaml
    │       ├── kustomization.yml
    │       ├── storage-class.yaml
    │       └── wazuh-resources.yaml
    └── wazuh
        ├── base
        │   ├── storage-class.yaml
        │   └── wazuh-ns.yaml
        ├── certs
        │   ├── kibana_http
        │   │   ├── generate_certs.sh
        │   └── odfe_cluster
        │       ├── generate_certs.sh
        ├── elastic_stack
        │   ├── elasticsearch
        │   │   ├── cluster
        │   │   │   ├── elasticsearch-api-svc.yaml
        │   │   │   └── elasticsearch-sts.yaml
        │   │   ├── elastic_conf
        │   │   │   ├── elasticsearch.yml
        │   │   │   └── internal_users.yml
        │   │   └── elasticsearch-svc.yaml
        │   └── kibana
        │       ├── kibana-deploy.yaml
        │       └── kibana-svc.yaml
        ├── kustomization.yml
        ├── secrets
        │   ├── elastic-cred-secret.yaml
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



## Branches

* `master` branch contains the latest code, be aware of possible bugs on this branch.


## Local development

To deploy a cluster on your local environment (like Minikube, Kind or Microk8s) read the instructions on [local-environment.md](local-environment.md).

## Contribute

If you want to contribute to our project please don't hesitate to send a pull request. You can also join our users [mailing list](https://groups.google.com/d/forum/wazuh) or the [Wazuh Slack community channel](https://wazuh.com/community/join-us-on-slack/) to ask questions and participate in discussions.

## Credits and Thank you

Based on the previous work from JPLachance [coveo/wazuh-kubernetes](https://github.com/coveo/wazuh-kubernetes) (2018/11/22).

## License and copyright

WAZUH
Copyright (C) 2016-2021 Wazuh Inc.  (License GPLv2)

## References

* [Wazuh website](http://wazuh.com)
