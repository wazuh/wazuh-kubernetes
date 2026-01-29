
# Verifying the deployment

## Namespace

```bash
kubectl get namespaces | grep wazuh
```

Expected output:

```bash
$ kubectl get namespaces | grep wazuh
wazuh         Active    12m
```

## Services

```bash
kubectl get services -n wazuh
```

Expected output:

```bash
$ kubectl get services -n wazuh
NAME                 TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)             AGE
dashboard            ClusterIP   10.100.196.140   <none>        443/TCP             23m
wazuh-api            ClusterIP   10.100.58.98     <none>        55000/TCP           23m
wazuh-cluster        ClusterIP   None             <none>        1516/TCP            23m
wazuh-events         ClusterIP   10.100.63.117    <none>        1514/TCP            23m
wazuh-indexer        ClusterIP   None             <none>        9300/TCP,9200/TCP   23m
wazuh-registration   ClusterIP   10.100.40.83     <none>        1515/TCP            23m

```

## Deployments

```bash
kubectl get deployments -n wazuh
```

Expected output:

```bash
$ kubectl get deployments -n wazuh
NAME              READY   UP-TO-DATE   AVAILABLE   AGE
wazuh-dashboard   1/1     1            1           4h16m
```

## Statefulsets

```bash
kubectl get statefulsets -n wazuh
```

Expected output:

```bash
$ kubectl get statefulsets -n wazuh
NAME                   READY   AGE
wazuh-indexer          3/3     4h17m
wazuh-manager-master   1/1     4h17m
wazuh-manager-worker   2/2     4h17m
```

## Pods

```bash
kubectl get pods -n wazuh
```

Expected output:

```bash
$ kubectl get pods -n wazuh
NAME                               READY   STATUS    RESTARTS   AGE
wazuh-dashboard-57d455f894-ffwsk   1/1     Running   0          4h17m
wazuh-indexer-0                    1/1     Running   0          4h17m
wazuh-indexer-1                    1/1     Running   0          4h17m
wazuh-indexer-2                    1/1     Running   0          4h17m
wazuh-manager-master-0             1/1     Running   0          4h17m
wazuh-manager-worker-0             1/1     Running   0          4h17m
wazuh-manager-worker-1             1/1     Running   0          4h17m
```

## Network Policies

```bash
kubectl -n wazuh get networkpolicy
```

Expected output:

```bash
$ kubectl -n wazuh get networkpolicy
NAME                              POD-SELECTOR                         AGE
allow-dns                         <none>                               51s
allow-ingress-to-dashboard        app=wazuh-dashboard                  50s
allow-ingress-to-manager-master   app=wazuh-manager,node-type=master   49s
allow-ingress-to-manager-worker   app=wazuh-manager,node-type=worker   48s
dashboard-egress                  app=wazuh-dashboard                  47s
default-deny-all                  <none>                               46s
indexer-egress                    app=wazuh-indexer                    45s
indexer-ingress                   app=wazuh-indexer                    44s
manager-egress                    app=wazuh-manager,node-type=master   43s
manager-egress-external           app=wazuh-manager                    42s
wazuh-api-ingress                 app=wazuh-manager,node-type=master   42s
wazuh-worker-egress               app=wazuh-manager,node-type=worker   41s
```

## Accessing Wazuh dashboard

In case you created domain names for the services, you should be able to access Wazuh dashboard using the proposed domain name: <https://wazuh.your-domain.com>.

Also, you can access using the External-IP (from the VPC): <https://xxx-yyy-zzz.us-east-1.elb.amazonaws.com:443>

```bash
kubectl -n ingress-nginx get svc
```

Expected output:

```bash
$ kubectl -n ingress-nginx get svc
NAME                                 TYPE           CLUSTER-IP      EXTERNAL-IP                                                                     PORT(S)                                                    AGE
ingress-nginx-controller             LoadBalancer   10.100.228.67   a0c363db4315d484fa38751820a9e89b-e1811181631efef0.elb.us-west-1.amazonaws.com   80:30561/TCP,443:32533/TCP,1514:31784/TCP,1515:31274/TCP   36s
ingress-nginx-controller-admission   ClusterIP      10.100.118.85   <none>                                                                          443/TCP                                                    35s
```
