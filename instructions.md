# Usage

This guide describes the necessary steps to deploy Wazuh on Kubernetes.

## Pre-requisites

- Kubernetes cluster already deployed.
- Kubernetes can run on a wide range of Cloud providers and bare-metal environments, this repository focuses on [AWS](https://aws.amazon.com/). It was tested using [Amazon EKS](https://docs.aws.amazon.com/eks). You should be able to:
    - Create Persistent Volumes on top of AWS EBS when using a volumeClaimTemplates
    - Create a record set in AWS Route 53 from a Kubernetes LoadBalancer.
- Having at least two Kubernetes nodes in order to meet the *podAntiAffinity* policy.
- For Kubernetes version 1.23 or higher, the assignment of an IAM Role is necessary for the CSI driver to function correctly. Within the AWS documentation you can find the instructions for the assignment: https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html
- The installation of the CSI driver is necessary for new and old deployments, since it is a Kubernetes feature.


## Overview

### StateFulSet and Deployments Controllers

Like a Deployment, a StatefulSet manages Pods that are based on an identical container specification, but it maintains an identity attached to each of its pods. These pods are created from the same specification, but they are not interchangeable: each one has a persistent identifier maintained across any rescheduling.

It is useful for stateful applications like databases that save the data to a persistent storage. The states of each Wazuh manager as well as Wazuh indexer are desirable to maintain, so we declare them using StatefulSet to ensure that they maintain their states in every startup.

Deployments are intended for stateless use and are quite lightweight and seem to be appropriate for Wazuh dashboard and Nginx, where it is not necessary to maintain the states.

### Pods

#### Wazuh master

This pod contains the master node of the Wazuh cluster. The master node centralizes and coordinates worker nodes, making sure the critical and required data is consistent across all nodes.
The management is performed only in this node, so the agent registration service (authd) and the API are placed here.

Details:
- Image: Docker Hub 'wazuh/wazuh-manager'
- Controller: StatefulSet

#### Wazuh worker 0 / 1

These pods contain a worker node of the Wazuh cluster. They will receive the agent events.

Details:
- Image: Docker Hub 'wazuh/wazuh-manager'
- Controller: StatefulSet


#### Wazuh indexer

Wazuh indexer pod. Used to build an Wazuh indexer cluster.

Details:
- Image: wazuh/wazuh-indexer
- Controller: StatefulSet

#### Wazuh dashboard

Wazuh dashboard pod. It lets you visualize your Wazuh indexer data, along with other features as the Wazuh app.

Details:
- image: Docker Hub 'wazuh/wazuh-dashboard'
- Controller: Deployment

### Services

#### Indexer stack

- wazuh-indexer:
  - Communication for Wazuh indexer nodes.
- indexer:
  - Wazuh indexer API. Used by Wazuh dashboard to write/read alerts.
- dashboard:
  - Wazuh dashboard service. https://wazuh.your-domain.com:443

#### Wazuh

- wazuh:
  - Wazuh API: wazuh-master.your-domain.com:55000
  - Agent registration service (authd): wazuh-master.your-domain.com:1515
- wazuh-workers:
  - Reporting service: wazuh-manager.your-domain.com:1514
- wazuh-cluster:
  - Communication for Wazuh manager nodes.


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

```BASH
$ git clone https://github.com/wazuh/wazuh-kubernetes.git
$ cd wazuh-kubernetes
```

### Step 3.1: Setup SSL certificates

Wazuh uses certificates to establish confidentiality and encrypt communications between its central components. Follow these steps to create certificates for the Wazuh central components.

Download the `wazuh-certs-tool.sh` script. This creates the certificates that encrypt communications between the Wazuh central components.

#### 3.1.1 Download the Wazuh certificates tool script and config.yml file:
```
$ curl -sO https://packages.wazuh.com/5.0/wazuh-certs-tool.sh
$ curl -sO https://packages.wazuh.com/5.0/config.yml
```

#### 3.1.2 Edit the config.yml file with the configuration of the Wazuh components to be deployed
```
nodes:
  # Wazuh indexer nodes
  indexer:
    - name: indexer
      ip: "127.0.0.1"

  server:
    - name: server
      ip: "127.0.0.1"

  # Wazuh dashboard nodes
  dashboard:
    - name: dashboard
      ip: "127.0.0.1"
```

#### 3.1.3 Run the Wazuh certificates tool script:
```
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

### Step 3.2: Apply Nginx ingress controller

To expose services outside the `EKS` cluster, we are using the Nginx ingress controller. To deploy it, we must run the following:

```BASH
$ kubectl apply -f nginx/nginx-ingress-controler.yaml
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

```BASH
$ kubectl -n ingress-nginx get svc
NAME                                 TYPE           CLUSTER-IP      EXTERNAL-IP                                                                     PORT(S)                                                    AGE
ingress-nginx-controller             LoadBalancer   10.100.228.67   a0c363db4315d484fa38751820a9e89b-e1811181631efef0.elb.us-west-1.amazonaws.com   80:30561/TCP,443:32533/TCP,1514:31784/TCP,1515:31274/TCP   36s
ingress-nginx-controller-admission   ClusterIP      10.100.118.85   <none>                                                                          443/TCP                                                    35s
```

### Step 3.3: Apply all manifests using kustomize

We are using the overlay feature of kustomize to create two variants: `eks` and `local-env`, in this guide we're using `eks`. (For a deployment on a local environment check the guide on [local-environment.md](local-environment.md))

You can adjust resources for the cluster on `envs/eks/`, you can tune cpu, memory as well as storage for persistent volumes of each of the cluster objects.

### Step 3.3.1: Update the Ingress host

For TLS Passthrough to work correctly, it is necessary to modify the ingress host `wazuh-ingress` with the `FQDN` of the load balancer obtained in the command `kubectl -n ingress-nginx get svc`

for example:

```
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

### Step 3.3.2: Deploy Wazuh cluster

By using the kustomization file on the `eks` variant we can now deploy the whole cluster with a single command:

```BASH
$ kubectl apply -k envs/eks/
```

### Verifying the deployment

#### Namespace

```BASH
$ kubectl get namespaces | grep wazuh
wazuh         Active    12m
```

#### Services

```BASH
$ kubectl get services -n wazuh
NAME                 TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)             AGE
dashboard            ClusterIP   10.100.196.140   <none>        443/TCP             23m
wazuh-api            ClusterIP   10.100.58.98     <none>        55000/TCP           23m
wazuh-cluster        ClusterIP   None             <none>        1516/TCP            23m
wazuh-events         ClusterIP   10.100.63.117    <none>        1514/TCP            23m
wazuh-indexer        ClusterIP   None             <none>        9300/TCP,9200/TCP   23m
wazuh-registration   ClusterIP   10.100.40.83     <none>        1515/TCP            23m

```

#### Deployments

```BASH
$ kubectl get deployments -n wazuh
NAME              READY   UP-TO-DATE   AVAILABLE   AGE
wazuh-dashboard   1/1     1            1           4h16m
```

#### Statefulsets

```BASH
$ kubectl get statefulsets -n wazuh
NAME                   READY   AGE
wazuh-indexer          3/3     4h17m
wazuh-manager-master   1/1     4h17m
wazuh-manager-worker   2/2     4h17m
```

#### Pods

```BASH
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

#### Accessing Wazuh dashboard

In case you created domain names for the services, you should be able to access Wazuh dashboard using the proposed domain name: https://wazuh.your-domain.com.

Also, you can access using the External-IP (from the VPC): https://xxx-yyy-zzz.us-east-1.elb.amazonaws.com:443

```BASH
$ kubectl -n ingress-nginx get svc
NAME                                 TYPE           CLUSTER-IP      EXTERNAL-IP                                                                     PORT(S)                                                    AGE
ingress-nginx-controller             LoadBalancer   10.100.228.67   a0c363db4315d484fa38751820a9e89b-e1811181631efef0.elb.us-west-1.amazonaws.com   80:30561/TCP,443:32533/TCP,1514:31784/TCP,1515:31274/TCP   36s
ingress-nginx-controller-admission   ClusterIP      10.100.118.85   <none>                                                                          443/TCP                                                    35s
```
