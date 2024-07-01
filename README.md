# Marvel SIEM 
## Wazuh Fork - Optimized for AWS EKS Load Balancers

This repository is a fork of the original [Wazuh](https://github.com/wazuh/wazuh) project. Our goal with this fork is to optimize the number of load balancers used in the deployment of Wazuh clusters on AWS EKS.

## Introduction

Wazuh is a security monitoring platform that provides comprehensive security monitoring capabilities. This fork aims to enhance the deployment efficiency on AWS EKS by reducing the number of load balancers required, thereby optimizing costs and resource utilization.

## Features

- Optimized deployment configuration for AWS EKS
- Reduced number of load balancers
- Maintained all security monitoring capabilities of the original Wazuh project

## Installation

To deploy this optimized Wazuh cluster on AWS EKS, follow the instructions below:

1. Clone this repository:
   ```sh
   git clone https://github.com/Marvel-Advisors-LLC/wazuh-kubernetes
   
   cd wazuh-kubernetes
   ```

2. Update your AWS credentials and the kubeconfig with the EKS cluster name.

3. Deploy Wazuh using the provided Kubernetes manifests:
   ```sh
   ./wazuh-eks/certs/indexer_stack/wazuh-dashboard/generate_certs.sh
   ./wazuh-eks/certs/indexer_stack/wazuh-indexer/generate_certs.sh
   kubectl apply -f kubernetes/
   ```

## Usage

After deployment, you can access the Wazuh dashboard and monitor your environment as usual. The optimizations should be transparent and provide a more cost-effective deployment on AWS EKS.

## Contributing

We welcome contributions to further optimize and improve this fork. Please open issues or submit pull requests with your suggestions and improvements.

## License

This project is licensed under the GNU General Public License v2. See the [LICENSE](LICENSE) file for details.

## Acknowledgements

- [Wazuh](https://github.com/wazuh/wazuh) - The original project that this fork is based on.
- The open-source community for their continuous support and contributions.

## Contact

For questions, issues, or further information, please contact us at [facu2@marveladvisors.com].