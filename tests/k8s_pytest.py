import subprocess
import pytest
import re
from pathlib import Path

CREDENTIALS_FILE = Path(__file__).resolve().parent.parent / "wazuh" / "config" / "credentials" / "indexer.env"
PASSWORD_KEYS = {
    "admin": "WAZUH_INDEXER_ADMIN_PASSWORD",
    "kibanaserver": "WAZUH_INDEXER_KIBANASERVER_PASSWORD",
    "wazuh-manager": "WAZUH_INDEXER_MANAGER_PASSWORD",
}


def generated_password(user):
    """Password of an indexer account, as credentials-conf.sh wrote it."""
    key = PASSWORD_KEYS.get(user)
    if key and CREDENTIALS_FILE.is_file():
        for line in CREDENTIALS_FILE.read_text().splitlines():
            if line.startswith(f"{key}="):
                return line.split("=", 1)[1]
    return None


def run(cmd, user, password):
    """Run a command whose curl reads the credentials on stdin (-K -)."""
    return subprocess.run(cmd, shell=True, capture_output=True, text=True,
                          input=f'user = "{user}:{password}"\n')

class TestWazuhKubernetes:
    """Test suite for Wazuh Kubernetes deployment"""

    @pytest.fixture(scope="class")
    def namespace(self):
        """Kubernetes namespace where Wazuh is deployed"""
        return "wazuh"

    @pytest.fixture(scope="class")
    def indexer_cred(self, request):
        """Wazuh indexer credentials the tests authenticate with.

        The password comes from --indexer-password or, without it, from
        wazuh/config/credentials/indexer.env (see docs/ref/credentials.md).
        """
        user = request.config.getoption("--indexer-user")
        password = request.config.getoption("--indexer-password") or generated_password(user)
        if not password:
            pytest.fail(f"no password for '{user}': pass --indexer-password, or run the "
                        f"tests from a checkout that has {CREDENTIALS_FILE}")
        return user, password

    @pytest.fixture(scope="class")
    def dashboard_pod(self, namespace):
        """Get Wazuh dashboard pod name"""
        cmd = f"kubectl -n {namespace} get pods -l app=wazuh-dashboard -o jsonpath='{{.items[0].metadata.name}}'"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return result.stdout.strip()

    def test_indexer_cluster_health(self, namespace, indexer_cred):
        """Check if Wazuh indexer cluster health is green"""
        user, password = indexer_cred
        cmd = f'kubectl -n {namespace} exec -i wazuh-indexer-0 -- curl -XGET "https://localhost:9200/_cluster/health" -K - -k -s'
        result = run(cmd, user, password)

        print(f"Cluster health status: {result.stdout}")
        assert "green" in result.stdout, "Cluster health is not green"

    def test_indexer_indices_health(self, namespace, indexer_cred):
        """Check if all Wazuh indexer indices are green"""
        user, password = indexer_cred
        cmd = f'kubectl -n {namespace} exec -i wazuh-indexer-0 -- curl -XGET "https://localhost:9200/_cat/indices" -K - -k -s'
        result = run(cmd, user, password)

        print(f"Indices status:\n{result.stdout}")

        lines = result.stdout.strip().split('\n')
        lines_total = len([line for line in lines if line.strip()])
        lines_green = len([line for line in lines if 'green' in line])

        assert lines_total == lines_green, f"Not all indices are green: {lines_green}/{lines_total}"

    def test_indexer_nodes_count(self, namespace, indexer_cred, request):
        """Check if there are the expected number of Wazuh indexer nodes"""
        user, password = indexer_cred
        deployment_type = request.config.getoption("--deployment-type", default="local")
        expected_nodes = 3 if deployment_type == "eks" else 1

        cmd = f'kubectl -n {namespace} exec -i wazuh-indexer-0 -- curl -XGET "https://localhost:9200/_cat/nodes" -K - -k -s'
        result = run(cmd, user, password)

        nodes_count = len(re.findall(r'indexer', result.stdout))
        print(f"Deployment type: {deployment_type}")
        print(f"Wazuh indexer nodes: {nodes_count}")

        assert nodes_count == expected_nodes, f"Expected {expected_nodes} indexer nodes for {deployment_type} deployment, found {nodes_count}"

    def test_wazuh_templates(self, namespace, indexer_cred):
        """Check if Wazuh templates are present (more than 3)"""
        user, password = indexer_cred
        cmd = f'kubectl -n {namespace} exec -i wazuh-indexer-0 -- curl -XGET "https://localhost:9200/_cat/templates" -K - -k -s'
        result = run(cmd, user, password)

        templates = re.findall(r'.*(?:wazuh|wazuh-agent|wazuh-statistics).*', result.stdout)
        qty_templates = len(templates)

        print("Wazuh templates:")
        for template in templates:
            print(template)

        assert qty_templates > 3, f"Expected more than 3 templates, found {qty_templates}"

    def test_manager_services_running(self, namespace):
        """Check if Wazuh manager has at least 7 services running"""
        cmd = f'kubectl -n {namespace} exec wazuh-manager-master-0 -- /var/wazuh-manager/bin/wazuh-manager-control status'
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)

        print("Wazuh Manager services status:")
        print(result.stdout)

        running_services = len(re.findall(r'is running', result.stdout))
        print(f"Running services: {running_services}")

        assert running_services >= 7, f"Expected at least 7 running services, found {running_services}"

    def test_dashboard_service_url(self, namespace, dashboard_pod, indexer_cred, request):
        """Check if Wazuh dashboard service returns HTTP 200"""
        user, password = indexer_cred
        dashboard_url = request.config.getoption("--dashboard-url", "localhost")
        if dashboard_url == "localhost":
            cmd = f'kubectl -n {namespace} exec -i {dashboard_pod} -- curl -XGET --silent https://{dashboard_url}/app/status -k -K - -I -s'
        else:
            cmd = f'curl -XGET --silent https://{dashboard_url}/app/status -k -K - -I -s'
        result = run(cmd, user, password)

        status_match = re.search(r'^HTTP.*?\s+(\d+)', result.stdout, re.MULTILINE)
        status = int(status_match.group(1)) if status_match else 0

        print(f"Wazuh dashboard status: {status}")
        assert status == 200, f"Expected status 200, got {status}"


if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])