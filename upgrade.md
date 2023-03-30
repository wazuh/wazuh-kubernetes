# Wazuh Upgrade

When upgrading our version of Wazuh installed in Kubernetes we must follow the following steps.

## Check which files are exported to the volume

Our Kubernetes deployment uses our Wazuh images from Docker. If we look at the following code extracted from the Wazuh configuration using Docker we can see which directories and files are used in the upgrades.

```
PERMANENT_DATA[((i++))]="/var/ossec/api/configuration"
PERMANENT_DATA[((i++))]="/var/ossec/etc"
PERMANENT_DATA[((i++))]="/var/ossec/logs"
PERMANENT_DATA[((i++))]="/var/ossec/queue"
PERMANENT_DATA[((i++))]="/var/ossec/agentless"
PERMANENT_DATA[((i++))]="/var/ossec/var/multigroups"
PERMANENT_DATA[((i++))]="/var/ossec/integrations"
PERMANENT_DATA[((i++))]="/var/ossec/active-response/bin"
PERMANENT_DATA[((i++))]="/var/ossec/wodles"
PERMANENT_DATA[((i++))]="/etc/filebeat"
```

Any file that we modify referring to the files previously mentioned, will be changed also the corresponding volume. When the corresponding Wazuh pod is created again, it will get the cited files from the volume, thus keeping the changes made previously.

To better understand it, we will give an example:

We have our newly created Kubernetes environment following our instructions. In this example, the image of Wazuh used has been `wazuh/wazuh:3.13.1_7.8.0`.

```
containers:
- name: wazuh-manager
  image: 'wazuh/wazuh:3.13.2_7.9.1'
```

Let's proceed by creating a set of rules in our `local_rules.xml` file at location `/var/ossec/etc/rules` in our wazuh manager master pod.

```
root@wazuh-manager-master-0:/# vim /var/ossec/etc/rules/local_rules.xml
root@wazuh-manager-master-0:/# cat /var/ossec/etc/rules/local_rules.xml
<!-- Local rules -->

<!-- Modify it at your will. -->

<!-- Example -->
<group name="local,syslog,sshd,">

  <!--
  Dec 10 01:02:02 host sshd[1234]: Failed none for root from 1.1.1.1 port 1066 ssh2
  -->
  <rule id="100001" level="5">
    <if_sid>5716</if_sid>
    <srcip>1.1.1.1</srcip>
    <description>sshd: authentication failed from IP 1.1.1.1.</description>
    <group>authentication_failed,pci_dss_10.2.4,pci_dss_10.2.5,</group>
  </rule>

  <rule id="100002" level="5">
    <if_sid>5716</if_sid>
    <srcip>2.1.1.1</srcip>
    <description>sshd: authentication failed from IP 2.1.1.1.</description>
    <group>authentication_failed,pci_dss_10.2.4,pci_dss_10.2.5,</group>
  </rule>

  <rule id="100003" level="7">
    <if_sid>5716</if_sid>
    <srcip>3.1.1.1</srcip>
    <description>sshd: authentication failed from IP 3.1.1.1.</description>
    <group>authentication_failed,pci_dss_10.2.4,pci_dss_10.2.5,</group>
  </rule>

</group>

```

This action has modified the `local_rules.xml` file in the `/var/ossec/data/etc/rules` path and in the `/etc/postfix/etc/` rules path due these routes reference our volume assembly points.

```
volumeMounts:
- name: config
  mountPath: /wazuh-config-mount/etc/ossec.conf
  subPath: ossec.conf
  readOnly: true
- name: wazuh-manager-master
  mountPath: /var/ossec/data
- name: wazuh-manager-master
  mountPath: /etc/postfix
```

We can see their content.

```
root@wazuh-manager-master-0:/# cat /var/ossec/data/etc/rules/local_rules.xml
<!-- Local rules -->

<!-- Modify it at your will. -->

<!-- Example -->
<group name="local,syslog,sshd,">

  <!--
  Dec 10 01:02:02 host sshd[1234]: Failed none for root from 1.1.1.1 port 1066 ssh2
  -->
  <rule id="100001" level="5">
    <if_sid>5716</if_sid>
    <srcip>1.1.1.1</srcip>
    <description>sshd: authentication failed from IP 1.1.1.1.</description>
    <group>authentication_failed,pci_dss_10.2.4,pci_dss_10.2.5,</group>
  </rule>

  <rule id="100002" level="5">
    <if_sid>5716</if_sid>
    <srcip>2.1.1.1</srcip>
    <description>sshd: authentication failed from IP 2.1.1.1.</description>
    <group>authentication_failed,pci_dss_10.2.4,pci_dss_10.2.5,</group>
  </rule>

  <rule id="100003" level="7">
    <if_sid>5716</if_sid>
    <srcip>3.1.1.1</srcip>
    <description>sshd: authentication failed from IP 3.1.1.1.</description>
    <group>authentication_failed,pci_dss_10.2.4,pci_dss_10.2.5,</group>
  </rule>

</group>
root@wazuh-manager-master-0:/# cat /etc/postfix/etc/rules/local_rules.xml
<!-- Local rules -->

<!-- Modify it at your will. -->

<!-- Example -->
<group name="local,syslog,sshd,">

  <!--
  Dec 10 01:02:02 host sshd[1234]: Failed none for root from 1.1.1.1 port 1066 ssh2
  -->
  <rule id="100001" level="5">
    <if_sid>5716</if_sid>
    <srcip>1.1.1.1</srcip>
    <description>sshd: authentication failed from IP 1.1.1.1.</description>
    <group>authentication_failed,pci_dss_10.2.4,pci_dss_10.2.5,</group>
  </rule>

  <rule id="100002" level="5">
    <if_sid>5716</if_sid>
    <srcip>2.1.1.1</srcip>
    <description>sshd: authentication failed from IP 2.1.1.1.</description>
    <group>authentication_failed,pci_dss_10.2.4,pci_dss_10.2.5,</group>
  </rule>

  <rule id="100003" level="7">
    <if_sid>5716</if_sid>
    <srcip>3.1.1.1</srcip>
    <description>sshd: authentication failed from IP 3.1.1.1.</description>
    <group>authentication_failed,pci_dss_10.2.4,pci_dss_10.2.5,</group>
  </rule>

</group>

```

At this point, if the pod was dropped or updated, Kubernetes would be in charge of creating a replica of it that would link to the volumes created and would maintain any changes referenced in the files and directories that we export to those volumes.

Once explained the operation regarding the volumes, we proceed to update Wazuh in two simple steps.

## 1. Change the image of the container

The first step is to change the image of the pod in each file that deploys each node of the Wazuh cluster.

These files are the statefulSet files:
- wazuh-master-sts.yaml
- wazuh-worker-sts.yaml

For example we had this version before:

```
containers:
- name: wazuh-manager
  image: 'wazuh/wazuh:3.13.1_7.8.0'
```

And now we're going to upgrade to the next version:

```
containers:
- name: wazuh-manager
  image: 'wazuh/wazuh:3.13.2_7.9.1'
```


## 2. Apply the new configuration

The second and last step is to apply the new configuration of each pod. For example for the wazuh manager master:

```
ubuntu@k8s-control-server:~/wazuh-kubernetes/manager_cluster$ kubectl apply -f wazuh-manager-master-sts.yaml
statefulset.apps "wazuh-manager-master" configured
```

This process will end the old pod while creating a new one with the new version, linked to the same volume. Once the Pods are booted, we will have our update ready and we can check the new version of Wazuh installed, the cluster and the changes that have been maintained through the use of the volumes.

### Note: It is important to update all Wazuh node pods, because the cluster only works when all nodes have the same version.
