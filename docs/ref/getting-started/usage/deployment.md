# Usage

This guide describes the necessary steps to deploy Wazuh on Kubernetes either on a local environment or on AWS EKS.

## Usage: EKS deployment

### Pre-requisites

- Kubernetes cluster already deployed.
  - Kubernetes can run on a wide range of Cloud providers and bare-metal environments, this documentation section focuses on [AWS](https://aws.amazon.com/). It was tested using [Amazon EKS](https://docs.aws.amazon.com/eks).
- You should be able to:
  - Create Persistent Volumes on top of AWS EBS when using a volumeClaimTemplates
  - Create a record set in AWS Route 53 from a Kubernetes LoadBalancer.
- Having at least two Kubernetes nodes in order to meet the *podAntiAffinity* policy.
- For Kubernetes version 1.23 or higher, the assignment of an IAM Role is necessary for the CSI driver to function correctly. Within the AWS documentation you can find the instructions for the assignment: <https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html>
- The installation of the CSI driver is necessary for new and old deployments, since it is a Kubernetes feature.
- Wazuh deployment includes Network policy configurations to filter communication between pods. Verify if the EKS cluster configuration has Network policy configuration enabled.

### Overview

#### StateFulSet and Deployments Controllers

Like a Deployment, a StatefulSet manages Pods that are based on an identical container specification, but it maintains an identity attached to each of its pods. These pods are created from the same specification, but they are not interchangeable: each one has a persistent identifier maintained across any rescheduling.

It is useful for stateful applications like databases that save the data to a persistent storage. The states of each Wazuh manager as well as Wazuh indexer are desirable to maintain, so we declare them using StatefulSet to ensure that they maintain their states in every startup.

Deployments are intended for stateless use and are quite lightweight and seem to be appropriate for Wazuh dashboard and Nginx, where it is not necessary to maintain the states.

#### Pods

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

#### Services

**Wazuh Indexer stack**:

- wazuh-indexer:
  - Internal service for Wazuh indexer pods.
  - Exposes ports 9200 (REST API) and 9300 (cluster transport) inside the Kubernetes cluster.
- dashboard:
  - Internal service for the Wazuh dashboard on port 443.
  - Exposed externally through the Nginx ingress controller (wazuh-ingress) at the configured FQDN.

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

#### Network policies

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

Base policies (such as default-deny-all and DNS) are always applied with the Wazuh namespace. Additional ingress policies for the dashboard and managers are added by the EKS overlay to integrate with the Nginx ingress controller.

### Deploy

#### Step 1: Deploy Kubernetes

Deploying the Kubernetes cluster is out of the scope of this guide.

This repository focuses on [AWS](https://aws.amazon.com/) but it should be easy to adapt it to another Cloud provider. In case you are using AWS, we recommend [EKS](https://docs.aws.amazon.com/en_us/eks/latest/userguide/getting-started.html).

#### Step 2: Create domains to access the services

We recommend creating domains and certificates to access the services. Examples:

- wazuh-master.your-domain.com: Wazuh API and authd registration service.
- wazuh-manager.your-domain.com: Reporting service.
- wazuh.your-domain.com: Wazuh dashboard app.

Note: You can skip this step and the services will be accessible using the Load balancer DNS from the VPC.

#### Step 3: Deployment

Clone this repository to deploy the necessary services and pods.

```bash
git clone https://github.com/wazuh/wazuh-kubernetes.git -b v5.0.0 --depth=1
cd wazuh-kubernetes
```

#### Step 3.1: Setup SSL certificates

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

#### Step 3.2: Apply Nginx ingress controller

To expose services outside the `EKS` cluster, we are using the Nginx ingress controller. To deploy it, we must run the following:

```bash
cd ..
kubectl apply -f nginx/nginx-ingress-controller.yaml
```

Expected output:

```bash
$ kubectl apply -f nginx/nginx-ingress-controller.yaml
namespace/ingress-nginx created
serviceaccount/ingress-nginx created
serviceaccount/ingress-nginx-admission created
role.rbac.authorization.k8s.io/ingress-nginx created
role.rbac.authorization.k8s.io/ingress-nginx-admission created
clusterrole.rbac.authorization.k8s.io/ingress-nginx created
clusterrole.rbac.authorization.k8s.io/ingress-nginx-admission created
rolebinding.rbac.authorization.k8s.io/ingress-nginx created
rolebinding.rbac.authorization.k8s.io/ingress-nginx-admission created
clusterrolebinding.rbac.authorization.k8s.io/ingress-nginx created
clusterrolebinding.rbac.authorization.k8s.io/ingress-nginx-admission created
configmap/ingress-nginx-controller created
service/ingress-nginx-controller created
service/ingress-nginx-controller-admission created
configmap/wazuh-server-tcp created
deployment.apps/ingress-nginx-controller created
job.batch/ingress-nginx-admission-create created
job.batch/ingress-nginx-admission-patch created
ingressclass.networking.k8s.io/nginx created
validatingwebhookconfiguration.admissionregistration.k8s.io/ingress-nginx-admission created
```

Wait until the load balancer is created, you can check it with the following command:

```bash
kubectl -n ingress-nginx get svc
```

Expected output:

```bash
$ kubectl -n ingress-nginx get svc
NAME                                 TYPE           CLUSTER-IP      EXTERNAL-IP                                                                     PORT(S)                                                    AGE
ingress-nginx-controller             LoadBalancer   10.100.228.67   a0c363db4315d484fa38751820a9e89b-e1811181631efef0.elb.us-west-1.amazonaws.com   80:30561/TCP,443:32533/TCP,1514:31784/TCP,1515:31274/TCP   36s
ingress-nginx-controller-admission   ClusterIP      10.100.118.85   <none>                                                                          443/TCP                                                    35s
```

#### Step 3.3: Apply all manifests using kustomize

We are using the overlay feature of kustomize to create two variants: `eks` and `local-env`, in this guide we're using `eks`.

You can adjust resources for the cluster on `envs/eks/`, you can tune cpu, memory as well as storage for persistent volumes of each of the cluster objects.

Follow the steps below:

#### Step 3.3.1: Update the Ingress host

For TLS Passthrough to work correctly, it is necessary to modify the ingress host `wazuh-ingress` in `wazuh/base/wazuh-ingress.yaml` with the `FQDN` of the load balancer obtained in the command `kubectl -n ingress-nginx get svc`

for example:

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
  - host: a0c363db4315d484fa38751820a9e89b-e1811181631efef0.elb.us-west-1.amazonaws.com
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

#### Step 3.3.2: Deploy Wazuh cluster

By using the kustomization file on the `eks` variant we can now deploy the whole cluster with a single command:

```bash
kubectl apply -k envs/eks/
```

## Usage: Local deployment

Here it is described the necessary steps to deploy Wazuh on a local Kubernetes environment.

Wazuh deployment includes Network policy configurations to restrict communication between pods. This guide was created using Minikube and Calico as the CNI.

### Pre-requisites

- Kubernetes cluster running
- kubectl installed and configured to connect to the cluster

#### Resource requirements

To deploy the `local-env` variant the Kubernetes cluster should have at least the following resources **available**:

- 2 CPU units
- 3 Gi of memory
- 2 Gi of storage

### Deployment

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

#### Clone this repository

```bash
git clone https://github.com/wazuh/wazuh-kubernetes.git -b v5.0.0 --depth=1
cd wazuh-kubernetes
```

#### Setup SSL certificates

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

#### Tune storage class with custom provisioner

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

#### Change Wazuh ingress host

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

#### Apply all manifests using kustomize

We are using the overlay feature of kustomize to create two variants: `eks` and `local-env`, in this guide we're using `local-env`.

It is possible to adjust resources for the cluster by editing patches on `envs/local-env/`, the number of replicas for Wazuh Indexer nodes and Wazuh Server workers are reduced on the `local-env` variant to save resources. This could be undone by removing these patches from the `kustomization.yaml` or alter the patches themselves with different values.

> **Note**: This guide was created using Minikube and Calico as the CNI.

By using the kustomization file on the `local-env` variant we can now deploy the whole cluster with a single command:

```bash
kubectl apply -k envs/local-env/
```

If you are using Minikube, you will also need to start the Minikube tunnel to expose LoadBalancer services:

```bash
minikube tunnel
```

##### Accessing Dashboard

To access the Dashboard interface you can use port-forward:

```bash
kubectl -n wazuh port-forward service/dashboard 8443:443
```

Dashboard will be accessible on ``https://localhost:8443``.

##### Exposing Wazuh server ports

```bash
kubectl -n wazuh port-forward service/wazuh-events 1514:1514
```

```bash
kubectl -n wazuh port-forward service/wazuh-registration 1515:1515
```

> **Note**: You can run the process in background adding `&` to the port-forward command, for example: kubectl -n wazuh port-forward service/wazuh-events 1514:1514 &

## Verifying the deployment

### Namespace

```bash
kubectl get namespaces | grep wazuh
```

Expected output:

```bash
$ kubectl get namespaces | grep wazuh
wazuh         Active    12m
```

### Services

```bash
kubectl get services -n wazuh
```

Expected output:

```bash
$ kubectl get services -n wazuh
NAME                 TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)             AGE
dashboard            ClusterIP   10.100.196.140   <none>        443/TCP             23m
wazuh-api            ClusterIP   10.100.58.98     <none>        55000/TCP           23m
wazuh-cluster        ClusterIP   None             <none>        1516/TCP            23m
wazuh-events         ClusterIP   10.100.63.117    <none>        1514/TCP            23m
wazuh-indexer        ClusterIP   None             <none>        9300/TCP,9200/TCP   23m
wazuh-registration   ClusterIP   10.100.40.83     <none>        1515/TCP            23m

```

### Deployments

```bash
kubectl get deployments -n wazuh
```

Expected output:

```bash
$ kubectl get deployments -n wazuh
NAME              READY   UP-TO-DATE   AVAILABLE   AGE
wazuh-dashboard   1/1     1            1           4h16m
```

### Statefulsets

```bash
kubectl get statefulsets -n wazuh
```

Expected output:

```bash
$ kubectl get statefulsets -n wazuh
NAME                   READY   AGE
wazuh-indexer          3/3     4h17m
wazuh-manager-master   1/1     4h17m
wazuh-manager-worker   2/2     4h17m
```

### Pods

```bash
kubectl get pods -n wazuh
```

Expected output:

```bash
$ kubectl get pods -n wazuh
NAME                               READY   STATUS    RESTARTS   AGE
wazuh-dashboard-57d455f894-ffwsk   1/1     Running   0          4h17m
wazuh-indexer-0                    1/1     Running   0          4h17m
wazuh-indexer-1                    1/1     Running   0          4h17m
wazuh-indexer-2                    1/1     Running   0          4h17m
wazuh-manager-master-0             1/1     Running   0          4h17m
wazuh-manager-worker-0             1/1     Running   0          4h17m
wazuh-manager-worker-1             1/1     Running   0          4h17m
```

### Network Policies

```bash
kubectl -n wazuh get networkpolicy
```

Expected output:

```bash
$ kubectl -n wazuh get networkpolicy
NAME                              POD-SELECTOR                         AGE
allow-dns                         <none>                               51s
allow-ingress-to-dashboard        app=wazuh-dashboard                  50s
allow-ingress-to-manager-master   app=wazuh-manager,node-type=master   49s
allow-ingress-to-manager-worker   app=wazuh-manager,node-type=worker   48s
dashboard-egress                  app=wazuh-dashboard                  47s
default-deny-all                  <none>                               46s
indexer-egress                    app=wazuh-indexer                    45s
indexer-ingress                   app=wazuh-indexer                    44s
manager-egress                    app=wazuh-manager,node-type=master   43s
manager-egress-external           app=wazuh-manager                    42s
wazuh-api-ingress                 app=wazuh-manager,node-type=master   42s
wazuh-worker-egress               app=wazuh-manager,node-type=worker   41s
```

### Accessing Wazuh dashboard

In case you created domain names for the services, you should be able to access Wazuh dashboard using the proposed domain name: <https://wazuh.your-domain.com>.

Also, you can access using the External-IP (from the VPC): <https://xxx-yyy-zzz.us-east-1.elb.amazonaws.com:443>

```bash
kubectl -n ingress-nginx get svc
```

Expected output:

```bash
$ kubectl -n ingress-nginx get svc
NAME                                 TYPE           CLUSTER-IP      EXTERNAL-IP                                                                     PORT(S)                                                    AGE
ingress-nginx-controller             LoadBalancer   10.100.228.67   a0c363db4315d484fa38751820a9e89b-e1811181631efef0.elb.us-west-1.amazonaws.com   80:30561/TCP,443:32533/TCP,1514:31784/TCP,1515:31274/TCP   36s
ingress-nginx-controller-admission   ClusterIP      10.100.118.85   <none>                                                                          443/TCP                                                    35s
```
