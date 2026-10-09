# Credentials

The Wazuh images ship no passwords. Every deployment gets its own: they are generated once, before
the first `kubectl apply -k`, by `tools/utils/deployment/credentials-conf.sh`. Each component
receives only the ones it needs, as a file. On its first start, each component stores what it
received: the indexer in its security configuration, the manager in its Wazuh API user database and
keystore, the dashboard in its keystore. From then on, the stored values are the ones that count.

## Table of Contents

- [Creating the credentials](#creating-the-credentials)
- [First access](#first-access)
- [How the passwords reach the pods](#how-the-passwords-reach-the-pods)
- [The accounts](#the-accounts)
- [Rotating a password on a running deployment](#rotating-a-password-on-a-running-deployment)
- [The cluster key and the agent enrollment password](#the-cluster-key-and-the-agent-enrollment-password)
- [Multi-node deployments and scaling](#multi-node-deployments-and-scaling)
- [Effect on the integration test suite](#effect-on-the-integration-test-suite)
- [Checking that no default is left](#checking-that-no-default-is-left)
- [Notes](#notes)

## Creating the credentials

Run it from the `wazuh/` directory, after the certificates and before the first deployment. It
sources the Wazuh credentials library, `wazuh-credentials.sh`, from the same directory
(`WAZUH_CREDENTIALS_LIB` overrides the path). Download it in the same version as the images:

```bash
cd wazuh
curl -so wazuh-credentials.sh https://raw.githubusercontent.com/wazuh/wazuh-installation-assistant/5.0.0/credentials_lib/wazuh-credentials.sh
sudo bash ../tools/utils/deployment/certificates-conf.sh --cert --copy --priv
sudo bash ../tools/utils/deployment/credentials-conf.sh
cd ..
kubectl apply -k envs/eks/   # or envs/local-env/
```

It writes `wazuh/config/credentials/{indexer,manager,dashboard}.env`, one file per component holding
only the keys that component needs, and `wazuh/config/credentials/cluster.key`, the key the manager
nodes share to form the cluster. Keep them for the whole life of the deployment: every
`kubectl apply -k` and `kubectl delete -k` reads them, and the indexer takes its passwords from them
again every time one of its pods is recreated.

- **Why `sudo`:** `certificates-conf.sh` creates `config/` as root. The files are still given to the
  user who ran `sudo`, with `0700` on the directory and `0600` on each file, so `kubectl apply -k` can
  read them without root.
- **Your own values:** to set a password instead of generating it, give its key in the environment.
  The value is validated against the password rules, and nothing is written if any value fails:

  ```bash
  sudo WAZUH_INDEXER_ADMIN_PASSWORD='<password>' bash ../tools/utils/deployment/credentials-conf.sh
  ```

  The cluster key is given the same way, as `WAZUH_CLUSTER_KEY`: exactly 32 characters from
  `A-Z a-z 0-9`.

- **No overwrite:** the script never replaces existing files. `--force` replaces them, and is only for
  a deployment that has never been started.
- **Password rules:** 12 to 64 characters from `A-Z a-z 0-9 . , _ + : @ % ^ = ~ -`, with at least one
  lowercase letter, one uppercase letter, one digit and one symbol. Generated passwords are 32
  characters long.

## First access

```bash
grep '^WAZUH_INDEXER_ADMIN_PASSWORD=' wazuh/config/credentials/indexer.env | cut -d= -f2-
```

Log into the dashboard as `admin` with that value.

## How the passwords reach the pods

`wazuh/kustomization.yml` turns each file into a Secret with a single key, `wazuh-credentials`:

| Secret | From | Mounted in |
| --- | --- | --- |
| `indexer-credentials` | `config/credentials/indexer.env` | `wazuh-indexer` |
| `manager-credentials` | `config/credentials/manager.env` | `wazuh-manager-master`, `wazuh-manager-worker` |
| `dashboard-credentials` | `config/credentials/dashboard.env` | `wazuh-dashboard` |

kustomize appends a hash of the content to each name (`indexer-credentials-<hash>`), so a changed file
produces a new Secret and rolls the workloads that mount it. The three carry the label
`app.kubernetes.io/component=credentials`:

```bash
kubectl -n wazuh get secrets -l app.kubernetes.io/component=credentials
```

A volume of a Secret takes the pod's `fsGroup`, which is the service user's group, and group read. So
the Secret is mounted only in an init container, `install-credentials`, which copies it to
`/run/secrets/wazuh-credentials` in a memory `emptyDir`, as a root-only file. The container mounts that
directory read-only, installs the file as `/etc/wazuh/credentials.env`, which is what the Wazuh
packages resolve their credentials from, and deletes that copy once the component has stored the
values. Then the service starts under its own user.

- The passwords are not in the pod spec or in the container environment: `kubectl describe` and
  `kubectl exec … env` do not show them, and the service users cannot read the file.
- Anyone who can read Secrets in the `wazuh` namespace can read them. Restrict that permission.
- The containers have to start as root, since they drop to their service user themselves. Started as
  another user (`runAsUser`), the indexer and dashboard containers stop with
  `credentials: this container has to start as root`.

If a key is missing or does not meet the rules, the container stops before its service starts, and
names the key. It never prints the value:

```text
credentials: MISSING WAZUH_INDEXER_ADMIN_PASSWORD
credentials: create the deployment credentials with tools/utils/deployment/credentials-conf.sh
```

Fix `wazuh/config/credentials/<file>.env` and apply the overlay again: the Secret gets a new name, so
the workloads that read it are recreated with the fixed file.

If one of the files is missing, `kubectl apply -k` (and `kubectl delete -k`) stops before sending
anything to the cluster:

```text
error: accumulating resources: ... loading KV pairs: file sources: [wazuh-credentials=config/credentials/indexer.env]: evalsymlink failure on '.../wazuh/config/credentials/indexer.env' : lstat .../wazuh/config/credentials: no such file or directory
```

Run `credentials-conf.sh` for a new deployment, or restore the files from your backup for an existing
one: new values would not match the ones the components stored.

## The accounts

| Account | Key | In | Used by |
| --- | --- | --- | --- |
| `admin` | `WAZUH_INDEXER_ADMIN_PASSWORD` | `indexer.env` | People: administrator of the indexer, and the account to log into the Wazuh dashboard with |
| `kibanaserver` | `WAZUH_INDEXER_KIBANASERVER_PASSWORD` | `indexer.env`, `dashboard.env` | The dashboard, to authenticate to the indexer |
| `wazuh-manager` | `WAZUH_INDEXER_MANAGER_PASSWORD` | `indexer.env`, `manager.env` | The managers, master and workers, to write events and read state in the indexer |
| `wazuh` | `WAZUH_MANAGER_API_PASSWORD` | `manager.env` | People and automation: superuser of the Wazuh API, for example to mint agent enrollment tokens |
| `wazuh-wui` | `WAZUH_MANAGER_WUI_PASSWORD` | `manager.env`, `dashboard.env` | The dashboard, to call the Wazuh API on behalf of the logged-in user |

The first three live in the indexer's security index and are cluster-wide. The last two live in the
Wazuh API user database, `rbac.db`, which only the manager master has: the Wazuh API runs on the
master, and a worker does not create one. A worker still receives the whole `manager.env`, and needs
it: the manager image requires `WAZUH_MANAGER_API_PASSWORD` and `WAZUH_MANAGER_WUI_PASSWORD` on
every start while there is no `rbac.db`, which on a worker is always. If the worker is promoted to
master, it creates its database from them.

The OpenSearch demo accounts (`anomalyadmin`, `kibanaro`, `logstash`, `readall`,
`snapshotrestore`) are removed from the indexer image when it is built. They do not exist in the
deployment.

## Rotating a password on a running deployment

**Editing a value in `wazuh/config/credentials/*.env` after the first start changes nothing.** The
components keep the values they stored. The pods roll, and the dashboard and the managers log that
they ignore the new value:

```text
resolve-credentials: opensearch.password is already in the keystore; WAZUH_INDEXER_KIBANASERVER_PASSWORD is ignored
```
 Use `password-tool.sh` instead: it changes the account on the
running deployment and prints the new password and the commands that apply it to the rest of the
deployment. The printed commands are written for Docker Compose. On Kubernetes, run the equivalents
below, from the root of the repository.

Change the account:

```bash
kubectl -n wazuh exec wazuh-indexer-0 -c wazuh-indexer -- /password-tool.sh --user kibanaserver    # admin, kibanaserver, wazuh-manager
kubectl -n wazuh exec wazuh-manager-master-0 -c wazuh-manager -- /password-tool.sh --user wazuh-wui # wazuh, wazuh-wui
```

To choose the password yourself, pass it on standard input:

```bash
printf '%s\n' '<password>' | kubectl -n wazuh exec -i wazuh-indexer-0 -c wazuh-indexer -- /password-tool.sh --user admin --stdin
```

Then keep the password the tool printed in a variable, and apply it to the components that consume
the account:

```bash
NEW='<the password the tool printed>'
```

- **`kibanaserver`**: the dashboard keystore.

  ```bash
  printf '%s' "$NEW" | kubectl -n wazuh exec -i deploy/wazuh-dashboard -c wazuh-dashboard -- \
    runuser -u wazuh-dashboard -- /usr/share/wazuh-dashboard/bin/opensearch-dashboards-keystore add -f --stdin opensearch.password
  ```

- **`wazuh-wui`**: the dashboard keystore.

  ```bash
  printf '%s' "$NEW" | kubectl -n wazuh exec -i deploy/wazuh-dashboard -c wazuh-dashboard -- \
    runuser -u wazuh-dashboard -- /usr/share/wazuh-dashboard/bin/opensearch-dashboards-keystore add -f --stdin wazuh_core.hosts.default.password
  ```

- **`wazuh-manager`**: the keystore of every manager pod, master and workers.

  ```bash
  for pod in $(kubectl -n wazuh get pods -l app=wazuh-manager -o name); do
    printf '%s' "$NEW" | kubectl -n wazuh exec -i "$pod" -c wazuh-manager -- \
      /var/wazuh-manager/bin/wazuh-manager-keystore -f indexer -k password
  done
  ```

- **`admin`, `wazuh`**: no component consumes them.

Finally, record the new value in the credentials files and apply the overlay:

```bash
KEY=WAZUH_INDEXER_KIBANASERVER_PASSWORD    # the key of the account, see The accounts
sed -i "s|^${KEY}=.*|${KEY}=${NEW}|" wazuh/config/credentials/*.env
kubectl apply -k envs/eks/   # or envs/local-env/
```

The files are the deployment's record of its passwords: a pod whose volume is lost, a new replica,
and every recreated indexer pod take their credentials from them. Applying the overlay regenerates
the Secrets whose file changed, and the workloads that mount them are recreated, which is also what
makes the dashboard and the managers load the new keystore value.

Skipping the keystore step leaves the consumer on the old value. The dashboard, for example, answers
`503` while its pod stays `Ready`.

The previous Secrets stay in the namespace, with the old values. Once the workloads run on the new
ones, delete those that no workload references:

```bash
used=$(kubectl -n wazuh get deploy,sts -o jsonpath='{..secretName}' | tr ' ' '\n' | sort -u)
for secret in $(kubectl -n wazuh get secrets -l app.kubernetes.io/component=credentials -o name); do
  echo "$used" | grep -qx "${secret#secret/}" || kubectl -n wazuh delete "$secret"
done
```

A `kubectl rollout undo` of the dashboard to a revision whose Secret was deleted cannot start its pod.

> **Note**: between changing the password and the consuming workload being recreated, that workload
> authenticates with a value that no longer works. Keep the gap short, and see the warning about the
> manager probes under [Notes](#notes).

The manager tool refuses to run on a worker, which has no Wazuh API user database, and before the
master's first start.

## The cluster key and the agent enrollment password

Neither is an account, so `password-tool.sh` has nothing to do with them, and neither ships with the
manifests.

- **The cluster key** is generated by `credentials-conf.sh` into `wazuh/config/credentials/cluster.key`,
  with the passwords. `wazuh/kustomization.yml` turns it into the `wazuh-cluster-key-<hash>` Secret,
  and the managers take it on **every container start** as `WAZUH_CLUSTER_KEY`, into `<cluster><key>`
  of `/var/wazuh-manager/etc/wazuh-manager.conf`.
- **The agent enrollment password** is generated by the master on its first start, as 64
  hexadecimal characters in `/var/wazuh-manager/etc/authd.pass`, on its persistent volume. The
  manager cluster distributes it to the workers.

| Value | Where it lives | Read by | What it protects |
| --- | --- | --- | --- |
| Cluster key | `wazuh/config/credentials/cluster.key`, Secret `wazuh-cluster-key-<hash>` (`key`) | `wazuh-manager-master`, `wazuh-manager-worker` | Membership of the Wazuh manager cluster on port `1516`. A node whose key does not match the master's cannot join it. |
| Agent enrollment password | `/var/wazuh-manager/etc/authd.pass` on the master, synchronized to the workers | `wazuh-manager-master`, `wazuh-manager-worker` | Agent enrollment with a password: Password-mode enrollment of Wazuh 5.x agents on port `1517`, and the legacy `authd` enrollment of 4.x agents on port `1515`. Token-mode enrollment on `1517` uses tokens minted through the Wazuh API instead. |

Keep `cluster.key` with the other files in `config/credentials/`: every `kubectl apply -k` reads it.
The key does not survive on its own in a persistent volume: it is rewritten from the Secret at every
container start, so **deleting the PersistentVolumeClaims does not return it to a default**.

### Reading the agent enrollment password

The guides enroll agents with tokens, which need no password. To enroll with the shared password
instead, read it from the master:

```bash
kubectl -n wazuh exec wazuh-manager-master-0 -c wazuh-manager -- cat /var/wazuh-manager/etc/authd.pass
```

### Changing them on a deployment that is already running

#### The agent enrollment password

Delete the file on the master and restart it. The master generates a new password and the cluster
distributes it to the workers:

```bash
kubectl -n wazuh exec wazuh-manager-master-0 -c wazuh-manager -- rm /var/wazuh-manager/etc/authd.pass
kubectl -n wazuh rollout restart statefulset/wazuh-manager-master
kubectl -n wazuh rollout status statefulset/wazuh-manager-master
```

Agents that are already enrolled keep working: they authenticate with the key in
`client.keys`. Only agents that enroll from this point on with a password (5.x on `1517`, 4.x on
`1515`) have to present the new one.

> **Note**: deployments created from a release that shipped `wazuh/secrets/wazuh-authd-pass-secret.yaml`
> keep its value, the string `password`, on the persistent volume after upgrading. Rotate it as shown
> above, and delete the old Secret with `kubectl -n wazuh delete secret wazuh-authd-pass`.

#### The cluster key

Write a new key into `cluster.key`, without a trailing newline, and apply. The key has to be exactly
32 alphanumeric characters; `openssl rand -hex 16` produces exactly that, and any other length or
character makes the managers refuse to start:

```bash
openssl rand -hex 16 | tr -d '\n' > wazuh/config/credentials/cluster.key
kubectl apply -k envs/eks/   # or envs/local-env/
kubectl -n wazuh rollout status statefulset/wazuh-manager-master
kubectl -n wazuh rollout status statefulset/wazuh-manager-worker
```

The new content gives the Secret a new name, so `kubectl apply -k` rolls **both** manager
StatefulSets on its own.

> **Warning**: until every manager pod has restarted, the ones still on the old key cannot sync with
> the master. The cluster is degraded for the length of the restart, so do this in a maintenance
> window on a production deployment.

> **Note**: deployments created from a release that shipped `wazuh/secrets/wazuh-cluster-key-secret.yaml`
> have every `*.env` file but no `cluster.key`. Run `credentials-conf.sh` again: it adds only
> `cluster.key` and leaves the passwords as they are. To keep the key the cluster runs on, pass it in
> `WAZUH_CLUSTER_KEY`:
>
> ```bash
> cd wazuh
> sudo WAZUH_CLUSTER_KEY="$(kubectl -n wazuh get secret wazuh-cluster-key -o jsonpath='{.data.key}' | base64 -d)" \
>   bash ../tools/utils/deployment/credentials-conf.sh
> cd ..
> ```
>
> The placeholder `REPLACETHISCLUSTERKEYBEFOREDEPLO` is refused; leave `WAZUH_CLUSTER_KEY` unset to
> generate a new key instead. After `kubectl apply -k`, delete the old Secret with
> `kubectl -n wazuh delete secret wazuh-cluster-key`.

Confirm the new key is in place on each node and that the workers rejoined:

```bash
kubectl -n wazuh exec wazuh-manager-master-0 -c wazuh-manager -- \
  grep '<key>' /var/wazuh-manager/etc/wazuh-manager.conf
kubectl -n wazuh logs statefulset/wazuh-manager-worker --tail=50 | grep -i cluster
```

## Multi-node deployments and scaling

- **The indexer accounts are cluster-wide.** The three indexer pods share `indexer-credentials`, and
  a change made with `password-tool.sh` on one of them reaches all of them.
- **The Wazuh API accounts live on the master only.** Change them there. A worker has no Wazuh API
  user database; a worker that is later promoted creates one from `manager.env`, which is why the
  rotation above keeps that file up to date.
- **`wazuh-manager` is consumed by every manager pod.** After changing it, update the keystore of the
  master and of every worker, as shown above.

## Effect on the integration test suite

`tests/k8s_pytest.py` authenticates to the indexer as `admin`, with the password it reads from
`wazuh/config/credentials/indexer.env`. Pass `--indexer-password` to use another value, for example
from a machine that does not have the files:

```bash
pytest tests/k8s_pytest.py -v --deployment-type local
```

See [How to run the tests](../dev/run-tests.md).

## Checking that no default is left

Run it from the `wazuh/` directory, where it finds `config/credentials/`:

```bash
cd wazuh
../tools/tests/check-default-credentials.sh
cd ..
```

It reads the generated passwords from `config/credentials/` and checks, from inside the pods, that
every account (`admin`, `kibanaserver`, `wazuh-manager`, `wazuh`, `wazuh-wui`) authenticates with its
generated password and none with its own username, that the indexer carries none of the OpenSearch
demo accounts, that only the master holds a Wazuh API user database, and that every manager pod runs
on the key in `config/credentials/cluster.key`. The credentials reach `curl`
on standard input, never as arguments. It needs neither port-forwarding nor any published port. Pass
`-n` for a different namespace, `-i` and `-m` to name the indexer and manager pods, and `-c` for
another credentials directory.

## Notes

- `wazuh/config/credentials/*.env` is the record of the deployment's passwords, in clear text. It is
  in `.gitignore`: keep it out of your commits, back it up with the certificates, and restrict access
  to it.
- The passwords are stored on persistent volumes: the indexer security index (with the
  `/var/lib/wazuh-indexer/.initialized` marker), `rbac.db` on the master, the keystore in
  `queue/keystore` on every manager pod, and the dashboard keystore on the `wazuh-dashboard-config`
  claim. **Deleting those PersistentVolumeClaims makes the pods take their credentials again from the
  Secrets**, which hold the values of the files. A restore therefore has to bring back the volumes
  and `config/credentials/*.env` from the same point in time.
- `password-tool.sh` keeps no copy of what it prints; the copy that matters afterwards is what you
  write into `config/credentials/*.env`. A password that is lost without having been recorded there
  is replaced, not recovered: run the tool again for that account.
- **The manager probes do not detect a credential mismatch.** `startupProbe`, `readinessProbe` and
  `livenessProbe` on the manager pods run `wazuh-manager-control status`, which reports on local
  daemons and never contacts the indexer. A manager that cannot authenticate stays `Ready` while
  failing to index. Confirm the connection from the logs, not from the pod status.
- `/securityadmin.sh` on its own is a different thing. With no arguments it uploads the whole security
  configuration of the image, replacing the one the cluster is running: every internal user that is
  not in the image is deleted, custom role mappings are reverted, and every password is replaced by
  what that node's `internal_users.yml` holds. Use `password-tool.sh` to change a password.
- For production, consider an external secret manager integrated with Kubernetes instead of the
  generated `config/credentials/` files. See [Security](security.md).
