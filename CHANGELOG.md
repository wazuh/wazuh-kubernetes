## [v5.0.1]

### Added

| Issue | Comment |
| - | - |

### Changed

| Issue | Comment |
| - | - |
| [#1611](https://github.com/wazuh/wazuh-kubernetes/pull/1611) | Remove unused deployability/deps install in k8s integration tests |

### Removed

| Issue | Comment |
| - | - |

### Fixed

| Issue | Comment |
| - | - |
| [#1613](https://github.com/wazuh/wazuh-kubernetes/pull/1613) | Report skipped bumps in the repository bumper workflow |
| [#1763](https://github.com/wazuh/wazuh-kubernetes/issues/1763) | Fix docs drift: explain that the EKS `wazuh-storage` StorageClass uses the in-tree `kubernetes.io/aws-ebs` name served by the EBS CSI driver, mark `DISCOVERY_SERVICE` and `KUBERNETES_NAMESPACE` as not required, and stop listing the Wazuh API under the `wazuh-master` domain |
| [#1734](https://github.com/wazuh/wazuh-kubernetes/issues/1734) | Write the rotated `wazuh-manager` password into the manager keystores from a one-off pod with the managers scaled to zero, instead of into the running managers |
| [#1707](https://github.com/wazuh/wazuh-kubernetes/issues/1707) | Stop certificates-conf.sh when wazuh-certs-tool.sh fails and give config.yml back to the invoking user |
| [#1687](https://github.com/wazuh/wazuh-kubernetes/issues/1687) | Make the Wazuh dashboard readiness probe fail on a non-2xx response, and point the three dashboard probes to `/app/login`, so the pod is not reported Ready while the dashboard answers `503`. |
| [#1685](https://github.com/wazuh/wazuh-kubernetes/issues/1685) | Add `localhost` (local) and the load balancer FQDN (EKS) to the dashboard certificate SAN in the sample `config.yml`, document how to verify it, and that a domain of your own also goes in the dashboard `HostSNI` rule. |
| [#1595](https://github.com/wazuh/wazuh-kubernetes/pull/1595) | Fix changelog check to accept Prior versions entries |
| [#1563](https://github.com/wazuh/wazuh-kubernetes/pull/1563) | Fix bumper workflow failure when bump produces no changes |
| [#1526](https://github.com/wazuh/wazuh-kubernetes/issues/1526) | Bumper script issue when the tag is set to false |
| [#1467](https://github.com/wazuh/wazuh-kubernetes/issues/1467) | Errors on bumper execution |
| [#1449](https://github.com/wazuh/wazuh-kubernetes/issues/1449) | Change API password to default |
| [#1340](https://github.com/wazuh/wazuh-kubernetes/issues/1340) | Fix test for deployment |

## Prior versions

- [v5.0.0](https://github.com/wazuh/wazuh-kubernetes/blob/v5.0.0/CHANGELOG.md)
