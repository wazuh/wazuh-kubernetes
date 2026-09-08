# Credentials

The Wazuh images ship with documented default passwords, and a deployment that keeps them answers to
anyone who has read this page. **Changing them is the first thing to do after the first deployment**,
and this page is the procedure.

Each image carries `password-tool.sh`, which changes the passwords of the running deployment and
prints the new ones once. It stores nothing: what it prints is the only copy, and the passwords the
workloads need are written by hand into the Secrets under `wazuh/secrets/`.

Two values are not accounts and are not covered by that tool: the manager cluster key and the agent
enrollment password. They come from Secret manifests in this repository, so they are set **before the
first deployment** rather than after it. See
[The cluster key and the agent enrollment password](#the-cluster-key-and-the-agent-enrollment-password).

## The accounts

Two components hold accounts, in separate databases reached over separate ports. The "Secret" column
is where the new password has to be written for the deployment to keep working; the accounts with no
Secret are for people and are not presented by any pod.

### Wazuh indexer

These live in the security plugin's internal user database, inside the security index. They are
cluster-wide: a change made on one indexer pod reaches all of them.

| Account | Default password | Secret | Workloads that present it | What it is for |
| --- | --- | --- | --- | --- |
| `admin` | `admin` | — | — | Administrator of the indexer: every index, the cluster settings and the security configuration. Logging into the dashboard as `admin` also produces a Wazuh API administrator session. |
| `kibanaserver` | `kibanaserver` | `dashboard-cred` | `wazuh-dashboard` | Service account the dashboard authenticates to the indexer as. |
| `wazuh-manager` | `wazuh-manager` | `indexer-cred` | `wazuh-manager-master`, `wazuh-manager-worker`, `wazuh-dashboard` | Service account the managers write events and read state as. |
| `wazuh-admin` | `wazuh-admin` | — | — | Wazuh administrator: reads the Wazuh indices, writes Wazuh settings and content, and administers the Security Analytics plugin. Also the account the integration test suite authenticates with. |
| `wazuh-readonly` | `wazuh-readonly` | — | — | Read-only access to settings, content and detectors. |
| `wazuh-demo` | `wazuh-demo` | — | — | Content management, without administration of the deployment. |

> **Important**: the indexer StatefulSet consumes no credential Secret at all. Its accounts come from
> `internal_users.yml` inside the image. Editing `indexer-cred` changes only what the managers and the
> dashboard *present*; it does not change what the indexer *accepts*. Both halves are needed, which is
> why the procedure below runs `password-tool.sh` **and** updates the Secret.

The OpenSearch demo accounts (`anomalyadmin`, `kibanaro`, `logstash`, `readall`, `snapshotrestore`)
are **not** part of a Wazuh deployment. They are removed from the indexer image when it is built, so
they do not exist and cannot be logged into.

### Wazuh manager

These live in the API's RBAC database, `rbac.db`, under
`/var/wazuh-manager/api/configuration/security/` on each manager node's persistent volume.

| Account | Default password | Secret | Workloads that present it | What it is for |
| --- | --- | --- | --- | --- |
| `wazuh` | `wazuh` | — | — | Superuser of the Wazuh API. |
| `wazuh-wui` | `wazuh-wui` | `wazuh-api-cred` | `wazuh-manager-master`, `wazuh-dashboard` | Service account the dashboard proxies manager requests as. It asks the API to act as the logged-in dashboard user, so what a dashboard session can do is decided by that user's role, not by this account. |

> **Important**: this database is local to each manager node and the Wazuh cluster does not
> synchronize it. On this deployment only the manager master serves the Wazuh API — the worker pods
> run no `wazuh-manager-apid`, declare no port `55000`, and the `wazuh-api` Service selects
> `node-type: master` — so the master's database is the only one consulted for authentication.

### Other secrets

Two more Secrets hold shared material rather than account passwords. They are not covered by
`password-tool.sh`, and they are set by editing the manifest **before deploying**:
[The cluster key and the agent enrollment password](#the-cluster-key-and-the-agent-enrollment-password)
is the procedure, for a fresh deployment and for one already running.

| Secret | Key | Default value | What it is for |
| --- | --- | --- | --- |
| `wazuh-authd-pass` | `authd.pass` | `password` | Enrollment password, mounted as a file into every manager pod. It guards the enrollment `remoted` serves on port `1517` and the legacy `authd` port `1515`. |
| `wazuh-cluster-key` | `key` | `123a45bc67def891gh23i45jk67l8mn9` | Shared key for manager cluster membership, on port `1516`. |

## Changing the passwords on the first deployment

Run this once, immediately after the deployment comes up for the first time. The examples use the
`wazuh` namespace and the pod names of the default topology: one indexer pod per replica
(`wazuh-indexer-0`…), one manager master (`wazuh-manager-master-0`) and the worker replicas of your
overlay (`wazuh-manager-worker-0`, and `wazuh-manager-worker-1` on the `eks` overlay).

### Step 1: Wait for the deployment to be ready

The tools work against the running cluster, so every pod has to be `Ready` before going on. The first
start takes a couple of minutes.

```bash
kubectl -n wazuh get pods
kubectl -n wazuh wait --for=condition=Ready pod --all --timeout=600s
```

### Step 2: Change the Wazuh indexer passwords

```bash
kubectl -n wazuh exec wazuh-indexer-0 -- /password-tool.sh --all
```

It prints every account with its new password, and repeats the two that a workload presents:

```console
$ kubectl -n wazuh exec wazuh-indexer-0 -- /password-tool.sh --all

Changed on the running deployment:

  admin            r?FT4dqvBn0LxlXQ.uYm-3jHsWk8zAeC
  kibanaserver     G2wrq1B20.eXC85*-8inI+F27y8UwoL.
  wazuh-manager    Bqf7j57J3BNEb5RgP9kprDX0GY*6QjmM
  wazuh-admin      j*YwhC.RUiJYCq4Qs10v3U3qm3keJqec
  wazuh-readonly   2d1a5KtVeVCHkrRytEmRYS4c8VGouku.
  wazuh-demo       o0V1D.k*qdJaydzha3eYQlvdDOjRLg4v

This is the only time these passwords are shown. Nothing is stored.
```

**Copy the whole output somewhere safe before going on.** It is not written to any file and it is not
shown again. The `admin` password is the one that logs into the dashboard.

The tool mentions `docker-compose.yml`, because it is shared with the Docker deployment method. On
Kubernetes the equivalent is the Secrets, which step 5 covers: `kibanaserver` goes into
`dashboard-cred` and `wazuh-manager` into `indexer-cred`.

> **Note**: any indexer pod works. The change is written to the security index, which is shared by
> the whole indexer cluster.

### Step 3: Change the Wazuh API passwords on the manager master

```bash
kubectl -n wazuh exec wazuh-manager-master-0 -- /password-tool.sh --all
```

```console
$ kubectl -n wazuh exec wazuh-manager-master-0 -- /password-tool.sh --all

Changed on this manager node:

  wazuh            ZD04YaYFH*JC?gOvWWaF54O-MrgJEm6K
  wazuh-wui        VdzPHTfpFCw8MbPkX?nek2902VkwYDsQ

This is the only time these passwords are shown. Nothing is stored.
```

### Step 4 (optional): Clear the defaults left in the worker databases

The Wazuh API runs on the manager master only, so the workers' `rbac.db` is never consulted for
authentication and the deployment is fully rotated without this step. The copies on the workers do
still hold the shipped defaults, though, so clear them if you would rather no default hash survive
anywhere on disk.

Pass each password on standard input. Note `exec -i`, without which the pod receives no input:

```bash
for pod in $(kubectl -n wazuh get pods -l app=wazuh-manager,node-type=worker \
    -o jsonpath='{.items[*].metadata.name}'); do
  printf '%s\n' 'ZD04YaYFH*JC?gOvWWaF54O-MrgJEm6K' | \
    kubectl -n wazuh exec -i "${pod}" -- /password-tool.sh --user wazuh --stdin
  printf '%s\n' 'VdzPHTfpFCw8MbPkX?nek2902VkwYDsQ' | \
    kubectl -n wazuh exec -i "${pod}" -- /password-tool.sh --user wazuh-wui --stdin
done
```

> **Note**: `tools/tests/check-default-credentials.sh` cannot verify this. It reaches the Wazuh API
> over `localhost:55000` inside the pod, and nothing answers there on a worker.

### Step 5: Write the three service passwords into the Secrets

Three of the passwords are presented by a workload and have to go into a Secret. The usernames do not
change.

| New password of | Secret file | Key |
| --- | --- | --- |
| `wazuh-manager` (indexer) | `wazuh/secrets/indexer-cred-secret.yaml` | `password` |
| `kibanaserver` (indexer) | `wazuh/secrets/dashboard-cred-secret.yaml` | `password` |
| `wazuh-wui` (API) | `wazuh/secrets/wazuh-api-cred-secret.yaml` | `password` |

The other five passwords go nowhere: no pod presents them.

Encode each new password, without a trailing newline:

```bash
echo -n 'Bqf7j57J3BNEb5RgP9kprDX0GY*6QjmM' | base64
```

Then replace the `password` value in the corresponding file, keeping `username` as it is:

```yaml
# wazuh/secrets/indexer-cred-secret.yaml
data:
  username: d2F6dWgtbWFuYWdlcg==                              # string "wazuh-manager" base64 encoded
  password: QnFmN2o1N0ozQk5FYjVSZ1A5a3ByRFgwR1kqNlFqbU0=      # the new password
```

Apply the overlay you deployed with:

```bash
kubectl apply -k envs/local-env/   # or envs/eks/
```

> **Important**: a base64 value is encoding, not encryption — anyone who can read the file can read
> the password. Keep these edits out of your commits and restrict read access to the deployment
> directory as you do for the generated certificates under `wazuh/config/`.

An alternative that leaves the repository untouched is to patch the live Secret instead:

```bash
kubectl -n wazuh patch secret indexer-cred \
  -p '{"stringData":{"password":"Bqf7j57J3BNEb5RgP9kprDX0GY*6QjmM"}}'
```

> **Warning**: a patched Secret is reverted the next time anyone runs `kubectl apply -k envs/<env>/`,
> which puts the deployment back on the default password while the indexer keeps the new one. Prefer
> editing the manifest, or make sure whoever re-applies the overlay knows.

Prefer applying the overlay over `kubectl apply -f wazuh/secrets/<file>`. The Secret manifests do
declare `namespace: wazuh`, so a direct apply lands in the right namespace, but going through
Kustomize keeps the live Secret and the overlay you deploy with in agreement.

### Step 6: Restart the workloads that read the Secrets

A Secret consumed with `valueFrom.secretKeyRef` is read into the environment when the container
starts. Until the pods are restarted they keep presenting the old password:

```bash
kubectl -n wazuh rollout restart statefulset/wazuh-manager-master
kubectl -n wazuh rollout restart statefulset/wazuh-manager-worker
kubectl -n wazuh rollout restart deployment/wazuh-dashboard

kubectl -n wazuh rollout status statefulset/wazuh-manager-master
kubectl -n wazuh rollout status statefulset/wazuh-manager-worker
kubectl -n wazuh rollout status deployment/wazuh-dashboard
```

All three are restarted because `indexer-cred` is presented by all three. The indexer pods need no
restart: their accounts changed in the security index, not in their environment.

> **Note**: between step 2 and the end of step 6 the managers and the dashboard authenticate to the
> indexer with a password that no longer works. That gap is unavoidable. Keep it short, and see the
> warning about the manager probes under [Notes](#notes).

### Step 7: Confirm

```bash
tools/tests/check-default-credentials.sh
```

Every account has to be refused with its own username as its password. Then log into the dashboard as
`admin` with the new password, and confirm the deployment still works end to end:

```bash
kubectl -n wazuh logs statefulset/wazuh-manager-master --tail=50
pytest tests/k8s_pytest.py -v --deployment-type local \
  --indexer-password 'j*YwhC.RUiJYCq4Qs10v3U3qm3keJqec'
```

## What the tool touches

`password-tool.sh` changes the password of the accounts you name, on the running deployment, and
nothing else:

| | |
| --- | --- |
| Passwords of the accounts named | changed |
| Passwords of every other account, including ones you created | untouched |
| Accounts you created yourself | kept, with their roles, attributes and description |
| Roles and role mappings | not written at all |
| The user database inside the image | not modified |

It works this way because it takes the user database from the running cluster before changing it,
rather than uploading the one in the image.

## Changing one password later

The same tool, with `--user` instead of `--all`:

```bash
kubectl -n wazuh exec wazuh-indexer-0 -- /password-tool.sh --user admin
kubectl -n wazuh exec wazuh-manager-master-0 -- /password-tool.sh --user wazuh-wui
```

To choose the password instead of having one generated, pass it on standard input:

```bash
printf '%s\n' 'MyNewPassword.1' | \
  kubectl -n wazuh exec -i wazuh-indexer-0 -- /password-tool.sh --user admin --stdin
```

A password must be 8 to 64 characters and contain an upper case letter, a lower case letter, a digit
and one of `.*+?-`. The Wazuh API rejects anything else.

If the account you changed has a Secret, repeat steps 5 and 6 for that Secret and the workloads that
present it. Changing `admin`, `wazuh-admin`, `wazuh-readonly`, `wazuh-demo` or `wazuh` takes effect
immediately and needs no Secret update and no restart. A Wazuh API account has to be changed on the
manager master, which is the node that serves the API.

## The cluster key and the agent enrollment password

`wazuh-cluster-key` and `wazuh-authd-pass` work differently from every account above. They are not
rows in a database inside an image: the managers take them from the Secret on **every container
start**, `WAZUH_CLUSTER_KEY` into `<cluster><key>` of `/var/wazuh-manager/etc/wazuh-manager.conf` and
`authd.pass` into the file `/var/wazuh-manager/etc/authd.pass`. So `password-tool.sh` has nothing to
do with them, and changing one is a matter of editing the manifest and restarting the managers.

| Secret | Key | Default value | Read by | What it protects |
| --- | --- | --- | --- | --- |
| `wazuh-cluster-key` | `key` | `123a45bc67def891gh23i45jk67l8mn9` | `wazuh-manager-master`, `wazuh-manager-worker` | Membership of the Wazuh manager cluster on port `1516`. A node whose key does not match the master's cannot join it. |
| `wazuh-authd-pass` | `authd.pass` | `password` | `wazuh-manager-master`, `wazuh-manager-worker` | Agent enrollment: the channel `remoted` serves on port `1517` on every node, and the legacy `authd` port `1515` on the master. |

### Set them before the first deployment

**These two belong in the installation, not in the first-deployment rotation above.** They are the one
part of this page that is better done before `kubectl apply -k` than after the pods come up:

- Nothing has to be running. The values come from the manifests, so there is no tool to exec into a
  pod for and no chicken-and-egg with the deployment being up.
- **Changing the cluster key on a running deployment interrupts the cluster.** Every manager node has
  to carry the same key, and a restart that does not cover all of them at once leaves workers on the
  old key while the master is already on the new one; they cannot sync until each pod has restarted.
- The default enrollment password is the string `password`, and it is what stands between port `1517`
  and an unwanted registration. A deployment that is reachable before you get to it has been
  reachable with a documented password.
- Nothing is lost by doing it up front. Neither value survives on its own in a persistent volume:
  both are rewritten from the Secret at every container start, which is also why **deleting the
  PersistentVolumeClaims does not return them to the defaults**, unlike the indexer and Wazuh API
  passwords.

The step is in Installation, placed before the deployment is applied, in both guides:
[EKS](getting-started/installation.md#step-332-set-the-cluster-key-and-the-agent-enrollment-password)
and [local](getting-started/installation.md#set-the-cluster-key-and-the-agent-enrollment-password).

### Changing them on a deployment that is already running

Both follow the same shape: edit the manifest, apply the overlay, restart the managers. Neither
reaches a running pod on its own: the cluster key is read into the environment when the container
starts, and `authd.pass` is a `subPath` mount, which Kubernetes never refreshes in place. The restart
is what applies them.

#### The agent enrollment password

This one can be done at any time. Encode the new password without a trailing newline:

```bash
echo -n '<new enrollment password>' | base64
```

Write it into `wazuh/secrets/wazuh-authd-pass-secret.yaml` under `authd.pass`, then apply and restart:

```bash
kubectl apply -k envs/local-env/   # or envs/eks/
kubectl -n wazuh rollout restart statefulset/wazuh-manager-master
kubectl -n wazuh rollout restart statefulset/wazuh-manager-worker
kubectl -n wazuh rollout status statefulset/wazuh-manager-master
kubectl -n wazuh rollout status statefulset/wazuh-manager-worker
```

Confirm it landed:

```bash
kubectl -n wazuh exec wazuh-manager-master-0 -- cat /var/wazuh-manager/etc/authd.pass
```

Agents that are already enrolled keep working: they authenticate with the key in `client.keys`, not
with this password. Only enrollments from this point on have to present the new one, so update
whatever provisions your agents — for a containerized agent, the `WAZUH_REGISTRATION_PASSWORD`
variable.

#### The cluster key

The key has to be 32 characters, as the shipped default is:

```bash
openssl rand -hex 16
```

Write it into `wazuh/secrets/wazuh-cluster-key-secret.yaml` under `key`, then apply and restart
**both** manager StatefulSets in one go:

```bash
kubectl apply -k envs/local-env/   # or envs/eks/
kubectl -n wazuh rollout restart statefulset/wazuh-manager-master statefulset/wazuh-manager-worker
kubectl -n wazuh rollout status statefulset/wazuh-manager-master
kubectl -n wazuh rollout status statefulset/wazuh-manager-worker
```

> **Warning**: until every manager pod has restarted, the ones still on the old key cannot sync with
> the master. Agent events are not lost — the workers keep receiving and queueing them — but the
> cluster is degraded for the length of the restart, so do this in a maintenance window on a
> production deployment.

Confirm the new key is in place on each node and that the workers rejoined:

```bash
kubectl -n wazuh exec wazuh-manager-master-0 -- \
  grep '<key>' /var/wazuh-manager/etc/wazuh-manager.conf
kubectl -n wazuh logs statefulset/wazuh-manager-worker --tail=50 | grep -i cluster
```

A worker whose key does not match logs the failure to connect to the master, which is what to look
for if a pod comes back `Ready` but never syncs — the manager probes do not detect this, see
[Notes](#notes).

> **Note**: `tools/tests/check-default-credentials.sh` does not cover these two values. It checks the
> Wazuh indexer and Wazuh API accounts, which are the ones it can test by authenticating. Verify the
> cluster key and the enrollment password with the commands above.

## Multi-node deployments and scaling

**The indexer accounts are cluster-wide.** Run the tool on any indexer pod and the change reaches
every replica, because it is written to the shared security index.

**The Wazuh API accounts are not.** Each manager pod keeps its own `rbac.db` on its own persistent
volume and the cluster does not synchronize them. In the topology these manifests deploy that costs
nothing, because only the master serves the API: change the accounts there and the deployment is
rotated.

> **Important**: scaling the manager workers up later brings up a pod with a fresh persistent volume
> whose API user database is seeded from the image, defaults included. Those defaults authenticate
> nothing while the pod is a worker, but they are worth clearing with step 4 after
> `kubectl -n wazuh scale statefulset wazuh-manager-worker --replicas=<n>`. If you ever change the
> topology so that another pod serves the Wazuh API, its own database becomes live and step 4 stops
> being optional for it.

## Effect on the integration test suite

`tests/k8s_pytest.py` authenticates to the indexer as `wazuh-admin`. It defaults to the shipped
password, so after rotating you have to pass the new one:

```bash
pytest tests/k8s_pytest.py -v --deployment-type local \
  --indexer-user wazuh-admin --indexer-password '<the new wazuh-admin password>'
```

See [How to run the tests](../dev/run-tests.md).

## Checking that no default is left

```bash
tools/tests/check-default-credentials.sh
```

It asserts that the indexer carries none of the OpenSearch demo accounts and that no Wazuh indexer or
Wazuh API account authenticates with its own username as its password. **A deployment that has not
been through the procedure above fails this check**, which is what it is for.

```console
$ tools/tests/check-default-credentials.sh

The Wazuh indexer image
  ok    wazuh-indexer-0 does not ship the OpenSearch demo account 'anomalyadmin'
  ...

Wazuh indexer accounts (wazuh-indexer-0)
  ok    admin is refused with 'admin' as its password (HTTP 401)
  ...

Wazuh API accounts (wazuh-manager-master-0)
  ok    wazuh is refused with 'wazuh' as its password (HTTP 401)
  ok    wazuh-wui is refused with 'wazuh-wui' as its password (HTTP 401)

18 checks, all passed.
```

It authenticates from inside the pods, so it needs neither port-forwarding nor any published port.
Pass `-n` for a different namespace, `-i` and `-m` to name the indexer and manager pods explicitly.

## Notes

- The passwords live in the security index of the indexer and in the `rbac.db` of each manager pod,
  both on persistent volumes. **Deleting those PersistentVolumeClaims returns the deployment to the
  defaults**, and the procedure has to be repeated. On the `eks` overlay the StorageClass uses
  `reclaimPolicy: Retain`, so the underlying volumes survive a `kubectl delete -k`, but the local
  overlay may not.
- `password-tool.sh` writes no file and keeps no copy. A password that is lost is replaced, not
  recovered: run the tool again for that account.
- **The manager probes do not detect a credential mismatch.** `startupProbe`, `readinessProbe` and
  `livenessProbe` on the manager pods run `wazuh-manager-control status`, which reports on local
  daemons and never contacts the indexer. A manager that cannot authenticate stays `Ready` while
  failing to index. Confirm the connection from the logs, not from the pod status.
- The indexer accounts are `reserved`, so the security REST API refuses to modify them.
  `password-tool.sh` goes through `securityadmin` with the admin certificate the deployment already
  mounts at `/usr/share/wazuh-indexer/config/certs/admin.pem`, which is why it is the supported way
  to change them.
- `/securityadmin.sh` on its own is a different thing. With no arguments it uploads the whole security
  configuration of the image, replacing the one the cluster is running: every internal user that is
  not in the image is deleted, custom role mappings are reverted, and every password returns to the
  default of the image. Use it only when that is what you want.
- For production, consider an external secret manager integrated with Kubernetes instead of the
  committed Secret manifests. See [Security](security.md).
