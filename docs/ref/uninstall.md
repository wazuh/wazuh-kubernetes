# Clean up

Steps to perform a clean up of our deployments, services and volumes used in our environment.

## Delete the cluster

To delete your Wazuh cluster just use `kubectl delete -k envs/<ENVIRONMENT>` from this repository directory (being `<ENVIRONMENT>` one of `eks` or `local-env`).

`kubectl delete -k` renders the kustomization first, so it needs `wazuh/config/` in place: the
certificates and `credentials/*.env`. If they are gone, delete the namespace instead:

```sh
kubectl delete namespace wazuh
```

Deleting the namespace also removes every Secret in it, including the `*-credentials-<hash>` Secrets
left behind by earlier rotations, which `kubectl delete -k` does not know about.

## Delete Traefik Ingress Controller

To remove the Traefik Ingress Controller, run the following command from your repository directory:

```sh
kubectl delete -k traefik/runtime/
kubectl delete -f traefik/crd/kubernetes-crd-definition-v1.yml
```

## Delete the persistent volumes manually

The EKS overlay uses `reclaimPolicy: Retain` in its storage class (`local-env` uses `Delete`), so on EKS you must delete volumes manually if you want to clean these as well.

```console
kubectl get persistentvolume
```

And then delete persistent volumes using:

```console
kubectl delete persistentvolume <PV_NAME>
```

This removes only the Kubernetes object: the EBS volume stays, with the indexer security index, the
Wazuh API user database and the keystores. Note its ID before deleting the PersistentVolume, and
delete it with the AWS CLI:

```console
kubectl get persistentvolume -o custom-columns=PV:.metadata.name,CLAIM:.spec.claimRef.name,EBS:.spec.awsElasticBlockStore.volumeID
aws ec2 delete-volume --volume-id <EBS_VOLUME_ID>
```

A new deployment does not bind the `Released` volumes: it starts with empty ones.

On a local cluster with `reclaimPolicy: Delete`, the volumes go away with their claims, but check
that their data did too before deploying again. Minikube's hostpath provisioner keeps each claim in
a directory named after it, and a deployment applied right after the uninstall can find the previous
data there, with the previous passwords: the indexer then refuses the new ones (`Unauthorized`).

```console
minikube ssh -- sudo ls /tmp/hostpath-provisioner/wazuh
minikube ssh -- sudo rm -rf /tmp/hostpath-provisioner/wazuh
```

Expected output:

```console
ubuntu@k8s-control-server:~$ kubectl get persistentvolume
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS        CLAIM                                                         STORAGECLASS             REASON    AGE
pvc-1e20762a-c38c-425f-a37b-32cfe967dc5e   1Gi        RWO            Retain           Released      wazuh/wazuh-dashboard-config                                  wazuh-storage                      6d
pvc-4d0253bd-114a-46a2-94f4-75e41ca85c1a   10Gi       RWO            Retain           Released      wazuh/wazuh-indexer-wazuh-indexer-1                           wazuh-storage                      6d
pvc-8a1f3c55-2b7e-4d61-9c0e-5f3a2d1b7c90   50Gi       RWO            Retain           Released      wazuh/wazuh-manager-master-wazuh-manager-master-0             wazuh-storage                      6d
pvc-b3226ad3-f7c4-11e8-b9b8-022ada63b4ac   50Gi       RWO            Retain           Released      wazuh/wazuh-manager-worker-wazuh-manager-worker-0             wazuh-storage                      6d
```

```console
ubuntu@k8s-control-server:~$ kubectl delete persistentvolume pvc-b3226ad3-f7c4-11e8-b9b8-022ada63b4ac
```

## Delete the local files

`wazuh/config/credentials/*.env` and `wazuh/wazuh-certificates/` stay on disk, with the passwords
and the private keys in clear text. Delete them, or keep them if you are going to restore the
volumes. `credentials-conf.sh` refuses to run while the credentials files exist (`--force` replaces
them, for a deployment that has never been started).

Once these steps are completed, our Wazuh deployment will have been removed from the Kubernetes environment.
