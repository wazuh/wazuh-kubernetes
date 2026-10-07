# Kubernetes Integration Tests

Workflow file: `.github/workflows/5_check_k8s_integration_tests.yaml`

This workflow provisions a Kubernetes cluster (Minikube or EKS), deploys Wazuh, and runs the integration test suite against the live deployment. It can be triggered manually or by adding a label to a PR.

---

## Triggers

The workflow supports two execution modes:

| Mode | Trigger | Who can trigger |
|---|---|---|
| PR label | `pull_request` (`labeled`) on a non-draft PR opened from a branch of this repository | Anyone who can add labels (triage access or higher) |
| Manual | `workflow_dispatch` | Anyone with repo write access |

To run the tests on a pull request, add one of the labels listed in [pull_request (label) flow](#pull_request-label-flow). Each label added starts one run against the PR head at that moment:

- To run the tests again (for example after pushing new commits), remove the label and add it again.
- Labels added while the PR is a draft are ignored. Mark the PR as ready for review and add the label again.
- PRs opened from forks do not run: GitHub does not pass secrets or the OIDC token to `pull_request` runs from forks. Push the branch to this repository to test it.

---

## Execution Flows

### pull_request (label) flow

Triggered when one of these labels is added to a non-draft PR opened from a branch of this repository.

```mermaid
flowchart TD
    A[Label added to PR] --> B{Test label on a non-draft\nPR from this repository?}
    B -- No --> Z[Ignored]
    B -- Yes --> C[get_pr_info\nExtract PR data · Parse label]
    C --> D[prepare\nResolve branch · Read VERSION.json]
    D --> E{deployment_matrix}
    E --> F[kubernetes_test\ndeployment_type=local]
    E --> G[kubernetes_test\ndeployment_type=eks]
```

**Labels:**

| Label | Deployment matrix |
|---|---|
| `test/k8s` | `["local","eks"]` |
| `test/k8s-local` | `["local"]` |
| `test/k8s-eks` | `["eks"]` |

Any other label, a draft PR or a PR opened from a fork skips `get_pr_info` and the rest of the workflow.

### workflow_dispatch flow

Triggered manually. Skips `get_pr_info`.

```mermaid
flowchart TD
    A[Manual trigger] --> D[prepare\nResolve branch · Read VERSION.json]
    D --> E{deployment_type input}
    E -- local --> F[kubernetes_test\ndeployment_type=local]
    E -- eks --> G[kubernetes_test\ndeployment_type=eks]
    E -- both --> F & G
```

---

## Parameters

### workflow_dispatch inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `pr_head_ref` | Yes | — | Branch of `wazuh-kubernetes` to check out and test |
| `automation_reference` | No | `5.0.0` | Branch of `wazuh-automation` to install `test_runner` from |
| `deployment_type` | Yes | — | `local`, `eks`, or `both` |
| `version` | No | — | Override image version (e.g. `5.0.1`). If empty, reads from `VERSION.json` |
| `stage` | No | — | Image stage suffix (e.g. `beta1`, `beta2-latest`). Required when `version` is set manually |
| `registry` | No | `ECR` | `ECR` (dev images) or `DockerHub` (prod images) |

### pull_request (label) parameters

When triggered by a PR label, all parameters are derived automatically:

| Parameter | Source |
|---|---|
| `pr_head_ref` | PR head branch from the event payload |
| `pr_head_sha` | PR head SHA from the event payload |
| `deployment_matrix` | Mapped from the label name |
| `version` / `stage` | Read from `VERSION.json` on the PR branch |
| `registry` | Defaults to ECR |
| `automation_reference` | Base branch of the PR (for example `5.0.0` for a PR against `5.0.0`) |

---

## Image Tag Resolution

The effective image tag depends on which inputs are provided:

| `version` input | `stage` input | Registry | Resulting tag |
|---|---|---|---|
| empty | empty | ECR | `{VERSION.json version}{-stage}-latest` |
| empty | empty | DockerHub | `{VERSION.json version}{-stage}` |
| set | empty | ECR | `{version}-latest` |
| set | empty | DockerHub | `{version}` |
| set | set | ECR | `{version}-{stage}` |
| set | set | DockerHub | `{version}-{stage}` |
| empty | set | ECR | `{VERSION.json version}-{stage}` |
| empty | set | DockerHub | `{VERSION.json version}-{stage}` |

The effective `WAZUH_VERSION` (passed to `test_runner`) is always the version that ends up in the tag, whether it comes from `VERSION.json` or the `version` input.

---

## Job Details

### Job 1 — `get_pr_info` (pull_request only)

| Step | What it does |
|---|---|
| Extract PR data | Reads the PR number, head branch and head SHA from the event payload |
| Parse label | Maps the label name → `deployment_matrix` JSON |

### Job 2 — `prepare` (both triggers)

| Step | What it does |
|---|---|
| Resolve context | If `workflow_dispatch`: reads inputs. If `pull_request`: reads outputs from `get_pr_info` |
| Checkout VERSION.json | Sparse-checks out only `VERSION.json` from the target branch |
| Read version info | Extracts `version` and `stage` fields from `VERSION.json` |
| Show test plan | Writes a summary table to the GitHub Actions step summary |

Outputs passed downstream: `pr_head_ref`, `deployment_matrix`, `wazuh_version`, `wazuh_stage`.

### Job 3 — `kubernetes_test` (matrix, both triggers)

Runs once per entry in `deployment_matrix`. Each instance provisions its own cluster.

#### Common setup

1. Checkout `wazuh-automation` at `automation_reference`
2. Checkout `wazuh-kubernetes` at `pr_head_ref`
3. Set up Python 3.12
4. Install `test_runner`:
   ```bash
   pip install -r wazuh-automation/deployability/deps/requirements.txt
   pip install -r wazuh-automation/integration-test-module/requirements.txt
   pip install -e wazuh-automation/integration-test-module/
   ```
5. Configure AWS credentials via OIDC (`AWS_IAM_ROLE`)
6. Resolve `WAZUH_VERSION`, `IMAGE_REGISTRY`, `IMAGE_TAG` (see [Image Tag Resolution](#image-tag-resolution))

#### Infrastructure provisioning

**Local (Minikube):**

| Step | Detail |
|---|---|
| Free disk space | Removes pre-installed tools to free ~20 GB; removes swap |
| Install Minikube | Downloads and installs latest `minikube-linux-amd64` |
| Start cluster | `minikube start --memory=8192 --cpus=4 --network-plugin=cni --cni=calico` |
| Login to ECR | Only if registry is ECR; authenticates Docker daemon |
| Pull + load images | Pulls `wazuh-dashboard`, `wazuh-indexer`, `wazuh-manager` and loads them into Minikube's internal registry |

**EKS:**

| Step | Detail |
|---|---|
| Install eksctl | Downloads latest `eksctl` binary |
| Create cluster | 6 managed spot nodes (`t3a.medium`), with OIDC; tagged with run metadata |
| EBS CSI driver | Creates IAM service account + installs `aws-ebs-csi-driver` addon |
| Network policies | Creates IAM SA for `aws-node`, enables `NetworkPolicy` support in VPC CNI |

#### Configuration and certificates

1. **Patch image references**: `yq` rewrites the image of every Wazuh container in `dashboard-deploy.yaml`, `indexer-sts.yaml`, `wazuh-master-sts.yaml`, and `wazuh-worker-sts.yaml` to `${IMAGE_REGISTRY}/wazuh/<component>:${IMAGE_TAG}`: the main containers and the `install-credentials`, `init-dashboard-config` and `init-wazuh-etc` init containers. The step fails if a `wazuh/` image is left unpatched
2. **Setup artifact URLs** (`setup_artifacts` composite action): downloads `artifact_urls.yaml` from S3, replaces template variables, exports `wazuh_certs_tool`, `wazuh_credentials` and `wazuh_config_yml` as environment variables. The file is generated by wazuh-automation
3. **Download certs tool, credentials library and config**: fetches `wazuh-certs-tool.sh`, `wazuh-credentials.sh` and `config.yml` from the S3 URLs. The step fails if `artifact_urls.yaml` has no `wazuh_credentials` entry
4. **Update `config.yml` for Kubernetes**: replaces IP-based node addressing with DNS names (cluster-internal service FQDNs)
5. **Generate certificates**: runs `tools/utils/deployment/certificates-conf.sh --cert --copy --priv`, after the ingress step below, because on EKS the load balancer hostname is only known once Traefik is up. On EKS that hostname is passed as `--agent-san`, which adds it to `manager-remoted.pem` and to nothing else
6. **Generate credentials**: runs `tools/utils/deployment/credentials-conf.sh` from `wazuh/`, masks the five generated passwords in the log, and exports `WAZUH_SERVICE_PASSWORD` (the indexer `admin` password) and `WAZUH_API_PASSWORD` (the Wazuh API `wazuh` password) for the following steps
7. **Check the names in the agent listener certificate**: reads the SAN of `wazuh/config/manager/certs/manager-remoted.pem` and fails if it does not name `wazuh-agents`, `wazuh-agents.wazuh.svc.cluster.local` and, on EKS, the load balancer hostname

#### Ingress configuration

**Local:**
- Patches `storage-class.yaml` to use `k8s.io/minikube-hostpath` provisioner
- Sets ingress match to `HostSNI(\`localhost\`)`
- Deploys Traefik CRD only (no Traefik runtime for Minikube)

**EKS:**
- Deploys Traefik CRDs and runtime (`kubectl apply -k traefik/runtime/`)
- Waits 5 minutes for the Traefik LoadBalancer to get a hostname
- Reads the LoadBalancer hostname, sets `HostSNI(\`{hostname}\`)` in the ingress route and keeps it for `--agent-san` in the certificate step

#### Wazuh deployment

```bash
# EKS
kubectl apply -k envs/eks/

# Local
kubectl apply -k envs/local-env/
```

Waits for every workload with `kubectl rollout status`: `statefulset/wazuh-indexer` up to 10 minutes, `statefulset/wazuh-manager-master`, `statefulset/wazuh-manager-worker` and `deployment/wazuh-dashboard` up to 3 minutes each, within a step timeout of 20 minutes.

Then waits up to **10 minutes** for:
- OpenSearch to report `"status"` in cluster health (requires 3 consecutive healthy responses), authenticated as `admin` with `WAZUH_SERVICE_PASSWORD`, sent to `curl` on standard input
- Dashboard to return HTTP 200/302 on `/app/status`

#### Test execution

```bash
test_runner \
  --test-type "kubernetes-${DEPLOY}" \
  --deployment-type "kubernetes-${DEPLOY}" \
  --use-local \
  --version "${WAZUH_VERSION}" \
  --log-level INFO \
  --output github \
  --output-file "test-results-k8s-${DEPLOY}.github"
```

| Argument | Value | Notes |
|---|---|---|
| `--test-type` | `kubernetes-local` or `kubernetes-eks` | Selects the test module set |
| `--deployment-type` | `kubernetes-local` or `kubernetes-eks` | Selects the deployment profile |
| `--use-local` | — | `kubectl` runs locally, not via SSH |
| `--version` | Resolved `WAZUH_VERSION` | Used for version assertion tests |
| `--output github` | — | Emits GitHub Actions annotations |
| `--output-file` | `test-results-k8s-{deploy}.github` | Saved for PR comment and artifact upload |

`test_runner` reads the generated passwords from `WAZUH_SERVICE_PASSWORD` and `WAZUH_API_PASSWORD`, exported by the credentials step.

For details on what `kubernetes-local` and `kubernetes-eks` test types validate, see the `Integration Test Module — Description` of the internal documentation.

#### Reporting

| Output | When | Content |
|---|---|---|
| Step summary | Always | Test results appended to `$GITHUB_STEP_SUMMARY` |
| PR comment | `pull_request` trigger only | Posts or updates a comment (identified by HTML marker `<!-- k8s-integration-check-{deploy} -->`) with ✅/❌ and the results file content |
| Artifact: `test-results-k8s-{deploy}-{run_id}` | Always | The `.github` results file, retained 7 days |
| Artifact: `k8s-logs-{deploy}-{run_id}` | On failure only | `kubectl` logs of every container, init containers included, of all pods in `wazuh` namespace, retained 7 days |

#### EKS cleanup (always runs, even on failure)

```bash
eksctl delete cluster --name k8s-integration-test-{run_number}-eks --region {AWS_REGION}

# Delete any EBS volumes tagged with the cluster name
aws ec2 delete-volume --volume-id <id>
```

Minikube clusters are ephemeral — no explicit cleanup is needed for local deployments.

---

## Required Secrets and Variables

### Secrets

| Secret | Used by |
|---|---|
| `AWS_ACCOUNT_ID` | ECR registry URL construction |
| `AWS_REGION` | All AWS operations |
| `AWS_IAM_ROLE` | OIDC role assumption for AWS credentials |
| `ARTIFACTS_S3_BUCKET` | Download `artifact_urls.yaml` |
| `GH_CLONE_TOKEN` | Checkout `wazuh-automation` (private repo) |
| `GITHUB_TOKEN` | PR comments (built-in) |

### Repository variables

| Variable | Used by |
|---|---|
| `IMAGE_REGISTRY_PROD` | DockerHub registry URL |
| `IMAGE_REGISTRY_DEV` | ECR registry URL fallback label |
| `AWS_S3_BUCKET_DEV` | Artifact URL template expansion |

---

## Permissions

| Permission | Scope | Purpose |
|---|---|---|
| `id-token: write` | OIDC token | Authenticate to AWS via IAM role |
| `contents: read` | Repository | Checkout the PR branch |
| `pull-requests: write` | PR | Post/update PR comments |
| `issues: write` | Issues | Post comments (PR comments use the issues API) |

---

## Cluster Naming

EKS clusters are named:

```
k8s-integration-test-{github.run_number}-{deployment_type}
```

Example: `k8s-integration-test-4217-eks`

This name is used for both cluster creation and deletion, and appears in resource tags for cost attribution.
