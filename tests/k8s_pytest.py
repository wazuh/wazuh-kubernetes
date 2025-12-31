import subprocess
import pytest
import re

ADMIN_USER = "admin"
ADMIN_PASSWORD = "admin"

class TestWazuhKubernetes:
    """Test suite for Wazuh Kubernetes deployment"""

    @pytest.fixture(scope="class")
    def namespace(self):
        """Kubernetes namespace where Wazuh is deployed"""
        return "wazuh"

    @pytest.fixture(scope="class")
    def dashboard_pod(self, namespace):
        """Get Wazuh dashboard pod name"""
        cmd = f"kubectl -n {namespace} get pods -l app=wazuh-dashboard -o jsonpath='{{.items[0].metadata.name}}'"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return result.stdout.strip()

    def test_indexer_cluster_health(self, namespace):
        """Check if Wazuh indexer cluster health is green"""
        cmd = f'kubectl -n {namespace} exec -it wazuh-indexer-0 -- curl -XGET "https://localhost:9200/_cluster/health" -u {ADMIN_USER}:{ADMIN_PASSWORD} -k -s'
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)

        print(f"Cluster health status: {result.stdout}")
        assert "green" in result.stdout, "Cluster health is not green"

    def test_indexer_indices_health(self, namespace):
        """Check if all Wazuh indexer indices are green"""
        cmd = f'kubectl -n {namespace} exec -it wazuh-indexer-0 -- curl -XGET "https://localhost:9200/_cat/indices" -u {ADMIN_USER}:{ADMIN_PASSWORD} -k -s'
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)

        print(f"Indices status:\n{result.stdout}")

        lines = result.stdout.strip().split('\n')
        lines_total = len([line for line in lines if line.strip()])
        lines_green = len([line for line in lines if 'green' in line])

        assert lines_total == lines_green, f"Not all indices are green: {lines_green}/{lines_total}"

    def test_indexer_nodes_count(self, namespace, request):
        """Check if there are the expected number of Wazuh indexer nodes"""
        deployment_type = request.config.getoption("--deployment-type", default="local")
        expected_nodes = 3 if deployment_type == "eks" else 1

        cmd = f'kubectl -n {namespace} exec -it wazuh-indexer-0 -- curl -XGET "https://localhost:9200/_cat/nodes" -u {ADMIN_USER}:{ADMIN_PASSWORD} -k -s'
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)

        nodes_count = len(re.findall(r'indexer', result.stdout))
        print(f"Deployment type: {deployment_type}")
        print(f"Wazuh indexer nodes: {nodes_count}")

        assert nodes_count == expected_nodes, f"Expected {expected_nodes} indexer nodes for {deployment_type} deployment, found {nodes_count}"

    def test_wazuh_templates(self, namespace):
        """Check if Wazuh templates are present (more than 3)"""
        cmd = f'kubectl -n {namespace} exec -it wazuh-indexer-0 -- curl -XGET "https://localhost:9200/_cat/templates" -u {ADMIN_USER}:{ADMIN_PASSWORD} -k -s'
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)

        templates = re.findall(r'.*(?:wazuh|wazuh-agent|wazuh-statistics).*', result.stdout)
        qty_templates = len(templates)

        print("Wazuh templates:")
        for template in templates:
            print(template)

        assert qty_templates > 3, f"Expected more than 3 templates, found {qty_templates}"

    def test_manager_services_running(self, namespace):
        """Check if Wazuh manager has at least 10 services running"""
        cmd = f'kubectl -n {namespace} exec -it wazuh-manager-master-0 -- /var/ossec/bin/wazuh-control status'
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)

        print("Wazuh Manager services status:")
        print(result.stdout)

        running_services = len(re.findall(r'is running', result.stdout))
        print(f"Running services: {running_services}")

        assert running_services >= 10, f"Expected at least 10 running services, found {running_services}"

    def test_dashboard_service_url(self, namespace, dashboard_pod, request):
        """Check if Wazuh dashboard service returns HTTP 200"""
        dashboard_url = request.config.getoption("--dashboard-url", "localhost")
        if dashboard_url == "localhost":
            cmd = f'kubectl -n {namespace} exec -it {dashboard_pod} -- curl -XGET --silent https://{dashboard_url}/app/status -k -u {ADMIN_USER}:{ADMIN_PASSWORD} -I -s'
        else:
            cmd = f'curl -XGET --silent https://{dashboard_url}/app/status -k -u {ADMIN_USER}:{ADMIN_PASSWORD} -I -s'
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)

        status_match = re.search(r'^HTTP.*?\s+(\d+)', result.stdout, re.MULTILINE)
        status = int(status_match.group(1)) if status_match else 0

        print(f"Wazuh dashboard status: {status}")
        assert status == 200, f"Expected status 200, got {status}"


if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])