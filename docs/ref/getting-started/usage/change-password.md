# Change the password of Wazuh users

Improve security by changing default passwords for Wazuh users. There are two categories of Wazuh users:

## Wazuh indexer users

Before starting the password change process, log out of your Wazuh dashboard session. Failing to do so might result in errors when accessing Wazuh after changing user passwords due to persistent session cookies.

To change the password of the default `admin` and `kibanaserver` users, do the following.

Warning: If you have custom users, add them to the `internal_users.yml` file. Otherwise, executing this procedure deletes them.

### Set a new password hash

Start a `Bash` shell in the `wazuh-indexer-0` pod.

```sh
kubectl exec -it wazuh-indexer-0 -n wazuh -- /bin/bash
```

Run these commands to generate the hash of your new password. When prompted, input the new password and press Enter.

```sh
export JAVA_HOME=/usr/share/wazuh-indexer/jdk
bash /usr/share/wazuh-indexer/plugins/opensearch-security/tools/hash.sh
```
Warning: Do not use the `$` or `&` characters in your new password. These characters can cause errors during deployment.

### Copy the generated hash and exit the Bash shell.

Open the `wazuh/indexer_stack/wazuh-indexer/indexer_conf/internal_users.yml` file. Locate the block for the user whose password you want to change and replace the hash:

#### admin user


```yaml
admin:
    hash: "<ADMIN_PASSWORD_HASH>"
    reserved: true
    backend_roles:
    - "admin"
    description: "Demo admin user"
```

Replace <ADMIN_PASSWORD_HASH> with the password hash generated in the previous step.

#### kibanaserver user

```yaml
kibanaserver:
    hash: "<KIBANASERVER_PASSWORD_HASH>"
    reserved: true
    description: "Demo kibanaserver user"
```

Replace <KIBANASERVER_PASSWORD_HASH> with the password hash generated in the previous step.

### Setting the new password

Encode your new password in `base64` format. Use the -n option with the echo command as follows to avoid inserting a trailing newline character to maintain the hash value.

```sh
echo -n "<NEW_PASSWORD>" | base64
```

Replace the variable <NEW_PASSWORD> with your password.

Edit the indexer or dashbboard secrets configuration file as follows. Replace the value of the password field with the `base64` encoded password.

To change the `admin` user password, edit the `wazuh/secrets/indexer-cred-secret.yaml` file.


```yaml
apiVersion: v1
kind: Secret
metadata:
    name: indexer-cred
data:
    username: YWRtaW4=              # string "admin" base64 encoded
    password: <NEW_PASSWORD>  # Paste the string of the base64 encoded password
```

To change the `kibanaserver` user password, edit the `wazuh/secrets/dashboard-cred-secret.yaml` file.


```yaml
apiVersion: v1
kind: Secret
metadata:
    name: dashboard-cred
data:
    username: a2liYW5hc2VydmVy  # string "kibanaserver" base64 encoded
    password: a2liYW5hc2VydmVy  # string "kibanaserver" base64 encoded
```

### Applying the changes

Apply the manifest changes

#### EKS cluster

```sh
kubectl apply -k envs/eks/
```

#### Other cluster types

```sh
kubectl apply -k envs/local-env/
```

Start a new Bash shell in the `wazuh-indexer-0` pod.

```yaml
kubectl exec -it wazuh-indexer-0 -n wazuh -- /bin/bash
```

Set the following variables:

```sh
export INSTALLATION_DIR=/usr/share/wazuh-indexer
export CONFIG_DIR=$INSTALLATION_DIR/config
CACERT=$CONFIG_DIR/certs/root-ca.pem
KEY=$CONFIG_DIR/certs/admin-key.pem
CERT=$CONFIG_DIR/certs/admin.pem
export JAVA_HOME=/usr/share/wazuh-indexer/jdk
```

Wait for the Wazuh indexer to initialize properly. The waiting time can vary from two to five minutes. It depends on the size of the cluster, the assigned resources, and the speed of the network. Then, run the `securityadmin.sh` script to apply all changes.

```sh
bash /usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh -cd $CONFIG_DIR/opensearch-security/ -nhnv -cacert  $CACERT -cert $CERT -key $KEY -p 9200 -icl -h $NODE_NAME
exit
```

Force the Wazuh dashboard deployment rollout to update the component credentials.

```sh
kubectl rollout restart deploy/wazuh-dashboard -n wazuh
```

Delete all Wazuh manager pods to update the component credentials.

```sh
kubectl delete -n wazuh pod/wazuh-manager-master-0 pod/wazuh-manager-worker-0 pod/wazuh-manager-worker-1
```

Log in to the Wazuh dashboard using the new credentials.

## Wazuh server API users

The `wazuh-wui` user is the default user used to connect to the Wazuh server API. Follow the steps below to change the password.

Note: The password for Wazuh server API users must be between 8 and 64 characters long. It must contain at least one uppercase and one lowercase letter, a number, and a symbol.

Encode your new password in `base64` format. Use the `-n` option with the echo command as follows to avoid inserting a trailing newline character to maintain the hash value.

```sh
echo -n "<NEW_PASSWORD>" | base64
```
Replace the variable <NEW_PASSWORD> with your password.

Edit the `wazuh/secrets/wazuh-api-cred-secret.yaml` file and replace the value of the password field.

```yaml
apiVersion: v1
kind: Secret
metadata:
    name: wazuh-api-cred
    namespace: wazuh
data:
    username: d2F6dWgtd3Vp          # string "wazuh-wui" base64 encoded
    password: <NEW_PASSWORD>  # Paste the string of the base64 encoded password
```

Apply the manifest changes.

```sh
kubectl apply -k envs/eks/
```

Force the Wazuh dashboard deployment rollout to update the component credentials.

```sh
kubectl rollout restart deploy/wazuh-dashboard -n wazuh
```

Delete all Wazuh manager pods to update the component credentials.

```sh
kubectl delete -n wazuh pod/wazuh-manager-master-0 pod/wazuh-manager-worker-0 pod/wazuh-manager-worker-1
```