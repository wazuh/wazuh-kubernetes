# Local deployment

This guide describes the necessary steps to deploy Wazuh on local Kubernetes environment using Minikube and Calico as the CNI.
As an important additional isolation layer, this deployment includes NetworkPolicy configurations to restrict communication between pods.

## Pre-requisites

- Kubernetes cluster running
- kubectl installed and configured to connect to the cluster

### Resource requirements

To deploy the `local-env` variant the Kubernetes cluster should have at least the following resources **available**:

- 2 CPU units
- 3 Gi of memory
- 2 Gi of storage

## Deployment

**Note**:

If you are using Minikube, make sure to start the cluster with Calico CNI:

```bash
minikube start --network-plugin=cni --cni=calico
```

You will also have to load the docker images used by Wazuh into Minikube:

```bash
docker pull wazuh/wazuh-indexer:5.0.0
docker pull wazuh/wazuh-manager:5.0.0
docker pull wazuh/wazuh-dashboard:5.0.0
minikube image load wazuh/wazuh-indexer:5.0.0
minikube image load wazuh/wazuh-manager:5.0.0
minikube image load wazuh/wazuh-dashboard:5.0.0
```

### Clone this repository

```bash
git clone https://github.com/wazuh/wazuh-kubernetes.git -b v5.0.0 --depth=1
cd wazuh-kubernetes
```

### Setup SSL certificates

Wazuh uses certificates to establish confidentiality and encrypt communications between its central components. Follow these steps to create certificates for the Wazuh central components.

Download the `wazuh-certs-tool.sh` script. This creates the certificates that encrypt communications between the Wazuh central components.

```bash
cd wazuh/
curl -sO https://packages.wazuh.com/5.0/wazuh-certs-tool.sh
curl -sO https://packages.wazuh.com/5.0/config.yml
```

Edit the `config.yml` file to set corresponding name and IP address for each Wazuh component.
For a local environment, you can use:

```yaml
nodes:
  # Wazuh indexer nodes
  indexer:
    - name: indexer
      ip: "127.0.0.1"

  # Wazuh server nodes
  server:
    - name: server
      ip: "127.0.0.1"

  # Wazuh dashboard nodes
  dashboard:
    - name: dashboard
      ip: "127.0.0.1"
```

Run `wazuh-certs-tool.sh` to create the certificates.

```bash
bash wazuh-certs-tool.sh -A
```

**Note**:

The required certificates are imported via secretGenerator on the `kustomization.yml` file:

```yaml
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
```

### Tune storage class with custom provisioner

Depending on the type of cluster you're running for local development the Storage Class may have a different provisioner.

You can check yours by running

```bash
kubectl get sc
```

You will see something like this:

```bash
$ kubectl get sc
NAME                          PROVISIONER            RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
elk-gp2                       microk8s.io/hostpath   Delete          Immediate           false                  67d
microk8s-hostpath (default)   microk8s.io/hostpath   Delete          Immediate           false                  54d

```

The provisioner column displays `microk8s.io/hostpath`, you must edit the file `envs/local-env/storage-class.yaml` and setup this provisioner.

### Change Wazuh ingress host

To deploy correctly in a local environment, it is necessary to change the parameter `<UPDATE-WITH-THE-FQDN-OF-THE-INGRESS>` to `localhost` in the file `wazuh/base/wazuh-ingress.yaml`, for example:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: wazuh-ingress
  annotations:
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
spec:
  ingressClassName: nginx
  rules:
  - host: localhost
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: dashboard
            port:
              number: 443

```

### Apply all manifests using kustomize

We are using the overlay feature of kustomize to create two variants: `eks` and `local-env`, in this guide we're using `local-env`.

It is possible to adjust resources for the cluster by editing patches on `envs/local-env/`, the number of replicas for Wazuh Indexer nodes and Wazuh Server workers are reduced on the `local-env` variant to save resources. This could be undone by removing these patches from the `kustomization.yaml` or alter the patches themselves with different values.

> **Note**: This guide was created using Minikube and Calico as the CNI.

By using the kustomization file on the `local-env` variant we can now deploy the whole cluster with a single command:

```bash
cd ..
kubectl apply -k envs/local-env/
```

#### Accessing dashboard

To access the dashboard interface you can use port-forward:

```bash
kubectl -n wazuh port-forward service/dashboard 8443:443
```

If you need to access the dashboard from another host (or register agents pointing to the Minikube host IP), you can bind the port-forward to a specific interface/IP address:

```console
kubectl -n wazuh port-forward service/dashboard 8443:443 --address 192.168.1.34 &
```

Access to Wazuh dashboard using <https://localhost:8443>

#### Exposing Wazuh server ports

```bash
kubectl -n wazuh port-forward service/wazuh-events 1514:1514
```

```bash
kubectl -n wazuh port-forward service/wazuh-registration 1515:1515
```

> **Note**: You can run the process in background adding `&` to the port-forward command, for example: kubectl -n wazuh port-forward service/wazuh-events 1514:1514 &

### Conclusion

At this point, the Wazuh stack should be deployed in your local Kubernetes cluster.

To validate the deployment and open the web UI, follow the steps in the **Accessing Wazuh dashboard** section: [verify.md](verify.md#accessing-wazuh-dashboard).
