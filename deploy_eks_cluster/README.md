# EKS Cluster Deployment

Deploy an EKS Cluster for Wazuh.

## YAML files

* `cluster.yml` should be used if the creation of the VPC and subnets is required.
* `cluster_existing_vpc.yml` should be used if the VPC and subnets already exist.


## Documentation

The goal of this section is to simplify the creation of an EKS cluster.
The execution of this guide will create the following resources:
- VPC
- Subnets
- NodeGroups
- SecurityGroups

## Pre-requisites

To perform the following steps, you will need to:
- Install and configure `AWS CLI`: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- Configure `AWS CLI`: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-quickstart.html
- Install `eksctl`: https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html
- Install `kubectl`: https://kubernetes.io/docs/tasks/tools/#kubectl

## Deployment

To deploy an EKS cluster, you need to:

1. Define whether you will use an existing VPN.
  a. If not: use `cluster.yml`
  b. If yes: use `cluster_existing_vpc.yml`
2. Replace the values marked with `<>`.
    **Common Values**
      - `metadata name`: the EKS cluster name.
      - `metadata region`: the region where the EKS cluster will be deployed.
      - `nodeGroups publicKeyName`: the keyPair for the EC2 instances.

    **Existing VPC Values**
      - `vpc id`: the existing VPC ID.
      - `vpc cidr`: the existing VPC CIDR.
      - `vpc private private-subnet#-az`: the existing private subnet AZ.
      - `vpc private private-subnet#-az id`: the existing private subnet ID.
      - `vpc private private-subnet#-az cidr`: the existing private subnet CIDR.
      - `vpc public public-subnet#-az`: the existing public subnet AZ.
      - `vpc public public-subnet#-az id`: the existing public subnet ID.
      - `vpc public public-subnet#-az cidr`: the existing public subnet CIDR.
3. Run the following command:
   a. Not existing VPC
    ```BASH
    eksctl create cluster -f cluster.yml
    ```
   b. Existing VPC
    ```BASH
    eksctl create cluster -f cluster_existing_vpc.yml
    ```
4. Wait until the EKS cluster creation finishes.
5. Update `kubeconfig` (replace the values marked with `<>`):
    ```BASH
    aws eks update-kubeconfig --name <eks-cluster-name> --region <eks-cluster-region>
    ```


## License and copyright

WAZUH
Copyright (C) 2022, Wazuh Inc.  (License GPLv2)

## References

* [Wazuh website](http://wazuh.com)
