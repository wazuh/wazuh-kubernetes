# Getting Started

This guide provides a quick introduction to deploying Wazuh on Kubernetes using this repository. It covers the deployment options available and outlines the basic steps required to get Wazuh running in your Kubernetes cluster.

## Deployment Options

Two pre-configured deployment environments are available:

### Local Environment

Designed for development, testing, and evaluation purposes using local Kubernetes clusters such as Minikube or Kind. This environment uses:

- Single-node deployment with reduced resource requirements
- Local storage provisioner for persistent volumes
- Simplified networking configuration

For detailed instructions, see [Usage: Local Deployment](usage/deployment/local.md).

### Amazon EKS

Optimized for deployments on Amazon Elastic Kubernetes Service (EKS). This environment includes:

- Multi-node cluster with high availability
- Amazon EBS-backed persistent storage
- Load balancer integration for service exposure
- Separate resource configurations for master and worker nodes

For detailed instructions, see [Usage: AWS EKS Deployment](usage/deployment/eks.md).

## Next Steps

- Review the [Requirements](requirements.md) to ensure your cluster is properly configured
- Follow the [Usage](usage/usage.md) guide for step-by-step deployment/cleanup/upgrade instructions
