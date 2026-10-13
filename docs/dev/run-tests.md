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
- **Manager services**: Ensures at least 7 Wazuh manager services are running correctly
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
| `--indexer-user` | `admin` | Wazuh indexer account the tests authenticate with. |
| `--indexer-password` | its value in `wazuh/config/credentials/indexer.env` | Password of that account. |

Without `--indexer-password`, the suite reads the password `credentials-conf.sh` generated from `wazuh/config/credentials/indexer.env`, so running it from the checkout the deployment was created from needs no options. From anywhere else, pass it:

```bash
pytest tests/k8s_pytest.py -v --deployment-type local \
  --indexer-password '<the admin password>'
```

If neither is available, every test that authenticates stops with `no password for 'admin'`. The password reaches `curl` on standard input, never as an argument. See [Credentials](../ref/credentials.md).

## Automated testing workflows

The PR check `.github/workflows/5_check_k8s_integration_tests.yaml` deploys the branch on Minikube or on a temporary EKS cluster and runs the integration test module of wazuh-automation (`test_runner`), not this suite. It runs when the `test/k8s`, `test/k8s-local` or `test/k8s-eks` label is added to a non-draft pull request, or manually from the Actions tab. See [Kubernetes Integration Tests](../ref/integration_test/k8s_integration_tests.md).
