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
