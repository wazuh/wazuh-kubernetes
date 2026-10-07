# Wazuh Upgrade

When upgrading our version of Wazuh installed in Kubernetes we must follow the following steps.

## What survives an upgrade

Our Kubernetes deployment uses the Wazuh images from Docker. These are the directories of the manager
that the image keeps across containers, and that this deployment puts on the manager claim:

```
PERMANENT_DATA[((i++))]="/var/wazuh-manager/api/configuration"
PERMANENT_DATA[((i++))]="/var/wazuh-manager/etc"
PERMANENT_DATA[((i++))]="/var/wazuh-manager/logs"
PERMANENT_DATA[((i++))]="/var/wazuh-manager/queue"
PERMANENT_DATA[((i++))]="/var/wazuh-manager/var/multigroups"
```

`/var/wazuh-manager/data` is on a volume here too, but it is not on that list: the image does not
restore it, so the init container of each manager StatefulSet seeds it from the image the first
time the claim is used. The subtrees the image owns (`data/tzdb`, `data/store/schema`,
`data/store/enrichment`) are refreshed from the new image on every start, which is what makes an
upgrade over an existing claim pick up the new content.

A change made in any of those directories, for example a rule added to
`/var/wazuh-manager/etc/rules/local_rules.xml` in `wazuh-manager-master-0`, is written to the claim
(`subPath: wazuh/var/wazuh-manager/etc`). When the pod is recreated with a new image, it finds the
file on the claim again.

The credentials survive the upgrade in the same way, on the persistent volumes:

- the indexer security index, with the `admin`, `kibanaserver` and `wazuh-manager` accounts;
- the Wazuh API user database, `rbac.db`, on the master;
- the manager keystore, `queue/keystore`, on every manager pod;
- the dashboard keystore, on the `wazuh-dashboard-config` claim.

The indexer also takes its passwords from its Secret again every time one of its pods is recreated,
so `wazuh/config/credentials/*.env` has to hold the current passwords, including any rotated with
`password-tool.sh`.

## Upgrading a 5.0 deployment

1. Check out the new release, and carry over from the directory the deployment was created from:
   `wazuh/config/` (certificates and `credentials/*.env`), your edits to `wazuh/secrets/*.yaml`,
   `wazuh/base/ingressRoute-tcp-dashboard.yaml`, `wazuh/base/middleware.yaml`, and any change to `envs/`. Do not run
   `credentials-conf.sh` again: the deployment keeps the passwords it was first started with, and
   new values would not match them.
2. If you pin the images yourself, change every `wazuh/wazuh-*` image, the init containers
   included: `install-credentials` (every workload), `init-wazuh-etc` (managers) and
   `init-dashboard-config` (dashboard). All the nodes of the Wazuh cluster have to run the same
   version.
3. Apply the Traefik runtime. From 5.0.0, also delete the `traefik` ClusterRoleBinding, which
   `kubectl apply` does not remove and which gives Traefik read access to the Secrets of every
   namespace. Traefik stops routing until the overlay of the next step creates its RoleBinding in the
   `wazuh` namespace.

   ```bash
   kubectl delete clusterrolebinding traefik --ignore-not-found
   kubectl apply -k traefik/runtime/
   ```

4. Apply the overlay. Always the overlay, never a single manifest: the Secrets the workloads mount
   carry a name kustomize generates, and a manifest applied on its own references a Secret that does
   not exist.

   ```bash
   kubectl apply -k envs/eks/   # or envs/local-env/
   kubectl -n wazuh rollout status statefulset/wazuh-indexer
   kubectl -n wazuh rollout status statefulset/wazuh-manager-master
   kubectl -n wazuh rollout status statefulset/wazuh-manager-worker
   kubectl -n wazuh rollout status deployment/wazuh-dashboard
   ```

5. Check that every account still authenticates with its password:

   ```bash
   cd wazuh && ../tools/tests/check-default-credentials.sh && cd ..
   ```

## From 4.x

The 4.x manifests differ in ways this procedure does not cover:

- The credentials came from the `indexer-cred`, `dashboard-cred` and `wazuh-api-cred` Secrets and from
  environment variables (`INDEXER_PASSWORD`, `API_PASSWORD`, `DASHBOARD_PASSWORD` and their
  `*_USERNAME` pairs). The 5.0 workloads read none of them, and `kubectl apply -k` does not delete
  those Secrets.
- The manager claims use the `wazuh/var/ossec/*` subPaths, where 5.0 uses `wazuh/var/wazuh-manager/*`.
  A 5.0 manager on a 4.x claim does not see the 4.x state.
- The 4.x indexer StatefulSet has no `podManagementPolicy: Parallel`, and the field cannot be
  changed on an existing StatefulSet.

Deploy 5.0 as a new deployment, following [Installation](getting-started/installation.md).
