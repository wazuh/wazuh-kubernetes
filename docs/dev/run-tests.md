# Run tests

This section describes how to run the automated tests for Wazuh Kubernetes deployments. The test suite validates that all Wazuh components are correctly deployed and functioning in the Kubernetes cluster.

## Prerequisites

The following tests require these tools and dependencies:

- **Python**: Python 3.x
- **pytest**: Install via package manager or pip
- **kubectl**: Configured to communicate with your Kubernetes cluster

## Test coverage

The test suite validates the following aspects of the Wazuh Kubernetes deployment:

- **Indexer cluster health**: Verifies that the Wazuh indexer cluster health status is `green`
- **Indexer indices health**: Confirms all Wazuh indexer indices are in a `green` state
- **Indexer nodes count**: Checks the expected number of indexer nodes based on the deployment type (3 for EKS, 1 for local)
- **Wazuh templates**: Validates that required Wazuh templates are present in the indexer
- **Manager services**: Ensures at least 10 Wazuh manager services are running correctly
- **Dashboard accessibility**: Confirms the Wazuh dashboard service returns HTTP 200 status

## Running the tests

From the root of the repository, against a deployment that is already up:

```bash
pytest tests/k8s_pytest.py -v --deployment-type local    # or: --deployment-type eks
```

A single test:

```bash
pytest tests/k8s_pytest.py::TestWazuhKubernetes::test_indexer_cluster_health -v
```

### Options

| Option | Default | Purpose |
| --- | --- | --- |
| `--deployment-type` | `local` | `local` or `eks`. Only changes the expected indexer node count: 3 for `eks`, 1 for `local`. |
| `--dashboard-url` | `localhost` | Host the dashboard check targets. With `localhost` the check runs inside the dashboard pod; any other value is curled from the host. |
| `--indexer-user` | `wazuh-admin` | Wazuh indexer account the tests authenticate with. |
| `--indexer-password` | `wazuh-admin` | Password of that account. |

`--indexer-password` defaults to the password the indexer image ships, so a deployment that has not been through the credential rotation needs no options at all. **After rotating the `wazuh-admin` password, the suite fails until you pass the new one:**

```bash
pytest tests/k8s_pytest.py -v --deployment-type local \
  --indexer-password '<the new wazuh-admin password>'
```

See [Credentials](../ref/credentials.md) for the rotation procedure.

## Automated testing workflows

The repository includes two GitHub Actions workflows for automated testing:

### EKS deployment test

The EKS workflow (eks-deployment-test.yml) performs a full end-to-end test on AWS EKS:

1. Deploys a temporary multi-node EKS cluster
2. Configures AWS EBS CSI driver and network policies
3. Generates SSL certificates for Wazuh components
4. Deploys the Traefik ingress controller
5. Deploys the Wazuh stack using the eks overlay
6. Runs the complete test suite with `--deployment-type eks`
7. Cleans up all resources (cluster and EBS volumes)

Trigger this workflow manually from the Actions tab by specifying the branch version to test.

### Local deployment test

The local workflow (local-deployment-test.yml) tests on a Minikube cluster:

1. Sets up a Minikube cluster with Calico CNI
2. Pulls Wazuh container images from AWS ECR
3. Generates SSL certificates for Wazuh components
4. Configures the Minikube storage provisioner
5. Deploys the Wazuh stack using the local-env overlay
6. Runs the complete test suite with `--deployment-type local`

This workflow runs automatically on pull requests and can be triggered manually from the Actions tab.
