# Usage

This guide describes the necessary steps to deploy Wazuh on a local Kubernetes environment (Microk8s, Minikube, Kind).

Here we will describe the steps unique for a deployment on a local development scenario. For general knowledge read [instructions.md](instructions.md) as well which describes a deployment in more detail using an EKS cluster.

## Pre-requisites

- Kubernetes cluster already deployed.

### Resource requirements

To deploy the `local-env` variant the Kubernetes cluster should have at least the following resources **available**:

- 2 CPU units
- 3 Gi of memory
- 2 Gi of storage

## Deployment

### Clone this repository.

```BASH
$ git clone https://github.com/wazuh/wazuh-kubernetes.git
$ cd wazuh-kubernetes
```

### Setup SSL certificates

Wazuh uses certificates to establish confidentiality and encrypt communications between its central components. Follow these steps to create certificates for the Wazuh central components.

Download the `wazuh-certs-tool.sh` script. This creates the certificates that encrypt communications between the Wazuh central components.

```BASH
cd wazuh/
curl -sO https://packages.wazuh.com/5.0/wazuh-certs-tool.sh
```

Run `wazuh-certs-tool.sh` to create the certificates.

```BASH
bash wazuh-certs-tool.sh -A
```

The required certificates are imported via secretGenerator on the `kustomization.yml` file:

    secretGenerator:
    - name: indexer-certs
        files:
        - wazuh-certificates/root-ca.pem
        - wazuh-certificates/indexer.pem
        - wazuh-certificates/indexer-key.pem
        - wazuh-certificates/dashboard.pem
        - wazuh-certificates/dashboard-key.pem
        - wazuh-certificates/admin.pem
        - wazuh-certificates/admin-key.pem
        - wazuh-certificates/server.pem
        - wazuh-certificates/server-key.pem
    - name: dashboard-certs
        files:
        - wazuh-certificates/dashboard.pem
        - wazuh-certificates/dashboard-key.pem
        - wazuh-certificates/root-ca.pem

### Tune storage class with custom provisioner

Depending on the type of cluster you're running for local development the Storage Class may have a different provisioner.

You can check yours by running `kubectl get sc`. You will see something like this:


```BASH
~> kubectl get sc
NAME                          PROVISIONER            RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
elk-gp2                       microk8s.io/hostpath   Delete          Immediate           false                  67d
microk8s-hostpath (default)   microk8s.io/hostpath   Delete          Immediate           false                  54d

```

The provisioner column displays `microk8s.io/hostpath`, you must edit the file `envs/local-env/storage-class.yaml` and setup this provisioner.

### Apply all manifests using kustomize

We are using the overlay feature of kustomize two create two variants: `eks` and `local-env`, in this guide we're using `local-env`. (For a production deployment on EKS check the guide on [instructions.md](instructions.md))

It is possible to adjust resources for the cluster by editing patches on `envs/local-env/`, the number of replicas for Elasticsearch nodes and Wazuh workers are reduced on the `local-env` variant to save resources. This could be undone by removing these patches from the `kustomization.yaml` or alter the patches themselves with different values.

By using the kustomization file on the `local-env` variant we can now deploy the whole cluster with a single command:

```BASH
$ kubectl apply -k envs/local-env/
```

#### Accessing Dashboard

To access the Dashboard interface you can use port-forward:

```bash
$ kubectl -n wazuh port-forward service/dashboard 8443:443
```

Dashboard will be accesible on ``https://localhost:8443``.
