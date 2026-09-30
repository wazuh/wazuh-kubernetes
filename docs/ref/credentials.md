# Credentials

The Wazuh images no longer ship a default password: each component generates or validates its own
credentials at install time and refuses to start without them
([wazuh/wazuh-indexer#1928](https://github.com/wazuh/wazuh-indexer/issues/1928)). This deployment's
part of that model is a pre-deployment step, `tools/utils/deployment/credentials-conf.sh`, run
**before** the first `kubectl apply -k` — the same shape as `certificates-conf.sh` for certificates.

Run it once, before deploying:

```bash
sudo bash tools/utils/deployment/certificates-conf.sh --cert --copy --priv
sudo bash tools/utils/deployment/credentials-conf.sh
kubectl apply -k envs/local-env/   # or envs/eks/
```

It writes `wazuh/config/credentials/{indexer,manager,dashboard}.env`, one file per component holding
only the keys that component needs. Kustomize's `secretGenerator` turns them into the
`indexer-credentials`, `manager-credentials` and `dashboard-credentials` Secrets that the pods read.
**It never overwrites an existing file**: once a deployment has started, the passwords it was given
are the ones that count, editing the file afterwards changes nothing running.

Needs `wazuh-credentials.sh` next to `wazuh-certs-tool.sh`, in the same version as the images. See
`credentials-conf.sh --help`.

## First access

```bash
grep '^WAZUH_INDEXER_ADMIN_PASSWORD=' wazuh/config/credentials/indexer.env | cut -d= -f2-
```

Log into the dashboard as `admin` with that value. It also produces a Wazuh API administrator session,
and it is the account the integration test suite authenticates with.

Two values are not accounts and are not covered by this: the manager cluster key and the agent
enrollment password. They stay exactly as before — set from Secret manifests in this repository,
**before** the first deployment. See
[The cluster key and the agent enrollment password](#the-cluster-key-and-the-agent-enrollment-password).

## The accounts

Two components hold accounts, in separate databases reached over separate ports.

### Wazuh indexer

These live in the security plugin's internal user database, inside the security index. They are
cluster-wide: a change made on one indexer pod reaches all of them.

| Account | Owned by | Secret | Key | Consumed by | What it is for |
| --- | --- | --- | --- | --- | --- |
| `admin` | Indexer | `indexer-credentials` | `WAZUH_INDEXER_ADMIN_PASSWORD` | Indexer | Administrator of the indexer: every index, the cluster settings and the security configuration. Logging into the dashboard as `admin` also produces a Wazuh API administrator session. |
| `kibanaserver` | Indexer | `indexer-credentials`, `dashboard-credentials` | `WAZUH_INDEXER_KIBANASERVER_PASSWORD` | Indexer, `wazuh-dashboard` | Service account the dashboard authenticates to the indexer as. |
| `wazuh-manager` | Indexer | `indexer-credentials`, `manager-credentials` | `WAZUH_INDEXER_MANAGER_PASSWORD` | Indexer, `wazuh-manager-master`, `wazuh-manager-worker` | Service account the managers write events and read state as. |

> **wazuh-admin, wazuh-readonly and wazuh-demo do not ship in 5.0.0.** They were discretionary
> accounts of the previous internal-users layout; 5.0.0 ships only the three accounts above, none of
> them with a password baked into the image:
>
> ```console
> $ kubectl -n wazuh exec wazuh-indexer-0 -- \
>     curl -sk -u "admin:$(grep '^WAZUH_INDEXER_ADMIN_PASSWORD=' wazuh/config/credentials/indexer.env | cut -d= -f2-)" \
>     'https://localhost:9200/_plugins/_security/api/internalusers'
> admin  kibanaserver  wazuh-manager
> ```

The OpenSearch demo accounts (`anomalyadmin`, `kibanaro`, `logstash`, `readall`, `snapshotrestore`)
are **not** part of a Wazuh deployment either. They are removed from the indexer image when it is
built, so they do not exist and cannot be logged into.

### Wazuh manager

These live in the API's RBAC database, `rbac.db`, under
`/var/wazuh-manager/api/configuration/security/` on each manager node's persistent volume. **Seeded
only on the manager master** — the workers never serve the API (see
[Multi-node deployments and scaling](#multi-node-deployments-and-scaling)).

| Account | Owned by | Secret | Key | Consumed by | What it is for |
| --- | --- | --- | --- | --- | --- |
| `wazuh` | Manager | `manager-credentials` | `WAZUH_MANAGER_API_PASSWORD` | `wazuh-manager-master` | Superuser of the Wazuh API. |
| `wazuh-wui` | Manager | `manager-credentials`, `dashboard-credentials` | `WAZUH_MANAGER_WUI_PASSWORD` | `wazuh-manager-master`, `wazuh-dashboard` | Service account the dashboard proxies manager requests as. It asks the API to act as the logged-in dashboard user, so what a dashboard session can do is decided by that user's role, not by this account. |

> **A worker seeds no database at all while it stays a worker.** The manager's own credentials
> resolver checks `cluster.node_type` before deciding whether to seed `rbac.db`; only a promoted
> worker would seed it, from `config/credentials/manager.env` at that point. `rbac.db` being absent
> on a worker is therefore the expected, healthy state — `check-default-credentials.sh` treats it
> that way, not as a missed credential.

### Other secrets

Two more Secrets hold shared material rather than account passwords, out of scope for
`credentials-conf.sh` and for the install-time credential generation epic. Unchanged from before —
set by editing the manifest **before deploying**:
[The cluster key and the agent enrollment password](#the-cluster-key-and-the-agent-enrollment-password).

| Secret | Key | Default value | What it is for |
| --- | --- | --- | --- |
| `wazuh-authd-pass` | `authd.pass` | `password` | Enrollment password, mounted as a file into every manager pod. It guards the enrollment `remoted` serves on port `1517` and the legacy `authd` port `1515`. |
| `wazuh-cluster-key` | `key` | `REPLACETHISCLUSTERKEYBEFOREDEPLO` (placeholder) | Shared key for manager cluster membership, on port `1516`. |

## Rotating a password on a running deployment

Generation at first start is not rotation. To change a password on a deployment that has already
started, `password-tool.sh` (inside the indexer and manager images) is still the tool — it is the
only actor allowed to reconfigure a sibling component's credential. Recreating a pod is **not**
enough on its own: a component keeps the value it resolved on its first start, so a Secret update
without also going through the tool leaves the deployment split between the old and the new value.

### Wazuh indexer accounts

```bash
kubectl -n wazuh exec wazuh-indexer-0 -- /password-tool.sh --user admin
```

To choose the password instead of having one generated, pass it on standard input:

```bash
printf '%s\n' '<NewPassword.1>' | \
  kubectl -n wazuh exec -i wazuh-indexer-0 -- /password-tool.sh --user admin --stdin
```

A password must be 12 to 64 characters and contain an upper case letter, a lower case letter, a digit
and one of `. , _ + : @ % ^ = ~ -`.

Any indexer pod works: the change is written to the security index, shared by the whole indexer
cluster, so `admin` takes effect immediately. `kibanaserver` and `wazuh-manager` are also consumed by
another workload (the dashboard and the managers respectively) — after changing either, update
`wazuh/config/credentials/{dashboard,manager}.env` with the same value, re-apply the overlay, and
restart the pods that consume it (see [Step 3](#step-3-restart-the-workloads-that-consume-it) below),
or the deployment splits: the indexer accepts the new password, the workload keeps presenting the old
one.

### Wazuh API accounts

Has to run on the manager master, the only node whose `rbac.db` is live:

```bash
kubectl -n wazuh exec wazuh-manager-master-0 -- /password-tool.sh --user wazuh-wui
```

`wazuh-wui` is also consumed by the dashboard — the same "update the `.env`, re-apply, restart" gap
as `kibanaserver`/`wazuh-manager` above applies here too.

### Step 3: restart the workloads that consume it

A Secret consumed with `valueFrom.secretKeyRef` is read into the environment when the container
starts. Until the pods are restarted they keep presenting the old password:

```bash
kubectl apply -k envs/local-env/   # or envs/eks/
kubectl -n wazuh rollout restart statefulset/wazuh-manager-master
kubectl -n wazuh rollout restart statefulset/wazuh-manager-worker
kubectl -n wazuh rollout restart deployment/wazuh-dashboard
kubectl -n wazuh rollout status statefulset/wazuh-manager-master
kubectl -n wazuh rollout status statefulset/wazuh-manager-worker
kubectl -n wazuh rollout status deployment/wazuh-dashboard
```

The indexer pods need no restart for their own accounts changing: that happened in the security
index, not in their environment.

> **Note**: between changing the password and finishing the restart above, the consuming workload
> authenticates with a value that no longer works. That gap is unavoidable. Keep it short, and see
> the warning about the manager probes under [Notes](#notes).

## The cluster key and the agent enrollment password

`wazuh-cluster-key` and `wazuh-authd-pass` work differently from every account above. They are not
rows in a database inside an image: the managers take them from the Secret on **every container
start**, `WAZUH_CLUSTER_KEY` into `<cluster><key>` of `/var/wazuh-manager/etc/wazuh-manager.conf` and
`authd.pass` into the file `/var/wazuh-manager/etc/authd.pass`. `password-tool.sh` has nothing to do
with them; changing one is a matter of editing the manifest and restarting the managers.

| Secret | Key | Default value | Read by | What it protects |
| --- | --- | --- | --- | --- |
| `wazuh-cluster-key` | `key` | `REPLACETHISCLUSTERKEYBEFOREDEPLO` (placeholder) | `wazuh-manager-master`, `wazuh-manager-worker` | Membership of the Wazuh manager cluster on port `1516`. A node whose key does not match the master's cannot join it. |
| `wazuh-authd-pass` | `authd.pass` | `password` | `wazuh-manager-master`, `wazuh-manager-worker` | Agent enrollment: the channel `remoted` serves on port `1517` on every node, and the legacy `authd` port `1515` on the master. |

### Set them before the first deployment

**These two belong in the installation, alongside `credentials-conf.sh`, not after the pods come
up.**

- Nothing has to be running: the values come from the manifests, not from a database inside a pod.
- **Changing the cluster key on a running deployment interrupts the cluster.** Every manager node has
  to carry the same key, and a restart that does not cover all of them at once leaves workers on the
  old key while the master is already on the new one; they cannot sync until each pod has restarted.
- The default enrollment password is the string `password`, and it is what stands between port `1517`
  and an unwanted registration. A deployment that is reachable before you get to it has been
  reachable with a documented password.
- Neither value survives on its own in a persistent volume: both are rewritten from the Secret at
  every container start, which is also why **deleting the PersistentVolumeClaims does not return
  them to a default**, unlike the accounts above.

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

The key has to be exactly 32 alphanumeric characters, as the shipped placeholder is.
`openssl rand -hex 16` produces exactly that; any other length or character makes the managers refuse
to start:

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

**The indexer accounts are cluster-wide.** A change reaches every replica, because it is written to
the shared security index.

**The Wazuh API accounts are not.** Each manager pod keeps its own `rbac.db` on its own persistent
volume and the cluster does not synchronize it. In the topology these manifests deploy that costs
nothing, because only the master serves the API.

> **Important**: a freshly scaled-up worker seeds no `rbac.db` at all — see the note under
> [Wazuh manager](#wazuh-manager). If you later change the topology so this pod serves the API
> instead of the master, promoting it seeds its database from `config/credentials/manager.env` at
> that point; only then does step-by-step reconciliation of its `rbac.db` become relevant.

## Effect on the integration test suite

`tests/k8s_pytest.py` authenticates to the indexer as `admin`. Pass the generated password:

```bash
pytest tests/k8s_pytest.py -v --deployment-type local \
  --indexer-user admin --indexer-password "$(grep '^WAZUH_INDEXER_ADMIN_PASSWORD=' wazuh/config/credentials/indexer.env | cut -d= -f2-)"
```

See [How to run the tests](../dev/run-tests.md).

## Checking that no default is left

```bash
tools/tests/check-default-credentials.sh
```

It asserts that the indexer carries none of the OpenSearch demo accounts and that every account
authenticates with its generated password rather than with its own username. **A deployment that
skipped `credentials-conf.sh` before its first start refuses to start at all**, so this check is
about confirming resolution succeeded and stayed consistent, not about catching a shipped default —
there no longer is one.

It authenticates from inside the pods, so it needs neither port-forwarding nor any published port.
Pass `-n` for a different namespace, `-i` and `-m` to name the indexer and manager pods explicitly.

## Notes

- The passwords live in the security index of the indexer and in the `rbac.db` of each manager pod,
  both on persistent volumes. **Deleting those PersistentVolumeClaims makes the pod resolve its
  credentials again from the still-present Secret** — the same value as before, not a shipped
  default, since nothing generated at build time survives inside the image to fall back to. Deleting
  the Secret too (or the whole `config/credentials/` directory before it is recreated) is what would
  force brand-new values on the next `credentials-conf.sh` run.
- `password-tool.sh` writes no file on its own and keeps no copy of what it prints; the copy that
  matters afterwards is what you write into `config/credentials/*.env`. A password that is lost
  without having been recorded there is replaced, not recovered: run the tool again for that account.
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
  not in the image is deleted, custom role mappings are reverted, and every password returns to
  whatever `internal_users.yml` currently holds on that node. Use it only when that is what you want.
- For production, consider an external secret manager integrated with Kubernetes instead of the
  generated `config/credentials/` files. See [Security](security.md).
