# Wazuh Kubernetes for development environments

Deploy a Wazuh cluster with a basic Elastic stack on a local Kubernetes cluster.


## Local Kubernetes environment

This repo was tested on both [Minikube](https://minikube.sigs.k8s.io/) and [Kind](https://kind.sigs.k8s.io/).


## Deployment

By taking advantage of kustomizations you can deploy the whole cluster with a single command

```bash
kubectl apply -k .
```
