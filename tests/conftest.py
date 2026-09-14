"""Pytest configuration for Wazuh Kubernetes tests"""

def pytest_addoption(parser):
    """Add custom command-line options"""
    parser.addoption(
        "--deployment-type",
        action="store",
        default="local",
        help="Deployment type: local or eks"
    )
    parser.addoption(
        "--dashboard-url",
        action="store",
        default="localhost",
        help="Dashboard URL for testing"
    )
    parser.addoption(
        "--indexer-user",
        action="store",
        default="wazuh-admin",
        help="Wazuh indexer account the tests authenticate with"
    )
    parser.addoption(
        "--indexer-password",
        action="store",
        default="wazuh-admin",
        help="Password of the Wazuh indexer account. Pass the new value after "
             "rotating credentials (see docs/ref/credentials.md)"
    )
