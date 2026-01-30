# EKS deployment

This guide provides instructions for deploying Wazuh on a Kubernetes cluster in Amazon EKS.

## Pre-requisites

- Kubernetes cluster already deployed.
  - Kubernetes can run on a wide range of Cloud providers and bare-metal environments, this documentation section focuses on [AWS](https://aws.amazon.com/). It was tested using [Amazon EKS](https://docs.aws.amazon.com/eks).
- You should be able to:
  - Create Persistent Volumes on top of AWS EBS when using a volumeClaimTemplates
  - Create a record set in AWS Route 53 from a Kubernetes LoadBalancer.
- Having at least two Kubernetes nodes in order to meet the *podAntiAffinity* policy.
- For Kubernetes version 1.23 or higher, the assignment of an IAM Role is necessary for the CSI driver to function correctly. Within the AWS documentation you can find the instructions for the assignment: <https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html>
  - The installation of the CSI driver is necessary for new and old deployments, since it is a Kubernetes feature.
- Wazuh deployment includes Network policy configurations to filter communication between pods. Verify EKS cluster configuration has Network policy configuration enabled.

## Overview

### StateFulSet and Deployments Controllers

Like a Deployment, a StatefulSet manages Pods that are based on an identical container specification, but it maintains an identity attached to each of its pods. These pods are created from the same specification, but they are not interchangeable: each one has a persistent identifier maintained across any rescheduling.

It is useful for stateful applications like databases that save the data to a persistent storage. The states of each Wazuh manager as well as Wazuh indexer are desirable to maintain, so we declare them using StatefulSet to ensure that they maintain their states in every startup.

Deployments are intended for stateless use and are quite lightweight and seem to be appropriate for Wazuh dashboard and Traefik, where it is not necessary to maintain the states.

### Pods

**Wazuh master**:

This pod contains the master node of the Wazuh cluster. The master node centralizes and coordinates worker nodes, making sure the critical and required data is consistent across all nodes.
The management is performed only in this node, so the agent registration service (authd) and the API are placed here.

Details:

- Image: Docker Hub 'wazuh/wazuh-manager'
- Controller: StatefulSet

**Wazuh worker 0 / 1**:

These pods contain a worker node of the Wazuh cluster. They will receive the agent events.

Details:

- Image: Docker Hub 'wazuh/wazuh-manager'
- Controller: StatefulSet

**Wazuh indexer**:

Wazuh indexer pod. Used to build an Wazuh indexer cluster.

Details:

- Image: wazuh/wazuh-indexer
- Controller: StatefulSet

**Wazuh dashboard**:

Wazuh dashboard pod. It lets you visualize your Wazuh indexer data, along with other features as the Wazuh app.

Details:

- image: Docker Hub 'wazuh/wazuh-dashboard'
- Controller: Deployment

### Services

**Wazuh Indexer stack**:

- wazuh-indexer:
  - Internal service for Wazuh indexer pods.
  - Exposes ports 9200 (REST API) and 9300 (cluster transport) inside the Kubernetes cluster.
- dashboard:
  - Internal service for the Wazuh dashboard on port 443.
  - Exposed externally through the Traefik ingress controller (ingressRoute-tcp-dashboard) at the configured FQDN.

**Wazuh Server stack**:

- wazuh-api:
  - Internal service for the Wazuh API on port 55000.
  - Consumed by the Wazuh dashboard and by external clients through the ingress TCP mappings.
- wazuh-events:
  - Internal service for agent event traffic on port 1514.
- wazuh-registration:
  - Internal service for agent enrollment (authd) on port 1515.
- wazuh-cluster:
  - Headless service for internal communication between Wazuh manager nodes on port 1516.

### Network policies

- allow-dns
  - Allows DNS traffic within the cluster.
- allow-ingress-to-dashboard
  - Allows incoming traffic from the ingress controller to port 443 of wazuh-dashboard.
- allow-ingress-to-manager-master
  - Allows incoming traffic from the ingress controller to port 1515 of wazuh-manager (master).
- allow-ingress-to-manager-worker
  - Allows incoming traffic from the ingress controller to port 1514 of wazuh-manager (worker).
- dashboard-egress
  - Allows outgoing traffic from wazuh-dashboard pods to port 9200 of wazuh-indexer and port 55000 of wazuh-manager (master).
- default-deny-all
  - Denies all incoming and outgoing traffic not explicitly declared in a network policy.
- indexer-egress
  - Allows outgoing traffic from wazuh-indexer pods to ports 9200 and 9300 of wazuh-indexer nodes.
- indexer-ingress
  - Allows incoming traffic from wazuh-dashboard (9200), wazuh-manager (9200), and wazuh-indexer (9300) pods to wazuh-indexer pods.
- manager-egress-external
  - Allows outgoing traffic from wazuh-manager pods to the internet (for downloading CTI and external resources).
- manager-egress
  - Allows outgoing traffic from wazuh-manager pods to wazuh-indexer on port 9200.
- wazuh-api-ingress
  - Allows incoming traffic from wazuh-dashboard (55000) and other wazuh-manager pods to port 1516 of the manager master.
- wazuh-worker-egress
  - Allows outgoing traffic from wazuh-manager worker pods to wazuh-manager ports 1516 and 55000.

Base policies (such as default-deny-all and DNS) are always applied with the Wazuh namespace. Additional ingress policies for the dashboard and managers are added by the EKS overlay to integrate with the Traefik ingress controller.

## Deploy

### Step 1: Deploy Kubernetes

Deploying the Kubernetes cluster is out of the scope of this guide.

This repository focuses on [AWS](https://aws.amazon.com/) but it should be easy to adapt it to another Cloud provider. In case you are using AWS, we recommend [EKS](https://docs.aws.amazon.com/en_us/eks/latest/userguide/getting-started.html).

### Step 2: Create domains to access the services

We recommend creating domains and certificates to access the services. Examples:

- wazuh-master.your-domain.com: Wazuh API and authd registration service.
- wazuh-manager.your-domain.com: Reporting service.
- wazuh.your-domain.com: Wazuh dashboard app.

Note: You can skip this step and the services will be accessible using the Load balancer DNS from the VPC.

### Step 3: Deployment

Clone this repository to deploy the necessary services and pods.

```bash
git clone https://github.com/wazuh/wazuh-kubernetes.git -b v5.0.0 --depth=1
cd wazuh-kubernetes
```

### Step 3.1: Setup SSL certificates

Wazuh uses certificates to establish confidentiality and encrypt communications between its central components. Follow these steps to create certificates for the Wazuh central components.

Download the `wazuh-certs-tool.sh` script. This creates the certificates that encrypt communications between the Wazuh central components.

**3.1.1 Download the Wazuh certificates tool script and config.yml file**:

```bash
cd wazuh
curl -sO https://packages.wazuh.com/5.0/wazuh-certs-tool.sh
curl -sO https://packages.wazuh.com/5.0/config.yml
```

**3.1.2 Edit the config.yml file with the configuration of the Wazuh components to be deployed**:

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

**3.1.3 Run the Wazuh certificates tool script**:

```bash
bash wazuh-certs-tool.sh -A
```

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

### Step 3.2: Apply Traefik ingress controller

To expose services outside the `EKS` cluster, we are using the Traefik ingress controller. We need to deploy the Traefik CRD first:

First, return to the root of the repository.

```bash
cd ..
```

Then, apply the Traefik CRD definitions:

```bash
kubectl apply -f traefik/crd/kubernetes-crd-definition-v1.yml
```

Expected output:

```bash
$ kubectl apply -f traefik/crd/kubernetes-crd-definition-v1.yml
customresourcedefinition.apiextensions.k8s.io/ingressroutes.traefik.io created
customresourcedefinition.apiextensions.k8s.io/ingressroutetcps.traefik.io created
customresourcedefinition.apiextensions.k8s.io/ingressrouteudps.traefik.io created
customresourcedefinition.apiextensions.k8s.io/middlewares.traefik.io created
customresourcedefinition.apiextensions.k8s.io/middlewaretcps.traefik.io created
customresourcedefinition.apiextensions.k8s.io/serverstransports.traefik.io created
customresourcedefinition.apiextensions.k8s.io/serverstransporttcps.traefik.io created
customresourcedefinition.apiextensions.k8s.io/tlsoptions.traefik.io created
customresourcedefinition.apiextensions.k8s.io/tlsstores.traefik.io created
customresourcedefinition.apiextensions.k8s.io/traefikservices.traefik.io created
```

Then, you can deploy the Traefik runtime for the ingress controller:

```bash
kubectl apply -k traefik/runtime/
```

Expected output:

```bash
$ kubectl apply -k traefik/runtime/
namespace/traefik created
serviceaccount/traefik created
clusterrole.rbac.authorization.k8s.io/traefik created
clusterrolebinding.rbac.authorization.k8s.io/traefik created
service/traefik created
deployment.apps/traefik created
```

Wait until the load balancer is created, you can check it with the following command:

```bash
kubectl -n traefik get svc
```

Expected output:

```bash
$ kubectl -n traefik get svc
NAME      TYPE           CLUSTER-IP     EXTERNAL-IP                                                              PORT(S)                                       AGE
traefik   LoadBalancer   10.100.34.51   a7ffe29bfcf38420988fd52a698be422-862207742.us-west-1.elb.amazonaws.com   443:30725/TCP,1514:32036/TCP,1515:30354/TCP   6m29s
```

### Step 3.3: Apply all manifests using kustomize

We are using the overlay feature of kustomize to create two variants: `eks` and `local-env`, in this guide we're using `eks`.

You can adjust resources for the cluster on `envs/eks/`, you can tune cpu, memory as well as storage for persistent volumes of each of the cluster objects.

Follow the steps below:

### Step 3.3.1: Update the Ingress host

For TLS Passthrough to work correctly, it is necessary to modify the ingress host `wazuh-ingress` in `wazuh/base/ingressRoute-tcp-dashboard.yaml` with the `FQDN` of the load balancer obtained in the command `kubectl -n traefik get svc`

for example:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRouteTCP
metadata:
  name: wazuh-dashboard
  namespace: wazuh
spec:
  entryPoints:
    - websecure
  routes:
  - match: HostSNI(`a7f3cfbd27cee45559254f08b24651ed-448249308.us-west-1.elb.amazonaws.com`)
    middlewares:
    - name: ip-allowlist
    services:
    - name: dashboard
      port: 443
  tls:
    passthrough: true
```

### Step 3.3.2: Deploy Wazuh cluster

By using the kustomization file on the `eks` variant we can now deploy the whole cluster with a single command:

```bash
kubectl apply -k envs/eks/
```

### Conclusion

At this point, the Wazuh stack should be deployed in your EKS cluster.

To validate the deployment and open the web UI, follow the steps in the **Accessing Wazuh dashboard** section: [verify.md](verify.md#accessing-wazuh-dashboard).
