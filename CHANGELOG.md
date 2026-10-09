## [v5.0.0]

### Added

| Issue | Comment |
| - | - |
| [#1681](https://github.com/wazuh/wazuh-kubernetes/issues/1681) | Add a worked agent enrollment example to the EKS and local deployment guides, and pass `--agent-san localhost` in the certificate command of the local guide. |
| [#1647](https://github.com/wazuh/wazuh-kubernetes/issues/1647) | Add the agent listener (`remoted`) certificate to the `manager-certs` secret and to both manager statefulsets. |
| [#1638](https://github.com/wazuh/wazuh-kubernetes/issues/1638) | Document how to change the default Wazuh indexer and Wazuh API passwords, the manager cluster key and the agent enrollment password, and add a check for default credentials. |
| [#1578](https://github.com/wazuh/wazuh-kubernetes/issues/1578) | Readiness and liveness probes on Wazuh deployment. |
| [#1539](https://github.com/wazuh/wazuh-kubernetes/pull/1539) | Added bump-issue-link support for Revert Stage Bump. |
| [#1534](https://github.com/wazuh/wazuh-kubernetes/pull/1534) | Add integration test module docs |
| [#1310](https://github.com/wazuh/wazuh-kubernetes/issues/1310) | Implement the wazuh-kubernetes integration testing module |
| [#1460](https://github.com/wazuh/wazuh-kubernetes/issues/1460) | Review and Implement AWS Tagging Policy in wazuh-kubernetes |
| [#1392](https://github.com/wazuh/wazuh-kubernetes/issues/1392) | Support Revert bump functionality in wazuh-kubernetes |
| [#1365](https://github.com/wazuh/wazuh-kubernetes/issues/1365) | Add `--set-as-main` flag support to repository bumper — `wazuh-kubernetes` |
| [#1338](https://github.com/wazuh/wazuh-kubernetes/issues/1338) | Wazuh Manager/agent Separation - Kubernetes - Breaking changes summary |
| [#1319](https://github.com/wazuh/wazuh-kubernetes/issues/1319) | Missing documentation in the wazuh-kubernetes repository |
| [#1309](https://github.com/wazuh/wazuh-kubernetes/issues/1309) | Add version and revision on wazuh-certs-tool.sh and config.yml files. |
| [#957](https://github.com/wazuh/wazuh-kubernetes/issues/957) | Development - Kubernetes - Analize Network Policies |
| [#1262](https://github.com/wazuh/wazuh-kubernetes/issues/1262) | Missing branch/tag checkout step in Kubernetes deployment documentation |
| [#954](https://github.com/wazuh/wazuh-kubernetes/issues/954) | Development - Kubernetes - Adapt the PR tests |

### Changed

| Issue | Comment |
| - | - |
| [#1703](https://github.com/wazuh/wazuh-kubernetes/issues/1703) | Rename the `wazuh-wui` Server API user to `wazuh-internal-client` in the credentials check and the documentation. The `WAZUH_MANAGER_WUI_PASSWORD` key keeps its name. |
| [#1714](https://github.com/wazuh/wazuh-kubernetes/issues/1714) | Add the Server API certificate (`apid`) issued by `wazuh-certs-tool.sh` to the `manager-certs` secret and the master statefulset, and add `--api-san` to `certificates-conf.sh`. |
| [#1710](https://github.com/wazuh/wazuh-kubernetes/issues/1710) | Hardening traefik deployment |
| [#1708](https://github.com/wazuh/wazuh-kubernetes/issues/1708) | Delete secrets and add random creation for authd.pass and cluster_key |
| [#1705](https://github.com/wazuh/wazuh-kubernetes/issues/1705) | Start the Kubernetes integration tests from PR labels |
| [#1660](https://github.com/wazuh/wazuh-kubernetes/issues/1660) | Adapt Kubernetes manifests to install-time credential generation |
| [#1673](https://github.com/wazuh/wazuh-kubernetes/issues/1673) | Adapt the deployment to the HTTPS communication changes |
| [#1636](https://github.com/wazuh/wazuh-kubernetes/issues/1636) | Agent enrollment fails on EKS because Traefik never expose port 1517 |
| [#1612](https://github.com/wazuh/wazuh-kubernetes/pull/1612) | Adapt certificate deployment to unified manager certificate layout |
| [#1608](https://github.com/wazuh/wazuh-kubernetes/issues/1608) | Change Codebuild runners to Github runners. |
| [#1567](https://github.com/wazuh/wazuh-kubernetes/issues/1567) | Update deployment for Wazuh Indexer 5.0.0 RBAC. |
| [#1569](https://github.com/wazuh/wazuh-kubernetes/pull/1569) | Add new WF for changelog check |
| [#1522](https://github.com/wazuh/wazuh-kubernetes/issues/1522) | Migrate the gha runner to codebuild |
| [#1504](https://github.com/wazuh/wazuh-kubernetes/pull/1504) | PR Revamp modifications 5.x |
| [#1459](https://github.com/wazuh/wazuh-kubernetes/issues/1459) | Forbid run local deployment test in draft PRs |
| [#1432](https://github.com/wazuh/wazuh-kubernetes/issues/1432) | Unification of user UID and GID |
| [#1370](https://github.com/wazuh/wazuh-kubernetes/issues/1370) | Kubernetes - Ensure correct Wazuh manager certificates ownership |
| [#1363](https://github.com/wazuh/wazuh-kubernetes/issues/1363) | Update artifact URLs file extension from .yml to .yaml |
| [#1358](https://github.com/wazuh/wazuh-kubernetes/issues/1358) | Updated wazuh-kubernetes documentation config and tooling versions to meet new standards. |
| [#1341](https://github.com/wazuh/wazuh-kubernetes/issues/1341) | Errors in the startup of Wazuh manager |
| [#1326](https://github.com/wazuh/wazuh-kubernetes/issues/1326) | Development - Separate Agent/Manager - Kubernetes - Adapt deployment |
| [#1305](https://github.com/wazuh/wazuh-kubernetes/issues/1305) | Update Wazuh Kubernetes local deployment documentation |
| [#1295](https://github.com/wazuh/wazuh-kubernetes/issues/1295) | Replace the Nginx ingress controller with an alternative that has long-term support. |
| [#958](https://github.com/wazuh/wazuh-kubernetes/issues/958) | Development - Kubernetes - Update documentation |
| [#949](https://github.com/wazuh/wazuh-kubernetes/issues/949) | Development - Kubernetes - Modify the networking of the Wazuh deployment |
| [#948](https://github.com/wazuh/wazuh-kubernetes/issues/948) | Development - Kubernetes - Modify deployment configuration in Kubernetes |
| [#1137](https://github.com/wazuh/wazuh-kubernetes/issues/1137) | Remove Wazuh Manager deprecated daemons and CLI tools |
| [#1107](https://github.com/wazuh/wazuh-kubernetes/issues/1107) | DevOps - Kubernetes - OpenSearch 3.0 deprecated settings |

### Removed

| Issue | Comment |
| - | - |

### Fixed

| Issue | Comment |
| - | - |
| [#1687](https://github.com/wazuh/wazuh-kubernetes/issues/1687) | Make the Wazuh dashboard readiness probe fail on a non-2xx response, and point the three dashboard probes to `/app/login`, so the pod is not reported Ready while the dashboard answers `503`. |
| [#1685](https://github.com/wazuh/wazuh-kubernetes/issues/1685) | Add `localhost` (local) and the load balancer FQDN (EKS) to the dashboard certificate SAN in the sample `config.yml`, document how to verify it, and that a domain of your own also goes in the dashboard `HostSNI` rule. |
| [#1613](https://github.com/wazuh/wazuh-kubernetes/pull/1613) | Report skipped bumps in the repository bumper workflow |
| [#1595](https://github.com/wazuh/wazuh-kubernetes/pull/1595) | Fix changelog check to accept Prior versions entries |
| [#1563](https://github.com/wazuh/wazuh-kubernetes/pull/1563) | Fix bumper workflow failure when bump produces no changes |
| [#1526](https://github.com/wazuh/wazuh-kubernetes/issues/1526) | Bumper script issue when the tag is set to false |
| [#1467](https://github.com/wazuh/wazuh-kubernetes/issues/1467) | Errors on bumper execution |
| [#1449](https://github.com/wazuh/wazuh-kubernetes/issues/1449) | Change API password to default |
| [#1340](https://github.com/wazuh/wazuh-kubernetes/issues/1340) | Fix test for deployment |

## Prior version

- []()