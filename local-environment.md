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

You can generate self-signed certificates for the ODFE cluster using the script at `wazuh/certs/odfe_cluster/generate_certs.sh` or provide your own.

Since Kibana has HTTPS enabled it will require its own certificates, these may be generated with: `openssl req -x509 -batch -nodes -days 365 -newkey rsa:2048 -keyout key.pem -out cert.pem`, there is an utility script at `wazuh/certs/kibana_http/generate_certs.sh` to help with this.

The required certificates are imported via secretGenerator on the `kustomization.yml` file:

    secretGenerator:
    - name: odfe-ssl-certs
        files:
        - certs/odfe_cluster/root-ca.pem
        - certs/odfe_cluster/node.pem
        - certs/odfe_cluster/node-key.pem
        - certs/odfe_cluster/kibana.pem
        - certs/odfe_cluster/kibana-key.pem
        - certs/odfe_cluster/admin.pem
        - certs/odfe_cluster/admin-key.pem
        - certs/odfe_cluster/filebeat.pem
        - certs/odfe_cluster/filebeat-key.pem
    - name: kibana-certs
        files:
        - certs/kibana_http/cert.pem
        - certs/kibana_http/key.pem

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

#### Accessing Kibana

To access the Kibana interface you can use port-forward:

```bash
$ kubectl -n wazuh port-forward service/kibana 8443:443
```

Kibana will be accesible on ``https://localhost:8443``.
