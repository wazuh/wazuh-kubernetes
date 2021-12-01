# Usage

This guide describes the necessary steps to deploy Wazuh on Kubernetes.

## Pre-requisites

- Kubernetes cluster already deployed.
- Kubernetes can run on a wide range of Cloud providers and bare-metal environments, this repository focuses on [AWS](https://aws.amazon.com/). It was tested using [Amazon EKS](https://docs.aws.amazon.com/eks). You should be able to:
    - Create Persistent Volumes on top of AWS EBS when using a volumeClaimTemplates
    - Create a record set in AWS Route 53 from a Kubernetes LoadBalancer.
- Having at least two Kubernetes nodes in order to meet the *podAntiAffinity* policy.
- EFS CSI Driver installed and EFS Filesystem created according to official documentation https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html


## Overview

### StateFulSet and Deployments Controllers

Like a Deployment, a StatefulSet manages Pods that are based on an identical container specification, but it maintains an identity attached to each of its pods. These pods are created from the same specification, but they are not interchangeable: each one has a persistent identifier maintained across any rescheduling.

It is useful for stateful applications like databases that save the data to a persistent storage. The states of each Wazuh manager as well as Elasticsearch are desirable to maintain, so we declare them using StatefulSet to ensure that they maintain their states in every startup.

Deployments are intended for stateless use and are quite lightweight and seem to be appropriate for Kibana and Nginx, where it is not necessary to maintain the states.

### Pods

#### Wazuh master

This pod contains 2 containers: the master node of the Wazuh cluster and filebeat container. The master node centralizes and coordinates worker nodes, making sure the critical and required data is consistent across all nodes and filebeat container send alerts from master node to elasticsearch cluster.
The management is performed only in this node, so the agent registration service (authd) and the API are placed here.

Details:
- Images: Docker Hub 'wazuh/wazuh-manager'
          Docker Hub 'wazuh/wazuh-filebeat'
- Controller: StatefulSet

#### Wazuh worker 0 / 1

These pods contain a worker node of the Wazuh cluster. They will receive the agent events.

Details:
- Images: Docker Hub 'wazuh/wazuh-manager'
          Docker Hub 'wazuh/wazuh-filebeat'
- Controller: StatefulSet


#### Elasticsearch

Elasticsearch pod. Used to build an Elasticsearch cluster.

Details:
- Image: amazon/opendistro-for-elasticsearch
- Controller: StatefulSet

#### Kibana

Kibana pod. It lets you visualize your Elasticsearch data, along with other features as the Wazuh app.

Details:
- image: Docker Hub 'wazuh/wazuh-kibana-odfe'
- Controller: Deployment

### Services

#### Elastic stack

- wazuh-elasticsearch:
  - Communication for Elasticsearch nodes.
- elasticsearch:
  - Elasticsearch API. Used by Kibana to write/read alerts.
- kibana:
  - Kibana service. https://wazuh.your-domain.com:443

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
- wazuh.your-domain.com: Kibana and Wazuh app.

Note: You can skip this step and the services will be accessible using the Load balancer DNS from the VPC.

### Step 3: Deployment

Clone this repository to deploy the necessary services and pods.

```BASH
$ git clone https://github.com/wazuh/wazuh-kubernetes.git
$ cd wazuh-kubernetes
```

### Step 3.1: Setup SSL certificates

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

### Step 3.2: Change EFS filesystem information

You need to take the name of the filesystem in the AWS console (example: fs-035361f0eab2bcccf) and modify the Storageclass and Persistantolume build files. The files are as follows:
- envs/eks/storage-class-nfs.yaml: you need to modify the fileSystemId parameter.
- wazuh/wazuh-managers/wazuh-master-pv.yaml: you need to modify the volumeHandle parameter in the declaration of both PVs.

### Step 3.3: Apply all manifests using kustomize

We are using the overlay feature of kustomize to create two variants: `eks` and `local-env`, in this guide we're using `eks`. (For a deployment on a local environment check the guide on [local-environment.md](local-environment.md))

You can adjust resources for the cluster on `envs/eks/`, you can tune cpu, memory as well as storage for persistent volumes of each of the cluster objects.


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
NAME                  TYPE           CLUSTER-IP       EXTERNAL-IP        PORT(S)                          AGE
elasticsearch         ClusterIP      xxx.yy.zzz.24    <none>             9200/TCP                         12m
kibana                ClusterIP      xxx.yy.zzz.76    <none>             5601/TCP                         11m
wazuh                 LoadBalancer   xxx.yy.zzz.209   internal-a7a8...   1515:32623/TCP,55000:30283/TCP   9m
wazuh-cluster         ClusterIP      None             <none>             1516/TCP                         9m
wazuh-elasticsearch   ClusterIP      None             <none>             9300/TCP                         12m
wazuh-workers         LoadBalancer   xxx.yy.zzz.26    internal-a7f9...   1514:31593/TCP                   9m
```

#### Deployments

```BASH
$ kubectl get deployments -n wazuh
NAME             DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
wazuh-kibana     1         1         1            1           11m
```

#### Statefulsets

```BASH
$ kubectl get statefulsets -n wazuh
NAME                   READY   AGE
wazuh-elasticsearch    3/3     15m
wazuh-manager-master   1/1     15m
wazuh-manager-worker   2/2     15m
```

#### Pods

```BASH
$ kubectl get pods -n wazuh
NAME                            READY   STATUS    RESTARTS   AGE
wazuh-elasticsearch-0           1/1     Running   0          15m
wazuh-elasticsearch-1           1/1     Running   0          15m
wazuh-elasticsearch-2           1/1     Running   0          14m
wazuh-kibana-7c9657f5c5-z95pt   1/1     Running   0          6m18s
wazuh-manager-master-0          1/1     Running   0          6m10s
wazuh-manager-worker-0          1/1     Running   0          8m18s
wazuh-manager-worker-1          1/1     Running   0          8m38s
```

#### Accessing Kibana

In case you created domain names for the services, you should be able to access Kibana using the proposed domain name: https://wazuh.your-domain.com.

Also, you can access using the External-IP (from the VPC): https://internal-xxx-yyy.us-east-1.elb.amazonaws.com:443

```BASH
$ kubectl get services -o wide -n wazuh
NAME                  TYPE           CLUSTER-IP       EXTERNAL-IP                                                                       PORT(S)                          AGE       SELECTOR
kibana                LoadBalancer   xxx.xx.xxx.xxx   internal-xxx-yyy.us-east-1.elb.amazonaws.com                                      80:31831/TCP,443:30974/TCP       15m       app=wazuh-kibana
```
