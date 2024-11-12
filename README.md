# Marvel SIEM 
## Wazuh Fork - Optimized for AWS EKS Load Balancers

This repository is a fork of the original Wazuh project. Our goal with this fork is to optimize the number of load balancers used in the deployment of Wazuh clusters on AWS EKS.

## Use

To deploy this optimized Wazuh cluster on AWS EKS, follow the instructions below:

1. Clone this repository:
   ```sh
   git clone https://github.com/Marvel-Advisors-LLC/wazuh-kubernetes
   cd wazuh-kubernetes
   ```

2. Update your AWS credentials and the kubeconfig with the EKS cluster name.
   ```
   aws configure
   aws eks --region <region> update-kubeconfig --name <name>
   ```


3. Deploy Wazuh using the provided Kubernetes manifests:
   ```sh
   ./wazuh-eks/certs/indexer_stack/wazuh-dashboard/generate_certs.sh
   ./wazuh-eks/certs/indexer_stack/wazuh-indexer/generate_certs.sh
   kubectl apply -f kubernetes/
   ```
## License

This project is licensed under the GNU General Public License v2. See the [LICENSE](LICENSE) file for details.

## Acknowledgements

- [Wazuh](https://github.com/wazuh/) - The original project that this fork is based on.
- The open-source community for their continuous support and contributions.

## Contact

For questions, issues, or further information, please contact us at [facu2@marveladvisors.com].