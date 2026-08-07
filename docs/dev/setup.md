# Set up the Development Environment

## Pre-requisites

- kubectl (1.14 or higher)
  - kustomize (built into kubectl 1.14+)

**Local**:

- Running Kubernetes cluster. For instance, you can use [Minikube](https://minikube.sigs.k8s.io/docs/) or [Kind](https://kind.sigs.k8s.io/docs/user/quick-start/)

**Cloud**:

- Kubernetes cluster already deployed.
  - Kubernetes can run on a wide range of Cloud providers and bare-metal environments. However, this repository focuses on [AWS](https://aws.amazon.com/) and [Amazon EKS](https://docs.aws.amazon.com/eks)
  - You should be able to:
    - Create Persistent Volumes on top of AWS EBS when using a volumeClaimTemplates
    - Create a record set in AWS Route 53 from a Kubernetes LoadBalancer
  - Having at least two Kubernetes nodes in order to meet the *podAntiAffinity* policy
  - For Kubernetes version 1.23 or higher, the assignment of an IAM Role is necessary for the CSI driver to function correctly. Within the AWS documentation you can find the instructions for the assignment: [https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)
  - The installation of the CSI driver is necessary for new and old deployments, since it is a Kubernetes feature

**Testing**:

- Python 3
- Pytest (as used in [docs/dev/run-tests.md](run-tests.md)).

## Resource requirements

### EKS

To deploy Wazuh on Kubernetes on AWS EKS, the cluster should have at least the following resources available:

- 4 CPU units
- 5.5 Gi of memory

### Locally

To deploy Wazuh on Kubernetes locally, the cluster should have at least the following resources available:

- 2 CPU units
- 3 Gi of memory

## Set up the editor/debugger

Any editor and debugger can be used, feel free to use your favorite one
