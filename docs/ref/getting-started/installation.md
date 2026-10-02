# Installation

This section describes the procedures to deploy the Wazuh stack using a Kubernetes cluster, trhough the manifests and Kustomize overlays provided in this repository.

## EKS deployment

This guide provides instructions for deploying Wazuh on a Kubernetes cluster in Amazon EKS.

### Pre-requisites

- Kubernetes cluster already deployed.
  - Kubernetes can run on a wide range of Cloud providers and bare-metal environments, this documentation section focuses on [AWS](https://aws.amazon.com/). It was tested using [Amazon EKS](https://docs.aws.amazon.com/eks).
- You should be able to:
  - Create Persistent Volumes on top of AWS EBS when using a volumeClaimTemplates
  - Create a record set in AWS Route 53 from a Kubernetes LoadBalancer.
- Having at least two Kubernetes nodes in order to meet the *podAntiAffinity* policy.
- For Kubernetes version 1.23 or higher, the assignment of an IAM Role is necessary for the CSI driver to function correctly. Within the AWS documentation you can find the instructions for the assignment: <https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html>
  - The installation of the CSI driver is necessary for new and old deployments, since it is a Kubernetes feature.
- Wazuh deployment includes Network policy configurations to filter communication between pods. Verify EKS cluster configuration has Network policy configuration enabled.

### Overview

#### StateFulSet and Deployments Controllers

Like a Deployment, a StatefulSet manages Pods that are based on an identical container specification, but it maintains an identity attached to each of its pods. These pods are created from the same specification, but they are not interchangeable: each one has a persistent identifier maintained across any rescheduling.

It is useful for stateful applications like databases that save the data to a persistent storage. The states of each Wazuh manager as well as Wazuh indexer are desirable to maintain, so we declare them using StatefulSet to ensure that they maintain their states in every startup.

Deployments are intended for stateless use and are quite lightweight and seem to be appropriate for Wazuh dashboard and Traefik, where it is not necessary to maintain the states.

All three StatefulSets set `podManagementPolicy: Parallel`. The Wazuh indexer needs it: its nodes form a quorum, and under the default `OrderedReady` a restart that took the whole StatefulSet down — a node group replacement, for instance — leaves `wazuh-indexer-0` unable to elect a cluster manager on its own, while the controller waits for it to become ready before creating the peers that would give it one. The field is immutable, so changing it on a running deployment means `kubectl delete statefulset wazuh-indexer --cascade=orphan` followed by an apply, which keeps the pods and the claims.

#### Pods

**Wazuh master**:

This pod contains the master node of the Wazuh cluster. The master node centralizes and coordinates worker nodes, making sure the critical and required data is consistent across all nodes.
The management is performed only in this node, so the API is placed here, together with the legacy agent registration service (`authd`) used by Wazuh 4.x agents. Wazuh 5.x agents enroll through `remoted`, which runs on every node, so their enrollment is not confined to the master.

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
  - Exposed externally through the Traefik ingress controller (ingressRoute-tcp-dashboard) at the configured FQDN.

**Wazuh Server stack**:

- wazuh-api:
  - Internal service for the Wazuh API on port 55000.
  - Consumed by the Wazuh dashboard. It is not published through Traefik: reach it with `kubectl -n wazuh exec` into `wazuh-manager-master-0`, or with `kubectl port-forward`.
- wazuh-agents:
  - Internal service for Wazuh 5.x agent traffic and enrollment on port 1517.
  - Selects every manager pod, master included, since `remoted` serves this HTTPS channel on all nodes.
- wazuh-events:
  - Internal service for Wazuh 4.x agent event traffic on port 1514 (legacy `remoted`).
- wazuh-registration:
  - Internal service for Wazuh 4.x agent enrollment (`authd`) on port 1515.
- wazuh-cluster:
  - Headless service for internal communication between Wazuh manager nodes on port 1516.

#### Network policies

- allow-dns
  - Allows DNS traffic within the cluster.
- allow-ingress-to-dashboard
  - Allows incoming traffic from the ingress controller to port 443 of wazuh-dashboard.
- allow-ingress-to-manager-master
  - Allows incoming traffic from the ingress controller to ports 1517 and 1515 of wazuh-manager (master).
- allow-ingress-to-manager-worker
  - Allows incoming traffic from the ingress controller to ports 1517 and 1514 of wazuh-manager (worker).
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

### Deploy

#### Step 1: Deploy Kubernetes

Deploying the Kubernetes cluster is out of the scope of this guide.

This repository focuses on [AWS](https://aws.amazon.com/) but it should be easy to adapt it to another Cloud provider. In case you are using AWS, we recommend [EKS](https://docs.aws.amazon.com/en_us/eks/latest/userguide/getting-started.html).

#### Step 2: Create domains to access the services

We recommend creating domains and certificates to access the services. Examples:

- wazuh-master.your-domain.com: Wazuh API and legacy authd registration service.
- wazuh-manager.your-domain.com: Reporting service.
- wazuh.your-domain.com: Wazuh dashboard app.

Note: You can skip this step and the services will be accessible using the Load balancer DNS from the VPC.

#### Step 3: Deployment

Clone this repository to deploy the necessary services and pods.

```bash
git clone https://github.com/wazuh/wazuh-kubernetes.git -b v5.0.0 --depth=1
cd wazuh-kubernetes
```

#### Step 3.1: Apply Traefik ingress controller

To expose services outside the `EKS` cluster, we are using the Traefik ingress controller. It goes first because the certificates of the next step have to carry the FQDN of the load balancer it creates.

From the root of the repository, apply the Traefik CRD definitions:

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
traefik   LoadBalancer   10.100.34.51   a7ffe29bfcf38420988fd52a698be422-862207742.us-west-1.elb.amazonaws.com   443:30725/TCP,1517:31485/TCP,1514:32036/TCP,1515:30354/TCP   6m29s
```

Keep that `EXTERNAL-IP` value: it is the FQDN agents dial, and the next step puts it in the agent listener certificate.

#### Step 3.2: Setup SSL certificates

Wazuh uses certificates to establish confidentiality and encrypt communications between its central components. Follow these steps to create certificates for the Wazuh central components.

Download the `wazuh-certs-tool.sh` script. This creates the certificates that encrypt communications between the Wazuh central components.

**3.2.1 Download the Wazuh certificates tool script, the credentials library and the config.yml file**:

```bash
cd wazuh
curl -so wazuh-certs-tool.sh https://packages.wazuh.com/5.0/wazuh-certs-tool-5.0.0-1.sh
curl -so wazuh-credentials.sh https://raw.githubusercontent.com/wazuh/wazuh-installation-assistant/5.0.0/credentials_lib/wazuh-credentials.sh
curl -so config.yml https://packages.wazuh.com/5.0/config-5.0.0-1.yml
```

`wazuh-credentials.sh` is the library `credentials-conf.sh` generates and validates the passwords
with (step 3.2.4). Use the same version as the images.

**3.2.2 Edit the config.yml file with the configuration of the Wazuh components to be deployed**:

```yaml
nodes:
  # Wazuh indexer nodes
  indexer:
    - name: indexer
      dns:
        - "wazuh-indexer"
        - "wazuh-indexer.wazuh.svc.cluster.local"
        - "wazuh-indexer-0.wazuh-indexer"
        - "wazuh-indexer-1.wazuh-indexer"
        - "wazuh-indexer-2.wazuh-indexer"
        - "wazuh-indexer-0.wazuh-indexer.wazuh.svc.cluster.local"
        - "wazuh-indexer-1.wazuh-indexer.wazuh.svc.cluster.local"
        - "wazuh-indexer-2.wazuh-indexer.wazuh.svc.cluster.local"

  # Wazuh server nodes
  manager:
    - name: manager
      dns:
        - "wazuh-api"
        - "wazuh-api.wazuh.svc.cluster.local"
        - "wazuh-agents"
        - "wazuh-agents.wazuh.svc.cluster.local"

  # Wazuh dashboard nodes
  dashboard:
    - name: dashboard
      dns:
        - "dashboard"
        - "dashboard.wazuh.svc.cluster.local"
        - "a7ffe29bfcf38420988fd52a698be422-862207742.us-west-1.elb.amazonaws.com"   # load balancer FQDN from step 3.1
```

> **Note**: The Wazuh indexer nodes verify each other's certificate on the transport port against
> the name each one publishes, `wazuh-indexer-<n>.wazuh-indexer.<namespace>.svc.cluster.local`, set
> by `network.publish_host` in `indexer-sts.yaml`. The `dns` list therefore needs one pair of
> entries per indexer replica, or the nodes cannot form a cluster. Adjust it if you change the
> replica count of the overlay.

> **Note**: Traefik passes the dashboard TLS connection through untouched, so the browser checks `dashboard.pem` itself. Its SAN has to carry every name the dashboard is opened with: the load balancer FQDN from step 3.1, and any domain of your own from step 2. A name that is not in the `dashboard` list fails verification with `no alternative certificate subject name matches target host name`.

> **Note**: The `manager` entry also produces the agent listener certificate (`manager-remoted.pem` and `manager-remoted-key.pem`), which `remoted` serves on port `1517`. Its SAN has to cover every name an agent dials: the `wazuh-agents` Service inside the cluster, which the `dns` list above provides, and the FQDN of the load balancer from step 3.1 for agents enrolling from outside, which `--agent-san` adds in the command below. Agents that verify the manager certificate fail to connect to a name the certificate does not carry.

**3.2.3 Run the Wazuh certificates tool script**:

Pass the load balancer FQDN from step 3.1 with `--agent-san`. It goes only into the agent listener certificate, leaving `manager.pem`, `indexer.pem` and `dashboard.pem` untouched. Repeat the flag for every extra address, such as a CNAME of your own that agents will use:

```bash
sudo bash ../tools/utils/deployment/certificates-conf.sh --cert --copy --priv \
  --agent-san a7ffe29bfcf38420988fd52a698be422-862207742.us-west-1.elb.amazonaws.com
```

Drop `--agent-san` if no agent enrolls from outside the cluster. The certificates are issued once here; there is nothing to re-run later.

> **Note**: `sudo` is required because the certificates tool refuses to run as anything else, and
> `--priv` is what makes the result usable afterwards: it hands the files to the user running the
> command. The certificates enter the cluster through the `secretGenerator` of
> `wazuh/kustomization.yml`, which reads them as whoever runs `kubectl apply -k`, so a private key
> left owned by `root` — they are created with mode `0600` — fails the next step with
> `permission denied`. Their ownership on this machine never reaches the cluster: the pods get the
> file modes from the Secret and, for the manager, from its init container.

The required certificates are imported via secretGenerator on the `kustomization.yml` file:

```yaml
secretGenerator:
  - name: indexer-certs
    files:
      - config/indexer/certs/admin-key.pem
      - config/indexer/certs/admin.pem
      - config/indexer/certs/indexer-key.pem
      - config/indexer/certs/indexer.pem
      - config/root-ca/certs/root-ca.pem
  - name: dashboard-certs
    files:
      - config/dashboard/certs/dashboard-key.pem
      - config/dashboard/certs/dashboard.pem
      - config/root-ca/certs/root-ca.pem
  - name: manager-certs
    files:
      - config/manager/certs/manager-key.pem
      - config/manager/certs/manager.pem
      - config/manager/certs/manager-remoted-key.pem
      - config/manager/certs/manager-remoted.pem
      - config/root-ca/certs/root-ca.pem
```

**3.2.4 Run the credentials generator**:

Every Wazuh component now generates or validates its own credentials at install time and refuses to
start without them. Generate the five passwords before the first `kubectl apply -k`, the same way as
the certificates above. The script sources `wazuh-credentials.sh`, downloaded in step 3.2.1
(`WAZUH_CREDENTIALS_LIB` overrides the path):

```bash
sudo bash ../tools/utils/deployment/credentials-conf.sh
```

It writes `config/credentials/{indexer,manager,dashboard}.env`, which `wazuh/kustomization.yml`'s
`secretGenerator` turns into Secrets the pods read. **It never overwrites an existing file**: once a
deployment has started, the passwords it was given are the ones that count. `--force` replaces them,
and is only for a deployment that has never been started.

Keep these files for the whole life of the deployment and back them up with the certificates: every
`kubectl apply -k` and `kubectl delete -k` reads them, and the indexer takes its passwords from its
Secret again every time one of its pods is recreated.

Return to the root of the repository for the steps that follow:

```bash
cd ..
```

#### Step 3.3: Apply all manifests using kustomize

We are using the overlay feature of kustomize to create two variants: `eks` and `local-env`, in this guide we're using `eks`.

You can adjust resources for the cluster on `envs/eks/`, you can tune cpu, memory as well as storage for persistent volumes of each of the cluster objects.

Follow the steps below:

#### Step 3.3.1: Update the Ingress host

For TLS Passthrough to work correctly, it is necessary to replace the placeholder `<UPDATE-WITH-THE-FQDN-OF-THE-INGRESS>` in `HostSNI(...)` of `wazuh/base/ingressRoute-tcp-dashboard.yaml` with the `FQDN` of the load balancer obtained in the command `kubectl -n traefik get svc`

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

#### Step 3.3.2: Set the cluster key and the agent enrollment password

Two of the Secrets under `wazuh/secrets/` hold shared keys rather than account passwords. Neither ships with a usable value: the cluster key is a placeholder, and the enrollment password is the string `password`.

| Secret | Key | Default value | What it protects |
| --- | --- | --- | --- |
| `wazuh-cluster-key` | `key` | `REPLACETHISCLUSTERKEYBEFOREDEPLO` (placeholder, not a key) | Membership of the Wazuh manager cluster, on port `1516` |
| `wazuh-authd-pass` | `authd.pass` | `password` | Agent enrollment: the channel `remoted` serves on port `1517`, and the legacy `authd` port `1515` |

**Change both here, before the first `kubectl apply -k`.** Unlike the Wazuh indexer and Wazuh API accounts created in step 3.2.4, these are not accounts inside an image, so `password-tool.sh` does not cover them: the managers read them from the Secrets on every container start. Setting them now costs nothing, while changing the cluster key on a running deployment stops the workers from syncing until every manager pod has restarted on the new key.

Generate the two values. The cluster key has to be **exactly 32 alphanumeric characters** (`^[a-zA-Z0-9]{32}$`); `openssl rand -hex 16` produces exactly that. A key of any other length, or one carrying `-`, `_` or any other punctuation, makes every manager refuse to start with `(1244): Invalid configuration at '/cluster/key': does not satisfy 'pattern'`:

```bash
openssl rand -hex 16   # cluster key, 32 hexadecimal characters
openssl rand -hex 24   # enrollment password
```

Encode each one, without a trailing newline:

```bash
echo -n '8f3c1d0b7a5e49628c1f0a3d5b7e9c21' | base64
```

Then write them into the two manifests, keeping the key names as they are:

```yaml
# wazuh/secrets/wazuh-cluster-key-secret.yaml
data:
  key: OGYzYzFkMGI3YTVlNDk2MjhjMWYwYTNkNWI3ZTljMjE=   # the new cluster key
```

```yaml
# wazuh/secrets/wazuh-authd-pass-secret.yaml
data:
  authd.pass: <base64 of the new enrollment password>   # the new enrollment password
```

Drop the `# string "..." base64 encoded` comments the manifests ship with, so they do not describe a value that is no longer there, and keep these edits out of your commits: base64 is encoding, not encryption.

Every agent you enroll afterwards has to present the new enrollment password. See [Credentials](../credentials.md#the-cluster-key-and-the-agent-enrollment-password) for how to change either value on a deployment that is already running.

#### Step 3.3.3: Deploy Wazuh cluster

By using the kustomization file on the `eks` variant we can now deploy the whole cluster with a single command:

```bash
kubectl apply -k envs/eks/
```

#### Step 3.4: First access

Wait for every pod to be `Ready`:

```bash
kubectl -n wazuh wait --for=condition=Ready pod --all --timeout=600s
```

Log in to the Wazuh dashboard as `admin`. Read its generated password with:

```bash
grep '^WAZUH_INDEXER_ADMIN_PASSWORD=' wazuh/config/credentials/indexer.env | cut -d= -f2-
```

See [Credentials](../credentials.md) for the full list of accounts, and how to rotate one on a deployment that is already running.

#### Step 3.5: Enroll an agent

A Wazuh 5.x agent enrolls and reports over the same HTTPS channel, port `1517`, which Traefik publishes on the load balancer from step 3.1 and spreads across every manager node. The steps below enroll it with an enrollment token minted through the Wazuh API: the token carries the manager address and its CA, so the agent needs no other setting.

The address in the token has to be in the SAN of the agent listener certificate: use the load balancer FQDN passed with `--agent-san` in step 3.2.3. Any other address is refused with `address not in certificate SAN`.

The Wazuh API is not published through Traefik, so forward it to mint the token. From the root of the repository:

```bash
kubectl -n wazuh port-forward service/wazuh-api 55000:55000 &
```

Mint a token with the `wazuh` API user, whose password is in `wazuh/config/credentials/manager.env`:

```bash
WAZUH_MANAGER_ADDRESS=$(kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

WAZUH_API_TOKEN=$(printf 'user = "wazuh:%s"\n' "$(grep '^WAZUH_MANAGER_API_PASSWORD=' wazuh/config/credentials/manager.env | cut -d= -f2-)" | \
  curl -sk -K - -X POST "https://localhost:55000/security/user/authenticate?raw=true")

RESPONSE=$(curl -sk -X POST "https://localhost:55000/agents/enrollment-tokens" \
  -H "Authorization: Bearer ${WAZUH_API_TOKEN}" -H "Content-Type: application/json" \
  -d "{\"address\": \"${WAZUH_MANAGER_ADDRESS}\", \"embed_ca\": true}")
WAZUH_ENROLLMENT_TOKEN=$(printf '%s' "${RESPONSE}" | sed -n 's/.*"token": *"\([^"]*\)".*/\1/p')
[ -n "${WAZUH_ENROLLMENT_TOKEN}" ] && echo "Token minted" || echo "${RESPONSE}"
```

Start an agent container with it, on any host that reaches the load balancer on port `1517`:

```bash
docker run -d --name wazuh-agent \
  -e WAZUH_ENROLLMENT_TOKEN="${WAZUH_ENROLLMENT_TOKEN}" \
  -e WAZUH_AGENT_NAME=eks-test-agent \
  -v wazuh_agent_etc:/var/ossec/etc \
  wazuh/wazuh-agent:5.0.0
```

The agent container variables and the optional fields of `POST /agents/enrollment-tokens` (`ttl`, `max_uses`, `description`) are described in the [wazuh-docker agent guide](https://github.com/wazuh/wazuh-docker/blob/5.0.0/docs/ref/getting-started/deployment/wazuh-agent.md).

Check that it is listed as `active`:

```bash
curl -sk -H "Authorization: Bearer ${WAZUH_API_TOKEN}" \
  "https://localhost:55000/agents?select=name,status&pretty=true"
```

The API token lasts 15 minutes; if the answer is `Invalid token`, run the `WAZUH_API_TOKEN=...` command again.

> **Note**: For about the first 30 seconds the agent may log `Enrollment rejected by the manager: token_unknown`, `credential rejected (401); re-enrolling` and `Manager unreachable`. The token and the agent key are created on the master and take a few seconds to reach every manager node, and the load balancer can send the agent to a node that does not have them yet. The agent retries on its own until `re-enrollment succeeded` and `Manager reachable again`.

#### Conclusion

At this point, the Wazuh stack should be deployed in your EKS cluster.

To validate the deployment and open the web UI, follow the steps in the **Accessing Wazuh dashboard** section: [Accessing Wazuh dashboard (EKS)](#accessing-wazuh-dashboard-eks).

## Local deployment

This guide describes the necessary steps to deploy Wazuh on local Kubernetes environment using Minikube and Calico as the CNI.
As an important additional isolation layer, this deployment includes NetworkPolicy configurations to restrict communication between pods.

### Pre-requisites

- Kubernetes cluster running
- kubectl installed and configured to connect to the cluster

#### Resource requirements

To deploy the `local-env` variant the Kubernetes cluster should have at least the following resources **available**:

- 2 CPU units
- 4.5 Gi of memory
- 2.5 Gi of storage

### Deployment

**Note**:

If you are using Minikube, make sure Docker Desktop has at least 6 GiB of memory allocated (Docker Desktop -> Settings -> Resources), then start the cluster with Calico CNI:

```bash
minikube start --memory=6144 --cpus=4 --network-plugin=cni --cni=calico
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
curl -so wazuh-certs-tool.sh https://packages.wazuh.com/5.0/wazuh-certs-tool-5.0.0-1.sh
curl -so wazuh-credentials.sh https://raw.githubusercontent.com/wazuh/wazuh-installation-assistant/5.0.0/credentials_lib/wazuh-credentials.sh
curl -so config.yml https://packages.wazuh.com/5.0/config-5.0.0-1.yml
```

`wazuh-credentials.sh` is the library `credentials-conf.sh` uses in the next steps. Use the same
version as the images.

Edit the `config.yml` file to set corresponding name and IP address for each Wazuh component.
For a local environment, you can use:

```yaml
nodes:
  # Wazuh indexer nodes
  indexer:
    - name: indexer
      dns:
        - "wazuh-indexer"
        - "wazuh-indexer.wazuh.svc.cluster.local"
        - "wazuh-indexer-0.wazuh-indexer"
        - "wazuh-indexer-0.wazuh-indexer.wazuh.svc.cluster.local"

  # Wazuh server nodes
  manager:
    - name: manager
      dns:
        - "wazuh-api"
        - "wazuh-api.wazuh.svc.cluster.local"
        - "wazuh-agents"
        - "wazuh-agents.wazuh.svc.cluster.local"

  # Wazuh dashboard nodes
  dashboard:
    - name: dashboard
      dns:
        - "dashboard"
        - "dashboard.wazuh.svc.cluster.local"
        - "localhost"
```

> **Note**: The Wazuh indexer nodes verify each other's certificate on the transport port against
> the name each one publishes, `wazuh-indexer-<n>.wazuh-indexer.<namespace>.svc.cluster.local`, set
> by `network.publish_host` in `indexer-sts.yaml`. The `dns` list therefore needs one pair of
> entries per indexer replica, or the nodes cannot form a cluster. Adjust it if you change the
> replica count of the overlay.

> **Note**: `localhost` in the `dashboard` list is the name the dashboard is opened with through the port-forward in [Accessing Dashboard](#accessing-dashboard). Add any other name you open it with. An IP address, such as the one given to `--address` there, goes in an `ip` list of the same node, because `wazuh-certs-tool.sh` refuses an IP in `dns`:
>
> ```yaml
>   dashboard:
>     - name: dashboard
>       ip:
>         - "192.168.1.34"
>       dns:
>         - "dashboard"
>         - "dashboard.wazuh.svc.cluster.local"
>         - "localhost"
> ```
>
> A name that is not in the certificate fails verification with `no alternative certificate subject name matches target host name`.

> **Note**: The `manager` entry also produces the agent listener certificate (`manager-remoted.pem` and `manager-remoted-key.pem`), which `remoted` serves on port `1517`. Its SAN is taken from the `dns` list above, plus every `--agent-san` passed to the next command, which adds an address to that certificate only. `--agent-san localhost` is what lets agents enroll through a port-forward, as in [Enrolling an agent](#enrolling-an-agent). Repeat the flag for any other address agents use to reach the manager.

Run `wazuh-certs-tool.sh` to create the certificates.

```bash
sudo bash ../tools/utils/deployment/certificates-conf.sh --cert --copy --priv --agent-san localhost
```

#### Run the credentials generator

Every Wazuh component now generates or validates its own credentials at install time and refuses to
start without them. Generate the five passwords before the first `kubectl apply -k`. The script
sources `wazuh-credentials.sh`, downloaded with the certificates tool:

```bash
sudo bash ../tools/utils/deployment/credentials-conf.sh
```

Return to the root of the repository.

```bash
cd ..
```

**Note**:

The required certificates are imported via secretGenerator on the `kustomization.yml` file:

```yaml
secretGenerator:
  - name: indexer-certs
    files:
      - config/indexer/certs/admin-key.pem
      - config/indexer/certs/admin.pem
      - config/indexer/certs/indexer-key.pem
      - config/indexer/certs/indexer.pem
      - config/root-ca/certs/root-ca.pem
  - name: dashboard-certs
    files:
      - config/dashboard/certs/dashboard-key.pem
      - config/dashboard/certs/dashboard.pem
      - config/root-ca/certs/root-ca.pem
  - name: manager-certs
    files:
      - config/manager/certs/manager-key.pem
      - config/manager/certs/manager.pem
      - config/manager/certs/manager-remoted-key.pem
      - config/manager/certs/manager-remoted.pem
      - config/root-ca/certs/root-ca.pem
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

On Minikube the provisioner is `k8s.io/minikube-hostpath`: comment out the `microk8s.io/hostpath` line in `envs/local-env/storage-class.yaml` and uncomment the `k8s.io/minikube-hostpath` one. Otherwise the claims stay `Pending`.

#### Change Wazuh ingress host

<!-- To deploy correctly in a local environment, it is necessary to change the parameter `<UPDATE-WITH-THE-FQDN-OF-THE-INGRESS>` to `localhost` in the file `wazuh/base/ingressRoute-tcp-dashboard.yaml`, for example:

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
  - match: HostSNI(`localhost`)
    middlewares:
    - name: ip-allowlist
    services:
    - name: dashboard
      port: 443
  tls:
    passthrough: true

``` -->

The `wazuh/base/ingressRoute-tcp-dashboard.yaml` file configures the Wazuh Dashboard ingress and is primarily intended for EKS deployments. To prevent this file from affecting your local deployment, it is recommended to either delete its contents or leave it empty.

```bash
echo "" > wazuh/base/ingressRoute-tcp-dashboard.yaml
```

#### Set the cluster key and the agent enrollment password

Two of the Secrets under `wazuh/secrets/` hold shared keys rather than account passwords. Neither ships with a usable value: the cluster key is a placeholder, and the enrollment password is the string `password`.

| Secret | Key | Default value | What it protects |
| --- | --- | --- | --- |
| `wazuh-cluster-key` | `key` | `REPLACETHISCLUSTERKEYBEFOREDEPLO` (placeholder, not a key) | Membership of the Wazuh manager cluster, on port `1516` |
| `wazuh-authd-pass` | `authd.pass` | `password` | Agent enrollment: the channel `remoted` serves on port `1517`, and the legacy `authd` port `1515` |

**Change both here, before the first `kubectl apply -k`.** Unlike the Wazuh indexer and Wazuh API accounts, these are not accounts inside an image, so `password-tool.sh` does not cover them: the managers read them from the Secrets on every container start. Setting them now costs nothing, while changing the cluster key on a running deployment stops the workers from syncing until every manager pod has restarted on the new key.

Generate the two values. The cluster key has to be **exactly 32 alphanumeric characters** (`^[a-zA-Z0-9]{32}$`); `openssl rand -hex 16` produces exactly that. A key of any other length, or one carrying `-`, `_` or any other punctuation, makes every manager refuse to start with `(1244): Invalid configuration at '/cluster/key': does not satisfy 'pattern'`:

```bash
openssl rand -hex 16   # cluster key, 32 hexadecimal characters
openssl rand -hex 24   # enrollment password
```

Encode each one, without a trailing newline:

```bash
echo -n '8f3c1d0b7a5e49628c1f0a3d5b7e9c21' | base64
```

Then write them into the two manifests, keeping the key names as they are:

```yaml
# wazuh/secrets/wazuh-cluster-key-secret.yaml
data:
  key: OGYzYzFkMGI3YTVlNDk2MjhjMWYwYTNkNWI3ZTljMjE=   # the new cluster key
```

```yaml
# wazuh/secrets/wazuh-authd-pass-secret.yaml
data:
  authd.pass: <base64 of the new enrollment password>   # the new enrollment password
```

Drop the `# string "..." base64 encoded` comments the manifests ship with, so they do not describe a value that is no longer there, and keep these edits out of your commits: base64 is encoding, not encryption.

Every agent you enroll afterwards has to present the new enrollment password. See [Credentials](../credentials.md#the-cluster-key-and-the-agent-enrollment-password) for how to change either value on a deployment that is already running.

#### Apply all manifests using kustomize

We are using the overlay feature of kustomize to create two variants: `eks` and `local-env`, in this guide we're using `local-env`.

It is possible to adjust resources for the cluster by editing patches on `envs/local-env/`, the number of replicas for Wazuh Indexer nodes and Wazuh Server workers are reduced on the `local-env` variant to save resources. This could be undone by removing these patches from `envs/local-env/kustomization.yml` or alter the patches themselves with different values.

> **Note**: This guide was created using Minikube and Calico as the CNI.

Deploy Traefik CRD

```bash
kubectl apply -f traefik/crd/
```

Expected output:

```bash
$ kubectl apply -f traefik/crd/
customresourcedefinition.apiextensions.k8s.io/ingressroutes.traefik.io created
customresourcedefinition.apiextensions.k8s.io/ingressroutetcps.traefik.io created
customresourcedefinition.apiextensions.k8s.io/ingressrouteudps.traefik.io created
Warning: unrecognized format "int64"
customresourcedefinition.apiextensions.k8s.io/middlewares.traefik.io created
customresourcedefinition.apiextensions.k8s.io/middlewaretcps.traefik.io created
customresourcedefinition.apiextensions.k8s.io/serverstransports.traefik.io created
customresourcedefinition.apiextensions.k8s.io/serverstransporttcps.traefik.io created
customresourcedefinition.apiextensions.k8s.io/tlsoptions.traefik.io created
customresourcedefinition.apiextensions.k8s.io/tlsstores.traefik.io created
customresourcedefinition.apiextensions.k8s.io/traefikservices.traefik.io created
```

By using the kustomization file on the `local-env` variant we can now deploy the whole cluster with a single command:

```bash
kubectl apply -k envs/local-env/
```

#### First access

Wait for every pod to be `Ready`:

```bash
kubectl -n wazuh wait --for=condition=Ready pod --all --timeout=600s
```

Log in to the Wazuh dashboard as `admin`. Read its generated password with:

```bash
grep '^WAZUH_INDEXER_ADMIN_PASSWORD=' wazuh/config/credentials/indexer.env | cut -d= -f2-
```

See [Credentials](../credentials.md) for the full list of accounts, and how to rotate one on a deployment that is already running.

##### Accessing Dashboard

To access the Dashboard interface you can use port-forward:

```bash
kubectl -n wazuh port-forward service/dashboard 8443:443
```

Access to Wazuh dashboard using <https://localhost:8443>

Log in as `admin` with the password `credentials-conf.sh` generated (see [First access](#first-access) above). See [Credentials](../credentials.md).

The certificate is signed by the deployment's own CA, so the browser warns about it until `wazuh/config/root-ca/certs/root-ca.pem` is trusted. To check the certificate without trusting the CA system-wide:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' --cacert wazuh/config/root-ca/certs/root-ca.pem https://localhost:8443/
```

Any answer other than `000` means the name and the chain verified. `no alternative certificate subject name matches target host name 'localhost'` means the certificates were created without `localhost` in the `dashboard` list (see [Setup SSL certificates](#setup-ssl-certificates)).

<!-- If you need to access the dashboard from another host (or register agents pointing to the Minikube host IP), you can bind the port-forward to a specific interface/IP address: -->

If you need to access the dashboard from another host, you can bind the port-forward to a specific interface/IP address:

```bash
kubectl -n wazuh port-forward service/dashboard 8443:443 --address 192.168.1.34 &
```

##### Exposing Wazuh server ports

```bash
kubectl -n wazuh port-forward service/wazuh-agents 1517:1517
```

For Wazuh 4.x agents, the legacy ports are exposed the same way:

```bash
kubectl -n wazuh port-forward service/wazuh-events 1514:1514
```

```bash
kubectl -n wazuh port-forward service/wazuh-registration 1515:1515
```

If you need to register agents pointing directly to the Minikube host IP, bind the port-forward to a specific interface/IP address adding the `--address` flag (as done previously for the dashboard).

> **Note**: You can run the process in background adding `&` to the port-forward command, for example: kubectl -n wazuh port-forward service/wazuh-agents 1517:1517 &

##### Enrolling an agent

A Wazuh 5.x agent enrolls and reports over the same HTTPS channel, port `1517`, so the `wazuh-agents` port-forward above is the only agent port it needs. The steps below enroll it with an enrollment token minted through the Wazuh API: the token carries the manager address and its CA, so the agent needs no other setting.

The address in the token has to be in the SAN of the agent listener certificate. For an agent going through the port-forward that address is `localhost`, which is there when the certificates were created with `--agent-san localhost` (see [Setup SSL certificates](#setup-ssl-certificates)). Otherwise the API refuses the token:

```text
{"title": "Bad Request", "detail": "Enrollment token refused: address not in certificate SAN", ...}
```

On a deployment whose certificates do not have `localhost`, use `WAZUH_MANAGER_ADDRESS=wazuh-agents` below, which is always in the SAN, and add `--add-host wazuh-agents:127.0.0.1` to the `docker run` command so that the name resolves to the port-forward.

Forward the Wazuh API and the agent port, from the root of the repository:

```bash
kubectl -n wazuh port-forward service/wazuh-api 55000:55000 &
kubectl -n wazuh port-forward service/wazuh-agents 1517:1517 &
```

Mint a token with the `wazuh` API user, whose password is in `wazuh/config/credentials/manager.env`:

```bash
WAZUH_MANAGER_ADDRESS=localhost

WAZUH_API_TOKEN=$(printf 'user = "wazuh:%s"\n' "$(grep '^WAZUH_MANAGER_API_PASSWORD=' wazuh/config/credentials/manager.env | cut -d= -f2-)" | \
  curl -sk -K - -X POST "https://localhost:55000/security/user/authenticate?raw=true")

RESPONSE=$(curl -sk -X POST "https://localhost:55000/agents/enrollment-tokens" \
  -H "Authorization: Bearer ${WAZUH_API_TOKEN}" -H "Content-Type: application/json" \
  -d "{\"address\": \"${WAZUH_MANAGER_ADDRESS}\", \"embed_ca\": true}")
WAZUH_ENROLLMENT_TOKEN=$(printf '%s' "${RESPONSE}" | sed -n 's/.*"token": *"\([^"]*\)".*/\1/p')
[ -n "${WAZUH_ENROLLMENT_TOKEN}" ] && echo "Token minted" || echo "${RESPONSE}"
```

Start an agent container with it. `--network host` lets the container reach the port-forward on `localhost:1517`:

```bash
docker run -d --name wazuh-agent --network host \
  -e WAZUH_ENROLLMENT_TOKEN="${WAZUH_ENROLLMENT_TOKEN}" \
  -e WAZUH_AGENT_NAME=k8s-test-agent \
  -v wazuh_agent_etc:/var/ossec/etc \
  wazuh/wazuh-agent:5.0.0
```

Check that it is listed as `active`:

```bash
curl -sk -H "Authorization: Bearer ${WAZUH_API_TOKEN}" \
  "https://localhost:55000/agents?select=name,status&pretty=true"
```

The API token lasts 15 minutes; if the answer is `Invalid token`, run the `WAZUH_API_TOKEN=...` command again. The optional fields of `POST /agents/enrollment-tokens` (`ttl`, `max_uses`, `description`) and the agent container variables are described in the [wazuh-docker agent guide](https://github.com/wazuh/wazuh-docker/blob/5.0.0/docs/ref/getting-started/deployment/wazuh-agent.md).

> **Note**: A port-forward to a Service attaches to a single manager pod, so every agent enrolled this way reports to that pod.

> **Note**: For about the first 30 seconds the agent may log `Enrollment rejected by the manager: token_unknown`, `credential rejected (401); re-enrolling` and `Manager unreachable`. The token and the agent key are created on the master and take a few seconds to reach the other manager nodes, and the port-forward may have attached to a worker. The agent retries on its own until `re-enrollment succeeded` and `Manager reachable again`.

### Conclusion

At this point, the Wazuh stack should be deployed in your local Kubernetes cluster.

To validate the deployment and its created resources check the following section: [Verifying the deployment](#verifying-the-deployment).

## Verifying the deployment

The outputs below are for `envs/eks`. With `envs/local-env` there is one indexer and one worker, the
claims are 500Mi (1Gi for the dashboard), and the three `allow-ingress-to-*` policies are not created.

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
wazuh-agents         ClusterIP   10.100.22.19     <none>        1517/TCP            23m
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

### Persistent volume claims

```bash
kubectl -n wazuh get pvc
```

Expected output:

```bash
$ kubectl -n wazuh get pvc
NAME                                              STATUS   VOLUME     CAPACITY   ACCESS MODES   STORAGECLASS    AGE
wazuh-dashboard-config                            Bound    pvc-6f1…   1Gi        RWO            wazuh-storage   4h17m
wazuh-indexer-wazuh-indexer-0                     Bound    pvc-a12…   10Gi       RWO            wazuh-storage   4h17m
wazuh-indexer-wazuh-indexer-1                     Bound    pvc-b34…   10Gi       RWO            wazuh-storage   4h17m
wazuh-indexer-wazuh-indexer-2                     Bound    pvc-c56…   10Gi       RWO            wazuh-storage   4h17m
wazuh-manager-master-wazuh-manager-master-0       Bound    pvc-d78…   50Gi       RWO            wazuh-storage   4h17m
wazuh-manager-worker-wazuh-manager-worker-0       Bound    pvc-e90…   50Gi       RWO            wazuh-storage   4h17m
wazuh-manager-worker-wazuh-manager-worker-1       Bound    pvc-f12…   50Gi       RWO            wazuh-storage   4h17m
```

One claim per manager pod carries `etc`, `api/configuration`, `logs`, `queue`, `var/multigroups` and `data` under separate `subPath`s, and the dashboard claim carries its configuration directory and keystore. See [Configuration files](../configuration/configuration-files.md#persistence-configuration).

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
manager-egress                    app=wazuh-manager                    43s
manager-egress-external           app=wazuh-manager                    42s
wazuh-api-ingress                 app=wazuh-manager,node-type=master   42s
wazuh-worker-egress               app=wazuh-manager,node-type=worker   41s
```

### Secrets

```bash
kubectl -n wazuh get secrets
```

Expected: `dashboard-certs-<hash>`, `dashboard-credentials-<hash>`, `indexer-certs-<hash>`,
`indexer-credentials-<hash>`, `manager-certs-<hash>`, `manager-credentials-<hash>`, `wazuh-authd-pass`
and `wazuh-cluster-key`.

### Credentials

Every pod runs an `install-credentials` init container that hands it its credentials file. No
password is in the container environment:

```bash
kubectl -n wazuh exec wazuh-manager-master-0 -c wazuh-manager -- env | grep -c PASSWORD
```

Expected output: `0`. Check that every account authenticates with its generated password and none
with a default:

```bash
cd wazuh && ../tools/tests/check-default-credentials.sh && cd ..
```

### Accessing Wazuh dashboard (EKS)

In case you created domain names for the services, you should be able to access Wazuh dashboard using the proposed domain name: <https://wazuh.your-domain.com>.
Log in as `admin` with the password `credentials-conf.sh` generated (**Step 3.4**). See [Credentials](../credentials.md).
Also, you can access using the External-IP of the load balancer, from any address the `ip-allowlist` middleware (`wazuh/base/middleware.yaml`) allows: <https://xxx-yyy-zzz.us-west-1.elb.amazonaws.com:443>
To access the Wazuh dashboard of a local deployment, please refer to [Accessing Dashboard](#accessing-dashboard).

The certificate is signed by the deployment's own CA, so the browser warns about it until `wazuh/config/root-ca/certs/root-ca.pem` is trusted. The name you open the dashboard with has to be in the `dashboard` list of `config.yml` (step 3.2.2). To check both without trusting the CA system-wide:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' --cacert wazuh/config/root-ca/certs/root-ca.pem \
  "https://$(kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/"
```

```bash
kubectl -n traefik get svc
```

Expected output:

```bash
$ kubectl -n traefik get svc
NAME      TYPE           CLUSTER-IP     EXTERNAL-IP                                                              PORT(S)                                       AGE
traefik   LoadBalancer   10.100.34.51   a7ffe29bfcf38420988fd52a698be422-862207742.us-west-1.elb.amazonaws.com   443:30725/TCP,1517:31485/TCP,1514:32036/TCP,1515:30354/TCP   6m29s
```
