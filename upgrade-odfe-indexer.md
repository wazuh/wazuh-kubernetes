1- Review reclaim-policy of the PV associated with opendistro, it has to be "Retain"
```
$ kubectl get pv
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS     CLAIM                                               STORAGECLASS    REASON   AGE
pvc-0e2cf63d-ef72-4ab5-bf4a-c73ac01c0bd2   10Gi       RWO            Retain           Bound   wazuh/wazuh-elasticsearch-wazuh-elasticsearch-2     wazuh-storage            39m
pvc-22edfa15-ef80-4130-8763-1ab6c28ce4a8   10Gi       RWO            Retain           Bound   wazuh/wazuh-elasticsearch-wazuh-elasticsearch-1     wazuh-storage            39m
pvc-6fd06423-03c2-4374-bf03-7ec95d8711ab   50Gi       RWO            Retain           Bound   wazuh/wazuh-manager-worker-wazuh-manager-worker-0   wazuh-storage            39m
pvc-9e8b31f7-e367-4986-957b-18017d21962b   50Gi       RWO            Retain           Bound   wazuh/wazuh-manager-master-wazuh-manager-master-0   wazuh-storage            39m
pvc-c12830dd-626c-4713-b7cf-fc078b178be3   10Gi       RWO            Retain           Bound   wazuh/wazuh-elasticsearch-wazuh-elasticsearch-0     wazuh-storage            40m
pvc-e10af5fc-de0d-4cbc-8899-e244905108b1   50Gi       RWO            Retain           Bound   wazuh/wazuh-manager-worker-wazuh-manager-worker-1   wazuh-storage            39m
```

Save the output data since we will use the names of the PVs

2- Extract yaml metadata for all PVCs in the namespace
```
kubectl get pvc wazuh-elasticsearch-wazuh-elasticsearch-0 -n wazuh -o yaml
kubectl get pvc wazuh-elasticsearch-wazuh-elasticsearch-1 -n wazuh -o yaml
kubectl get pvc wazuh-elasticsearch-wazuh-elasticsearch-2 -n wazuh -o yaml
kubectl get pvc wazuh-manager-master-wazuh-manager-master-0 -n wazuh -o yaml
kubectl get pvc wazuh-manager-worker-wazuh-manager-worker-0 -n wazuh -o yaml
kubectl get pvc wazuh-manager-worker-wazuh-manager-worker-1 -n wazuh -o yaml
```
Save that scripts because we need this data in steps forward

3- Remove all objects from the Wazuh namespace. The namespace can be deleted directly or all the objects created with the repository deploy can be deleted, to do this we stop at the root of the wazuh-kubernetes repository, in the version that we have installed and execute the following command:
```
$ kubectl delete -k envs/eks/
namespace "wazuh" deleted
storageclass.storage.k8s.io "wazuh-storage" deleted
configmap "dashboard-conf-gc2hkg4tff" deleted
configmap "indexer-conf-765k99m7g8" deleted
configmap "wazuh-conf-9hf9g2fgk8" deleted
secret "dashboard-certs-5ccmm6hth4" deleted
secret "dashboard-cred" deleted
...
```

4- Modify the metadata of the PVs associated with the opendistro PVCs so that they go from Released to Available
```
kubectl patch pv pvc-c12830dd-626c-4713-b7cf-fc078b178be3 --type json -p '[{"op": "remove", "path": "/spec/claimRef"}]'
kubectl patch pv pvc-22edfa15-ef80-4130-8763-1ab6c28ce4a8 --type json -p '[{"op": "remove", "path": "/spec/claimRef"}]'
kubectl patch pv pvc-0e2cf63d-ef72-4ab5-bf4a-c73ac01c0bd2 --type json -p '[{"op": "remove", "path": "/spec/claimRef"}]'
kubectl patch pv pvc-9e8b31f7-e367-4986-957b-18017d21962b --type json -p '[{"op": "remove", "path": "/spec/claimRef"}]'
kubectl patch pv pvc-6fd06423-03c2-4374-bf03-7ec95d8711ab --type json -p '[{"op": "remove", "path": "/spec/claimRef"}]'
kubectl patch pv pvc-e10af5fc-de0d-4cbc-8899-e244905108b1 --type json -p '[{"op": "remove", "path": "/spec/claimRef"}]'
```

5- Create a new wazuh's namespace
```
kubectl create ns wazuh
```

6- Create yaml scripts for each pvc using the ones provided bellow

pvc-indexer-0.yml
```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  annotations:
    pv.kubernetes.io/bind-completed: "yes"
    pv.kubernetes.io/bound-by-controller: "yes"
    volume.beta.kubernetes.io/storage-provisioner: kubernetes.io/aws-ebs
    volume.kubernetes.io/selected-node: ip-192-168-2-187.us-west-1.compute.internal
  finalizers:
  - kubernetes.io/pvc-protection
  labels:
    app: wazuh-indexer
  name: wazuh-indexer-wazuh-indexer-0
  namespace: wazuh
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: wazuh-storage
  volumeMode: Filesystem
  volumeName: pvc-c12830dd-626c-4713-b7cf-fc078b178be3
```
pvc-indexer-1.yml
```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  annotations:
    pv.kubernetes.io/bind-completed: "yes"
    pv.kubernetes.io/bound-by-controller: "yes"
    volume.beta.kubernetes.io/storage-provisioner: kubernetes.io/aws-ebs
    volume.kubernetes.io/selected-node: ip-192-168-38-176.us-west-1.compute.internal
  finalizers:
  - kubernetes.io/pvc-protection
  labels:
    app: wazuh-indexer
  name: wazuh-indexer-wazuh-indexer-1
  namespace: wazuh
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: wazuh-storage
  volumeMode: Filesystem
  volumeName: pvc-22edfa15-ef80-4130-8763-1ab6c28ce4a8
```
pvc-indexer-2.yml
```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  annotations:
    pv.kubernetes.io/bind-completed: "yes"
    pv.kubernetes.io/bound-by-controller: "yes"
    volume.beta.kubernetes.io/storage-provisioner: kubernetes.io/aws-ebs
    volume.kubernetes.io/selected-node: ip-192-168-6-43.us-west-1.compute.internal
  finalizers:
  - kubernetes.io/pvc-protection
  labels:
    app: wazuh-indexer
  name: wazuh-indexer-wazuh-indexer-2
  namespace: wazuh
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: wazuh-storage
  volumeMode: Filesystem
  volumeName: pvc-0e2cf63d-ef72-4ab5-bf4a-c73ac01c0bd2
```
pvc-master-0.yml
```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  annotations:
    pv.kubernetes.io/bind-completed: "yes"
    pv.kubernetes.io/bound-by-controller: "yes"
    volume.beta.kubernetes.io/storage-provisioner: kubernetes.io/aws-ebs
    volume.kubernetes.io/selected-node: ip-192-168-38-176.us-west-1.compute.internal
  finalizers:
  - kubernetes.io/pvc-protection
  labels:
    app: wazuh-manager
    node-type: master
  name: wazuh-manager-master-wazuh-manager-master-0
  namespace: wazuh
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
  storageClassName: wazuh-storage
  volumeMode: Filesystem
  volumeName: pvc-9e8b31f7-e367-4986-957b-18017d21962b
```
pvc-worker-0.yml
```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  annotations:
    pv.kubernetes.io/bind-completed: "yes"
    pv.kubernetes.io/bound-by-controller: "yes"
    volume.beta.kubernetes.io/storage-provisioner: kubernetes.io/aws-ebs
    volume.kubernetes.io/selected-node: ip-192-168-6-43.us-west-1.compute.internal
  finalizers:
  - kubernetes.io/pvc-protection
  labels:
    app: wazuh-manager
    node-type: worker
  name: wazuh-manager-worker-wazuh-manager-worker-0
  namespace: wazuh
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
  storageClassName: wazuh-storage
  volumeMode: Filesystem
  volumeName: pvc-6fd06423-03c2-4374-bf03-7ec95d8711ab
```
pvc-worker-0.yml
```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  annotations:
    pv.kubernetes.io/bind-completed: "yes"
    pv.kubernetes.io/bound-by-controller: "yes"
    volume.beta.kubernetes.io/storage-provisioner: kubernetes.io/aws-ebs
    volume.kubernetes.io/selected-node: ip-192-168-2-187.us-west-1.compute.internal
  finalizers:
  - kubernetes.io/pvc-protection
  labels:
    app: wazuh-manager
    node-type: worker
  name: wazuh-manager-worker-wazuh-manager-worker-1
  namespace: wazuh
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
  storageClassName: wazuh-storage
  volumeMode: Filesystem
  volumeName: pvc-e10af5fc-de0d-4cbc-8899-e244905108b1
```

7- Modify the `annotations` and `volumeName` with the data from the scripts in point 3.

The data correlation between the 4.2 PVCs and the new 4.3 PVCs is as follows:
```
wazuh-elasticsearch-wazuh-elasticsearch-0 --> wazuh-indexer-wazuh-indexer-0
wazuh-elasticsearch-wazuh-elasticsearch-1 --> wazuh-indexer-wazuh-indexer-1
wazuh-elasticsearch-wazuh-elasticsearch-2 --> wazuh-indexer-wazuh-indexer-2
wazuh-manager-master-wazuh-manager-master-0 --> wazuh-manager-master-wazuh-manager-master-0
wazuh-manager-worker-wazuh-manager-worker-0 --> wazuh-manager-worker-wazuh-manager-worker-0
wazuh-manager-worker-wazuh-manager-worker-1 --> wazuh-manager-worker-wazuh-manager-worker-1
```

These are the scripts to create:

apply these manifests on the wazuh namespace
```
kubectl apply -f pvc-indexer-0.yml
kubectl apply -f pvc-indexer-1.yml
kubectl apply -f pvc-indexer-2.yml
kubectl apply -f pvc-master-0.yml
kubectl apply -f pvc-worker-0.yml
kubectl apply -f pvc-worker-1.yml
```

7- Verify that the PVs and PVCs are created and correctly assigned
```
$ kubectl get pv
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                                               STORAGECLASS    REASON   AGE
pvc-0e2cf63d-ef72-4ab5-bf4a-c73ac01c0bd2   10Gi       RWO            Retain           Bound    wazuh/wazuh-indexer-wazuh-indexer-2                 wazuh-storage            100m
pvc-22edfa15-ef80-4130-8763-1ab6c28ce4a8   10Gi       RWO            Retain           Bound    wazuh/wazuh-indexer-wazuh-indexer-1                 wazuh-storage            100m
pvc-6fd06423-03c2-4374-bf03-7ec95d8711ab   50Gi       RWO            Retain           Bound    wazuh/wazuh-manager-worker-wazuh-manager-worker-0   wazuh-storage            101m
pvc-9e8b31f7-e367-4986-957b-18017d21962b   50Gi       RWO            Retain           Bound    wazuh/wazuh-manager-master-wazuh-manager-master-0   wazuh-storage            101m
pvc-c12830dd-626c-4713-b7cf-fc078b178be3   10Gi       RWO            Retain           Bound    wazuh/wazuh-indexer-wazuh-indexer-0                 wazuh-storage            101m
pvc-e10af5fc-de0d-4cbc-8899-e244905108b1   50Gi       RWO            Retain           Bound    wazuh/wazuh-manager-worker-wazuh-manager-worker-1   wazuh-storage            101m
$ kubectl get pvc -n wazuh
NAME                                          STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS    AGE
wazuh-indexer-wazuh-indexer-0                 Bound    pvc-c12830dd-626c-4713-b7cf-fc078b178be3   10Gi       RWO            wazuh-storage   5m44s
wazuh-indexer-wazuh-indexer-1                 Bound    pvc-22edfa15-ef80-4130-8763-1ab6c28ce4a8   10Gi       RWO            wazuh-storage   50s
wazuh-indexer-wazuh-indexer-2                 Bound    pvc-0e2cf63d-ef72-4ab5-bf4a-c73ac01c0bd2   10Gi       RWO            wazuh-storage   44s
wazuh-manager-master-wazuh-manager-master-0   Bound    pvc-9e8b31f7-e367-4986-957b-18017d21962b   50Gi       RWO            wazuh-storage   31s
wazuh-manager-worker-wazuh-manager-worker-0   Bound    pvc-6fd06423-03c2-4374-bf03-7ec95d8711ab   50Gi       RWO            wazuh-storage   24s
wazuh-manager-worker-wazuh-manager-worker-1   Bound    pvc-e10af5fc-de0d-4cbc-8899-e244905108b1   50Gi       RWO            wazuh-storage   19s
```

8- From the wazuh-kubernetes repository, in the new version (v4.3.4) perform the new deploy.

9- Check the status of the pods
```
$ kubectl get pods -n wazuh
NAME                               READY   STATUS    RESTARTS   AGE
wazuh-dashboard-7f7cbc64cd-rq26p   1/1     Running   0          4h20m
wazuh-indexer-0                    1/1     Running   0          4h20m
wazuh-indexer-1                    1/1     Running   0          4h20m
wazuh-indexer-2                    1/1     Running   0          4h20m
wazuh-manager-master-0             1/1     Running   0          4h20m
wazuh-manager-worker-0             1/1     Running   0          4h20m
wazuh-manager-worker-1             1/1     Running   0          4h20m
```

10- Modify file permissions within Wazuh manager pods
```
$ kubectl exec -it wazuh-manager-master-0 -n wazuh bash
root@wazuh-manager-master-0:/# find / -group 997 -exec chown :101 {} +
root@wazuh-manager-master-0:/# find / -user 999 -exec chown 101 {} +
root@wazuh-manager-master-0:/# exit
command terminated with exit code 1
$ kubectl exec -it wazuh-manager-worker-0 -n wazuh bash
root@wazuh-manager-worker-0:/# find / -group 997 -exec chown :101 {} +
root@wazuh-manager-worker-0:/# find / -user 999 -exec chown 101 {} +
root@wazuh-manager-worker-0:/# exit
command terminated with exit code 1
$ kubectl exec -it wazuh-manager-worker-1 -n wazuh bash
root@wazuh-manager-worker-1:/# find / -group 997 -exec chown :101 {} +
root@wazuh-manager-worker-1:/# find / -user 999 -exec chown 101 {} +
root@wazuh-manager-worker-1:/# exit
command terminated with exit code 1
```

11- Restart Wazuh manager pods
```
kubectl delete pod -n wazuh wazuh-manager-master-0
kubectl delete pod -n wazuh wazuh-manager-worker-0
kubectl delete pod -n wazuh wazuh-manager-worker-1
```