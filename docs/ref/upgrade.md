# Wazuh Upgrade

When upgrading our version of Wazuh installed in Kubernetes we must follow the following steps.

## What survives an upgrade

Our Kubernetes deployment uses the Wazuh images from Docker. These are the directories of the manager
that the image keeps across containers, and that this deployment puts on the manager claim:

```
PERMANENT_DATA[((i++))]="/var/wazuh-manager/api/configuration"
PERMANENT_DATA[((i++))]="/etc/wazuh-manager"
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
`/etc/wazuh-manager/rules/local_rules.xml` in `wazuh-manager-master-0`, is written to the claim
(`subPath: wazuh/etc/wazuh-manager`). When the pod is recreated with a new image, it finds the
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

A deployment created with the 5.0.0 RC 1 images cannot be upgraded in place. From RC 2:
- the manager keeps its configuration in `/etc/wazuh-manager`, on a new subPath of its claim;
- the components refuse the ownership and modes RC 1 left on the claims.

Start RC 2 on new claims: delete the namespace, or its PersistentVolumeClaims, before applying the
new overlay.

1. Check out the new release, and carry over from the directory the deployment was created from:
   `wazuh/config/` (certificates, `credentials/*.env` and `credentials/cluster.key`),
   `wazuh/base/ingressRoute-tcp-dashboard.yaml`, `wazuh/base/middleware.yaml`, and any change to `envs/`. Do not run
   `credentials-conf.sh` again: the deployment keeps the passwords it was first started with, and
   new values would not match them. The exception is a deployment created before
   `credentials-conf.sh` wrote `cluster.key`: run it once to add that file only, as described in
   [The cluster key](credentials.md#the-cluster-key).
2. If you pin the images yourself, change every `wazuh/wazuh-*` image, the init containers
   included: `install-credentials` (every workload), `install-certs` (indexer and dashboard),
   `init-wazuh-etc` (managers) and `init-dashboard-config` (dashboard). All the nodes of the Wazuh cluster have to run the same
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

A 4.x deployment cannot be upgraded in place. The 5.0 manager uses other paths (`/var/wazuh-manager` and `/etc/wazuh-manager` instead of `/var/ossec`), a new configuration format and a new agent protocol, and the 4.x manifests differ in ways `kubectl apply` cannot reconcile:

- The credentials came from the `indexer-cred`, `dashboard-cred` and `wazuh-api-cred` Secrets and from environment variables. The 5.0 workloads read none of them.
- The manager claims use the `wazuh/var/ossec/*` subPaths, where 5.0 uses `wazuh/var/wazuh-manager/*`. A 5.0 manager on a 4.x claim does not see the 4.x state.
- The 4.x indexer StatefulSet has no `podManagementPolicy: Parallel`, and the field cannot be changed on an existing StatefulSet.

Do not apply the 5.0 overlay in the namespace of the 4.x deployment: both use `wazuh` and the same workload names. `kubectl apply -k` replaces the managers and the dashboard with 5.0, which do not start on the 4.x claims and cannot reach the 4.x indexer, fails on the indexer StatefulSet, and turns the `dashboard` Service into a `ClusterIP` one. The 4.x deployment stops working. Deploy 5.0 in another namespace, `wazuh-5` in the steps below, or in another cluster. To keep `wazuh`, remove 4.x first, as [Reusing the `wazuh` namespace](#reusing-the-wazuh-namespace) describes.

Carry the agents' identity across with the manager's migration tool, `wazuh-migrate-identity.py`. It keeps the agent ids, names and keys, the group membership and the group folders and, optionally, the API users and the enrollment password, so the 4.x agents reconnect without enrolling again. The Wazuh manager guide [Migrating a Wazuh manager from 4.x to 5.0](https://github.com/wazuh/wazuh/blob/5.0.0/docs/guide/migration/manager-4x-to-5x.md) covers everything else: the configuration, the rules and decoders, upgrading the agents, retiring the legacy channel, and the historical data. [Configuration and content](#configuration-and-content) says where its input is in a 4.x Kubernetes deployment and where 5.0 takes it.

The 5.0 manager image has no `python3` on its `PATH` and no `tar`: the steps run the tool with the Python the manager bundles, and copy files with `kubectl exec -i`, because `kubectl cp` needs `tar` in the container.

1. **Stop the 4.x managers**, keeping their claims:
   ```bash
   kubectl -n wazuh scale statefulset wazuh-manager-master wazuh-manager-worker --replicas=0
   kubectl -n wazuh wait --for=delete pod -l app=wazuh-manager --timeout=300s
   ```
   The `wazuh` and `wazuh-workers` load balancers keep their addresses, with no endpoints behind them. The 4.x agents log `(1137): Lost connection with manager`, then `Unable to connect to any server` and `(1208): Unable to connect to enrollment service`, and keep retrying: an agent that cannot connect tries to enroll again, so it must not reach a manager before the import of step 4.

2. **Export the identity** from the master claim, with a one-off pod of your 4.x manager image. Use the tag of your 4.x deployment:
   ```bash
   curl -fsSLo wazuh-migrate-identity.py https://raw.githubusercontent.com/wazuh/wazuh/5.0.0/tools/migration/wazuh-migrate-identity.py
   kubectl -n wazuh create configmap wazuh-migrate-identity --from-file=wazuh-migrate-identity.py
   cat > wazuh-4x-export.yaml <<'EOF'
   apiVersion: v1
   kind: Pod
   metadata:
     name: wazuh-4x-export
   spec:
     restartPolicy: Never
     containers:
       - name: export
         image: wazuh/wazuh-manager:4.14.10
         command: ["sleep", "3600"]
         volumeMounts:
           - {name: master, mountPath: /var/ossec/etc, subPath: wazuh/var/ossec/etc, readOnly: true}
           - {name: master, mountPath: /var/ossec/queue, subPath: wazuh/var/ossec/queue, readOnly: true}
           - {name: master, mountPath: /var/ossec/api/configuration, subPath: wazuh/var/ossec/api/configuration, readOnly: true}
           - {name: tool, mountPath: /opt/migration}
     volumes:
       - name: master
         persistentVolumeClaim:
           claimName: wazuh-manager-master-wazuh-manager-master-0
       - name: tool
         configMap:
           name: wazuh-migrate-identity
   EOF
   kubectl -n wazuh apply -f wazuh-4x-export.yaml
   kubectl -n wazuh wait --for=condition=Ready pod/wazuh-4x-export --timeout=300s
   kubectl -n wazuh exec wazuh-4x-export -- /var/ossec/framework/python/bin/python3 \
     /opt/migration/wazuh-migrate-identity.py export /tmp/identity --with-rbac
   kubectl -n wazuh exec wazuh-4x-export -- tar -C /tmp -cf - identity > wazuh-4x-identity.tar
   kubectl -n wazuh delete pod wazuh-4x-export
   kubectl -n wazuh delete configmap wazuh-migrate-identity
   ```
   `--with-rbac` carries the API users, roles and policies, and `--with-password` the enrollment password, which only 4.x agents that still have to enroll need. The bundle holds agent keys and password hashes: handle it like a credential.

3. **Deploy 5.0 in the `wazuh-5` namespace.** Follow [Installation](getting-started/installation.md) in a checkout of 5.0, with `-n wazuh-5` wherever it says `-n wazuh`, and these changes:
   - Before applying the Traefik runtime, make Traefik watch `wazuh-5`:
     ```bash
     sed -i 's/kubernetescrd.namespaces=wazuh"/kubernetescrd.namespaces=wazuh-5"/' traefik/runtime/traefik-deployment.yaml
     ```
   - In `config.yml`, write `wazuh-5` instead of `wazuh` in every `*.wazuh.svc.cluster.local` name. The indexer nodes verify each other against `wazuh-indexer-<n>.wazuh-indexer.<namespace>.svc.cluster.local`.
   - Apply the overlay through another one that sets the namespace:
     ```bash
     mkdir -p envs/wazuh-5
     printf 'resources:\n  - ../eks\nnamespace: wazuh-5\n' > envs/wazuh-5/kustomization.yml
     kubectl apply -k envs/wazuh-5/
     ```
   - Run the credentials check with `--namespace wazuh-5`.

   Do not change the address the 4.x agents use yet: until step 5 they keep trying the 4.x load balancers, which have no endpoints, so no agent reaches the 5.0 manager before its registry is restored.

4. **Import the identity** into the 5.0 master, through its API on loopback. The master pod has the `wazuh` password in `/run/secrets/wazuh-credentials`:
   ```bash
   PY=/var/wazuh-manager/framework/python/bin/python3
   kubectl -n wazuh-5 exec -i wazuh-manager-master-0 -c wazuh-manager -- \
     sh -c 'cat > /tmp/wazuh-migrate-identity.py' < wazuh-migrate-identity.py
   kubectl -n wazuh-5 exec -i wazuh-manager-master-0 -c wazuh-manager -- \
     $PY -c 'import sys, tarfile; tarfile.open(fileobj=sys.stdin.buffer, mode="r|").extractall("/tmp", filter="data")' \
     < wazuh-4x-identity.tar
   kubectl -n wazuh-5 exec wazuh-manager-master-0 -c wazuh-manager -- sh -c \
     "sed -n 's/^WAZUH_MANAGER_API_PASSWORD=//p' /run/secrets/wazuh-credentials | \
      $PY /tmp/wazuh-migrate-identity.py import /tmp/identity --with-rbac --api-password-file -"
   ```
   Run it with `--dry-run` first. The import ends with `Inserted N of N agent(s)`.

5. **Open the manager to the agents.** With `--with-rbac`, the API loads the imported users on its next start, and from then on `wazuh` and `wazuh-internal-client` have their 4.x passwords, so the dashboard cannot log in. Restart the master, then set both back:
   ```bash
   kubectl -n wazuh-5 delete pod wazuh-manager-master-0
   kubectl -n wazuh-5 wait --for=condition=Ready pod/wazuh-manager-master-0 --timeout=600s
   kubectl -n wazuh-5 exec wazuh-manager-master-0 -c wazuh-manager -- sh -c \
     "sed -n 's/^WAZUH_MANAGER_API_PASSWORD=//p' /run/secrets/wazuh-credentials | /var/wazuh-manager/bin/rbac_control change-password -u wazuh -p -"
   kubectl -n wazuh-5 exec wazuh-manager-master-0 -c wazuh-manager -- sh -c \
     "sed -n 's/^WAZUH_MANAGER_WUI_PASSWORD=//p' /run/secrets/wazuh-credentials | /var/wazuh-manager/bin/rbac_control change-password -u wazuh-internal-client -p -"
   ```
   Your own API users keep their 4.x passwords. Then point the 4.x agents at the Traefik load balancer, which takes `1514` and `1515`: change the DNS record they resolve, or the `<address>` in their configuration.
   ```bash
   kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
   ```
   The agents connect with their existing keys, without enrolling again.

6. **Check the result**, then delete the bundle. The restart of step 5 emptied `/tmp`, so copy the tool and the bundle again as in step 4:
   ```bash
   PY=/var/wazuh-manager/framework/python/bin/python3
   kubectl -n wazuh-5 exec -i wazuh-manager-master-0 -c wazuh-manager -- \
     sh -c 'cat > /tmp/wazuh-migrate-identity.py' < wazuh-migrate-identity.py
   kubectl -n wazuh-5 exec -i wazuh-manager-master-0 -c wazuh-manager -- \
     $PY -c 'import sys, tarfile; tarfile.open(fileobj=sys.stdin.buffer, mode="r|").extractall("/tmp", filter="data")' \
     < wazuh-4x-identity.tar
   kubectl -n wazuh-5 exec wazuh-manager-master-0 -c wazuh-manager -- sh -c \
     "sed -n 's/^WAZUH_MANAGER_API_PASSWORD=//p' /run/secrets/wazuh-credentials | \
      $PY /tmp/wazuh-migrate-identity.py check /tmp/identity --api-password-file -"
   kubectl -n wazuh-5 exec wazuh-manager-master-0 -c wazuh-manager -- grep 'agent key' /var/wazuh-manager/logs/wazuh-manager.log
   kubectl -n wazuh-5 exec wazuh-manager-master-0 -c wazuh-manager -- rm -rf /tmp/identity /tmp/wazuh-migrate-identity.py
   rm -f wazuh-4x-identity.tar
   ```
   `check` reports `The target matches the bundle.` The 4.x agents show as `active`, with their ids, names and groups. The registration date is the date of the import. Keep the 4.x namespace and its claims until the migration is complete. To keep the 4.x alerts, copy them as [Historical data](#historical-data) describes before removing it.

### Historical data

The 5.0 indexer does not read the 4.x indices. Neither indexer image has the `repository-s3` plugin, and an `fs` snapshot repository needs a filesystem shared by every indexer node, so copy the 4.x alerts with reindex from remote while the 4.x indexer still runs. The 5.0 indexer pulls them over `9200`, so it needs the 4.x root CA, three static settings and a NetworkPolicy that lets it reach the 4.x indexer.

1. **Open the 5.0 indexer to the 4.x one** with a second overlay on top of `envs/wazuh-5/`. Take the 4.x root CA from the `indexer-certs` Secret of the 4.x namespace, or from `wazuh/certs/indexer_cluster/root-ca.pem` in the 4.x checkout:
   ```bash
   mkdir -p envs/wazuh-5-reindex && cd envs/wazuh-5-reindex
   kubectl -n wazuh get secret -o name | grep indexer-certs   # indexer-certs-<hash>
   kubectl -n wazuh get secret indexer-certs-<hash> -o jsonpath='{.data.root-ca\.pem}' | base64 -d > root-ca-4x.pem
   cat > kustomization.yml <<'EOT'
   resources:
     - ../wazuh-5
     - indexer-egress-4x.yaml
   namespace: wazuh-5
   secretGenerator:
     - name: indexer-4x-ca
       files:
         - root-ca.pem=root-ca-4x.pem
   patches:
     - path: indexer-reindex.yaml
   EOT
   cat > indexer-reindex.yaml <<'EOT'
   apiVersion: apps/v1
   kind: StatefulSet
   metadata:
     name: wazuh-indexer
     namespace: wazuh-5
   spec:
     template:
       spec:
         volumes:
           - name: indexer-4x-ca
             secret:
               secretName: indexer-4x-ca
               defaultMode: 0444
         containers:
           - name: wazuh-indexer
             env:
               - name: reindex.remote.allowlist
                 value: "indexer.wazuh.svc.cluster.local:9200"
               - name: reindex.ssl.certificate_authorities
                 value: "/usr/share/wazuh-indexer/config/certs-4x/root-ca.pem"
               - name: reindex.ssl.verification_mode
                 value: "certificate"
             volumeMounts:
               - name: indexer-4x-ca
                 mountPath: /usr/share/wazuh-indexer/config/certs-4x
                 readOnly: true
   EOT
   cat > indexer-egress-4x.yaml <<'EOT'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: indexer-egress-4x
   spec:
     podSelector:
       matchLabels:
         app: wazuh-indexer
     policyTypes:
       - Egress
     egress:
       - to:
           - namespaceSelector:
               matchLabels:
                 kubernetes.io/metadata.name: wazuh
             podSelector:
               matchLabels:
                 app: wazuh-indexer
         ports:
           - protocol: TCP
             port: 9200
   EOT
   cd ../..
   kubectl apply -k envs/wazuh-5-reindex/
   kubectl -n wazuh-5 rollout status statefulset/wazuh-indexer --timeout=900s
   ```
   The 4.x node certificate has no subject alternative name, so `verification_mode: certificate` verifies the chain and not the host name.

2. **Create the template of the copied indices** from the 4.x `wazuh` template, so they keep the 4.x field types:
   ```bash
   kubectl -n wazuh exec wazuh-indexer-0 -c wazuh-indexer -- sh -c 'cd /usr/share/wazuh-indexer/config/certs; \
     curl -sk --cert admin.pem --key admin-key.pem https://localhost:9200/_template/wazuh' > wazuh-4x-template.json
   python3 -c 'import json; t=json.load(open("wazuh-4x-template.json"))["wazuh"]; t["index_patterns"]=["restored-wazuh-alerts-4.x-*"]; t.pop("version",None); json.dump(t, open("restored-template.json","w"))'
   kubectl -n wazuh-5 exec -i wazuh-indexer-0 -c wazuh-indexer -- sh -c 'cd /usr/share/wazuh-indexer/config/certs; \
     curl -sk --cert admin.pem --key admin-key.pem -X PUT https://localhost:9200/_template/restored-wazuh-alerts-4.x \
     -H "Content-Type: application/json" --data-binary @-' < restored-template.json
   ```

3. **Copy the alerts**, with the 4.x `admin` password on standard input. Each 4.x index lands in `restored-<name>`:
   ```bash
   kubectl -n wazuh get secret indexer-cred -o jsonpath='{.data.password}' | base64 -d | \
     kubectl -n wazuh-5 exec -i wazuh-indexer-0 -c wazuh-indexer -- sh -c 'read -r P; cd /usr/share/wazuh-indexer/config/certs; \
     curl -sk --cert admin.pem --key admin-key.pem -X POST "https://localhost:9200/_reindex?wait_for_completion=true" \
     -H "Content-Type: application/json" -d "{\"source\":{\"remote\":{\"host\":\"https://indexer.wazuh.svc.cluster.local:9200\",\"username\":\"admin\",\"password\":\"$P\"},\"index\":\"wazuh-alerts-4.x-*\",\"size\":1000},\"dest\":{\"index\":\"restored-wazuh-alerts-4.x\"},\"script\":{\"lang\":\"painless\",\"source\":\"ctx._index = 'restored-' + ctx._index\"}}"'
   ```
   The answer reports `"created"` equal to `"total"` and `"failures":[]`. Compare the counts with `_cat/indices/restored-*?v&h=index,docs.count` on 5.0 and `_cat/indices/wazuh-alerts-4.x-*` on 4.x.

4. **Close it again**: apply the plain overlay and delete what it does not remove. The copied indices stay:
   ```bash
   kubectl apply -k envs/wazuh-5/
   kubectl -n wazuh-5 delete networkpolicy indexer-egress-4x
   kubectl -n wazuh-5 get secret -o name | grep indexer-4x-ca   # then kubectl -n wazuh-5 delete <that name>
   ```

### Reusing the `wazuh` namespace

5.0 can take the `wazuh` namespace once 4.x is gone from it. The 4.x deployment is then down from its removal until 5.0 is ready, there is no 4.x left to return to, and the historical data has to be read from the volumes 4.x leaves behind. Prepare Traefik, the certificates and the credentials of [Installation](getting-started/installation.md) before removing 4.x to shorten that window.

1. **Run steps 1 and 2** above: stop the 4.x managers and export the identity.

2. **Remove 4.x, claims included.** 5.0 uses the same claim names, and a 5.0 manager on a 4.x claim does not start. Check that the volumes outlive their claims before deleting anything:
   ```bash
   kubectl get storageclass wazuh-storage -o jsonpath='{.reclaimPolicy}'   # Retain
   kubectl get pv
   ```
   With `Delete`, removing the claims deletes the 4.x data, the indices included. Then, in the 4.x checkout:
   ```bash
   kubectl delete -k envs/eks/
   ```
   This removes the namespace and its load balancers. The 4.x volumes stay as `Released`, still naming their old claims, and nothing binds them again.

3. **Deploy 5.0** following [Installation](getting-started/installation.md) as written, in `wazuh`. 5.0 creates new volumes. Then run steps 4 to 6 above with `-n wazuh` in place of `-n wazuh-5`.

4. **Copy the historical data** from the 4.x indexer, started again in the `wazuh-4x` namespace on its own volumes. Point each 4.x indexer volume at a claim in `wazuh-4x`:
   ```bash
   for n in 0 1 2; do
     pv=$(kubectl get pv -o jsonpath="{range .items[?(@.spec.claimRef.name=='wazuh-indexer-wazuh-indexer-$n')]}{.metadata.name} {.spec.claimRef.namespace} {.status.phase}{'\n'}{end}" | awk '$2=="wazuh" && $3=="Released" {print $1}')
     kubectl patch pv "$pv" --type json -p "[{\"op\":\"replace\",\"path\":\"/spec/claimRef\",\"value\":{\"namespace\":\"wazuh-4x\",\"name\":\"wazuh-indexer-wazuh-indexer-$n\"}}]"
   done
   ```
   In the 4.x checkout, create an overlay that keeps only the indexer, with its `indexer` Service internal, and apply it:
   ```bash
   mkdir -p envs/wazuh-4x-indexer
   cat > envs/wazuh-4x-indexer/kustomization.yml <<'EOT'
   resources:
     - ../eks
   namespace: wazuh-4x
   patches:
     - target: {kind: StatefulSet, name: wazuh-manager-.*}
       patch: '{"$patch": "delete", "apiVersion": "apps/v1", "kind": "StatefulSet", "metadata": {"name": "any"}}'
     - target: {kind: Deployment, name: wazuh-dashboard}
       patch: '{"$patch": "delete", "apiVersion": "apps/v1", "kind": "Deployment", "metadata": {"name": "any"}}'
     - target: {kind: Service, name: "^(dashboard|wazuh|wazuh-workers|wazuh-cluster)$"}
       patch: '{"$patch": "delete", "apiVersion": "v1", "kind": "Service", "metadata": {"name": "any"}}'
     - target: {kind: StorageClass}
       patch: '{"$patch": "delete", "apiVersion": "storage.k8s.io/v1", "kind": "StorageClass", "metadata": {"name": "any"}}'
     - target: {kind: Service, name: indexer}
       patch: '[{"op": "replace", "path": "/spec/type", "value": "ClusterIP"}]'
   EOT
   kubectl apply -k envs/wazuh-4x-indexer/
   kubectl -n wazuh-4x rollout status statefulset/wazuh-indexer --timeout=900s
   ```
   The cluster reports `red` until the three nodes have joined, then `green` with the 4.x indices. Follow [Historical data](#historical-data) with these differences:
   - The reindex overlay lists `../eks` as its resource and sets `namespace: wazuh`, as does the metadata of `indexer-reindex.yaml`.
   - `reindex.remote.allowlist` is `indexer.wazuh-4x.svc.cluster.local:9200`, the NetworkPolicy selects the `wazuh-4x` namespace, and the reindex `host` is `https://indexer.wazuh-4x.svc.cluster.local:9200`.
   - The 4.x root CA, the 4.x template and the `indexer-cred` Secret are read with `-n wazuh-4x`, and the 5.0 commands run with `-n wazuh`.
   - To close it, apply `envs/eks/` instead of `envs/wazuh-5/`.

   Then remove the 4.x indexer from the 4.x checkout. Its volumes are `Released` again:
   ```bash
   kubectl delete -k envs/wazuh-4x-indexer/
   ```

The 4.x volumes are the only copy of the 4.x deployment. With `Retain`, deleting their claims or the cluster does not delete them: delete the `PersistentVolume` objects and the volumes at the cloud provider once the migration is complete.

### Configuration and content

5.0 reads none of the 4.x configuration files: each one is rewritten following the manager guide. Read the 4.x files from the claim of the master, with a one-off pod as in step 2, or from the 4.x checkout.

| 4.x source | 4.x path in the pod | 5.0 destination |
|---|---|---|
| ConfigMap `wazuh-conf` (`wazuh/wazuh_managers/wazuh_conf/master.conf`, `worker.conf`), copied to the claim on every start | `/var/ossec/etc/ossec.conf` | `/etc/wazuh-manager/wazuh-manager.conf` on the claim of each manager (subPath `wazuh/etc/wazuh-manager`), rewritten as the [Manager configuration migration](https://github.com/wazuh/wazuh/blob/5.0.0/docs/guide/migration/manager-configuration-migration.md) guide says |
| Master claim | `/var/ossec/etc/rules`, `decoders`, `lists` | Rewritten as detection rules, engine decoders and KVDBs: [rules](https://github.com/wazuh/wazuh/blob/5.0.0/docs/guide/migration/rules-4x-to-5x.md), [decoders](https://github.com/wazuh/wazuh/blob/5.0.0/docs/guide/migration/xml-decoders-migration.md), [CDB lists](https://github.com/wazuh/wazuh/blob/5.0.0/docs/guide/migration/cdb-to-kvdb-migration.md) |
| Master claim | `/var/ossec/etc/shared/<group>/` | Carried by `wazuh-migrate-identity.py`. The export lists the files it leaves out, such as the 4.x rootcheck files of the `default` group |
| Master claim | `/var/ossec/api/configuration/api.yaml` | `/var/wazuh-manager/api/configuration/api.yaml` on the claim of the master |
| ConfigMap `indexer-conf` | `opensearch.yml`, `opensearch-security/internal_users.yml` | Environment variables in `indexer-sts.yaml`. The shipped accounts take their passwords from `wazuh/config/credentials/indexer.env` (see [Credentials](credentials.md)) |
| ConfigMap `dashboard-conf` | `opensearch_dashboards.yml` | Environment variables in `dashboard-deploy.yaml` (`OPENSEARCH_HOSTS`, `WAZUH_API_URL`) |
| Secrets `indexer-cred`, `dashboard-cred`, `wazuh-api-cred` | Environment variables | `wazuh/config/credentials/*.env` |
| Secret `wazuh-authd-pass` | `/var/ossec/etc/authd.pass` | Carried by `wazuh-migrate-identity.py` with `--with-password` |

Validate the manager configuration before restarting the manager:

```bash
kubectl -n wazuh-5 exec wazuh-manager-master-0 -c wazuh-manager -- /var/wazuh-manager/bin/wazuh-manager-conf validate
```
