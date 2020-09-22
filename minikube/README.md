# Wazuh Kubernetes for development environments

Deploy a Wazuh cluster with a basic Elastic stack on a local Kubernetes cluster.


## Local Kubernetes environment

This repo was tested on both [Minikube](https://minikube.sigs.k8s.io/) and [Kind](https://kind.sigs.k8s.io/).


## Deployment

By taking advantage of kustomizations you can deploy the whole cluster with a single command

```bash
kubectl apply -k .
```

## Expose Kind hostPorts

To expose internal nodePorts on a Kind setup you can use a custom configuration when launching your cluster.

### kind-config.yaml

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30443
    hostPort: 443
    listenAddress: "0.0.0.0"
    protocol: tcp
  - containerPort: 31515
    hostPort: 1515
    listenAddress: "0.0.0.0"
    protocol: tcp
  - containerPort: 31514
    hostPort: 1514
    listenAddress: "0.0.0.0"
    protocol: udp
```

Launch a new cluster with: `kind create cluster --config kind-config.yaml`
