1- Review reclaim-policy of the PV associated with opendistro, it has to be "Retain"
```
$ kubectl get pv | grep wazuh-elasticsearch
pvc-9a42ac59-262e-4580-9fd8-eff0f02fedbb   10Gi       RWO            Retain           Released   wazuh/wazuh-elasticsearch-wazuh-elasticsearch-1     wazuh-storage            8m24s
pvc-b5bea50d-e6e0-48d8-a743-faa42885a7bb   10Gi       RWO            Retain           Released   wazuh/wazuh-elasticsearch-wazuh-elasticsearch-2     wazuh-storage            7m45s
pvc-f6f02274-bac1-4c30-8108-dcdedbf891c8   10Gi       RWO            Retain           Released   wazuh/wazuh-elasticsearch-wazuh-elasticsearch-0     wazuh-storage            9m14s
```

Save the output data since we will use the names of the PVs

2- Remove all objects from the Wazuh namespace. The namespace can be deleted directly or all the objects created with the repository deploy can be deleted, to do this we stop at the root of the wazuh-kubernetes repository, in the version that we have installed and execute the following command:
```
$ kubectl delete -k envs/eks/
namespace "wazuh" deleted
storageclass.storage.k8s.io "wazuh-storage" deleted
configmap "dashboard-conf-gc2hkg4tff" deleted
configmap "indexer-conf-765k99m7g8" deleted
configmap "wazuh-conf-9hf9g2fgk8" deleted
secret "dashboard-certs-5ccmm6hth4" deleted
secret "dashboard-cred" deleted
secret "indexer-certs-mkggcttfcf" deleted
secret "indexer-cred" deleted
service "dashboard" deleted
service "indexer" deleted
service "wazuh" deleted
service "wazuh-workers" deleted
Error from server (NotFound): error when deleting "envs/eks/": secrets "wazuh-api-cred" not found
Error from server (NotFound): error when deleting "envs/eks/": secrets "wazuh-authd-pass" not found
Error from server (NotFound): error when deleting "envs/eks/": secrets "wazuh-cluster-key" not found
Error from server (NotFound): error when deleting "envs/eks/": services "wazuh-cluster" not found
Error from server (NotFound): error when deleting "envs/eks/": services "wazuh-indexer" not found
Error from server (NotFound): error when deleting "envs/eks/": deployments.apps "wazuh-dashboard" not found
Error from server (NotFound): error when deleting "envs/eks/": statefulsets.apps "wazuh-indexer" not found
Error from server (NotFound): error when deleting "envs/eks/": statefulsets.apps "wazuh-manager-master" not found
Error from server (NotFound): error when deleting "envs/eks/": statefulsets.apps "wazuh-manager-worker" not found
```

3- Modify the metadata of the PVs associated with the opendistro PVCs so that they go from Released to Available
```
kubectl patch pv pvc-9a42ac59-262e-4580-9fd8-eff0f02fedbb --type json -p '[{"op": "remove", "path": "/spec/claimRef"}]'
kubectl patch pv pvc-b5bea50d-e6e0-48d8-a743-faa42885a7bb --type json -p '[{"op": "remove", "path": "/spec/claimRef"}]'
kubectl patch pv pvc-f6f02274-bac1-4c30-8108-dcdedbf891c8 --type json -p '[{"op": "remove", "path": "/spec/claimRef"}]'
```

4- Eliminate or disassemble all the PVs in Available state that are in the cluster, so that the distribution of the PVs at the time of the new deploy is consistent.

5- From the wazuh-kubernetes repository, in the new version (v4.3.4) perform the new deploy.

6- Verify that the PVs that we had maintained from the previous deploy are the same ones assigned to indexer, with the same node number
```
$ kubectl get pv | grep wazuh-indexer
pvc-b5bea50d-e6e0-48d8-a743-faa42885a7bb   10Gi       RWO            Retain           Bound       wazuh/wazuh-indexer-wazuh-indexer-2                 wazuh-storage            4h1m
pvc-f6f02274-bac1-4c30-8108-dcdedbf891c8   10Gi       RWO            Retain           Bound       wazuh/wazuh-indexer-wazuh-indexer-0                 wazuh-storage            4h
pvc-9a42ac59-262e-4580-9fd8-eff0f02fedbb   10Gi       RWO            Retain           Bound       wazuh/wazuh-indexer-wazuh-indexer-1                 wazuh-storage            4h1m
```

7- Check the status of the pods
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