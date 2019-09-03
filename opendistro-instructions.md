## Deploying Wazuh + ELK with Opendistro Security in K8S



### Objective

The main goal is to be able to set up a Wazuh cluster of managers working with Elastic Stack components using certificates to securitize the communications.

We will deploy a testing/dev environment, some of the configurations are not completely secure, please check the security notes.

### Installation and Setup

The following steps detail the process required to set up the whole environment.



#### Certificates considerations

To secure the communication between Wazuh and ELK, the different components will use the certificates we will generate.

An important point is that Filebeat and Kibana default configuration check the certificate and the hostname as the default verification mode is set to `full`. To perform the `full` verification, the Common Name (CN) needs to match the hostname of the Elasticsearch nodes.

When generating the ES certificate (node.pem) we will explicitly set the CN=elasticsearch.



#### Certificates generation

- Generate the CA

  ```
  openssl genrsa -out root-ca-key.pem 2048
  openssl req -new -x509 -sha256 -key root-ca-key.pem -out root-ca.pem
  ```

  

- Generate the Admin certificate (**admin.pem**)

  ```bash
  openssl genrsa -out admin-key-temp.pem 2048
  openssl pkcs8 -inform PEM -outform PEM -in admin-key-temp.pem -topk8 -nocrypt -v1 PBE-SHA1-3DES -out admin-key.pem
  openssl req -new -key admin-key.pem -subj "/C=US/ST=CA/O=MyOrganization/CN=MyDomain.com" -out admin.csr
  openssl x509 -req -in admin.csr -CA root-ca.pem -CAkey root-ca-key.pem -CAcreateserial -sha256 -out admin.pem
  ```

  

- Generate the ES certificate (**node.pem**)

  ```bash
  openssl genrsa -out node-key-temp.pem 2048
  openssl pkcs8 -inform PEM -outform PEM -in node-key-temp.pem -topk8 -nocrypt -v1 PBE-SHA1-3DES -out node-key.pem
  openssl req -new -key node-key.pem -subj "/C=US/ST=CA/O=MyOrganization2/CN=elasticsearch" -out node.csr
  openssl x509 -req -in node.csr -CA root-ca.pem -CAkey root-ca-key.pem -CAcreateserial -sha256 -out node.pem
  ```

  ​	 *Note:* Feel free to edit the subject to fit your needs. You can remove the `-subj` parameter to make the configuration interactive.

  ​    **Important**: Note the `CN=elasticsearch" we mentioned before.

  

- Generate the Kibana certificate (**node2.pem**)

  ```bash
  openssl genrsa -out node-key2-temp.pem 2048
  openssl pkcs8 -inform PEM -outform PEM -in node-key2-temp.pem -topk8 -nocrypt -v1 PBE-SHA1-3DES -out node-key2.pem
  openssl req -new -key node-key2.pem -subj "/C=US/ST=CA/O=MyOrganization3/CN=kibana" -out node2.csr
  openssl x509 -req -in node2.csr -CA root-ca.pem -CAkey root-ca-key.pem -CAcreateserial -sha256 -out node2.pem
  ```



#### Obtain certificates subject

Let's get the certificates subject that we will use later

- Admin

  ```bash
  $ openssl x509 -subject -nameopt RFC2253 -noout -in admin.pem
  ```

   In my case outputs: *subject=CN=MyDomain.com,O=MyOrganization,ST=CA,C=US* 

  We will need the whole line from CN to configure our ES and Kibana later

- ES

  ```bash
  openssl x509 -subject -nameopt RFC2253 -noout -in node.pem
  ```

- Kibana

  ```bash
  openssl x509 -subject -nameopt RFC2253 -noout -in node2.pem
  ```



#### Configure elasticsearch.yml

The elasticsearch.yml is configured in K8S by using a ConfigMap located in */elasticsearch/elasticsearch-conf.yaml*



```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: elasticsearch-config
  namespace: wazuh
data:
  elasticsearch.yml: |-
    opendistro_security.ssl.transport.pemcert_filepath: /usr/share/elasticsearch/config/node.pem
    opendistro_security.ssl.transport.pemkey_filepath: /usr/share/elasticsearch/config/node-key.pem
    opendistro_security.ssl.transport.pemtrustedcas_filepath: /usr/share/elasticsearch/config/root-ca.pem
    opendistro_security.ssl.transport.enforce_hostname_verification: false
    opendistro_security.ssl.http.enabled: true
    opendistro_security.ssl.http.pemcert_filepath: /usr/share/elasticsearch/config/node.pem
    opendistro_security.ssl.http.pemkey_filepath: /usr/share/elasticsearch/config/node-key.pem
    opendistro_security.ssl.http.pemtrustedcas_filepath: /usr/share/elasticsearch/config/root-ca.pem
    opendistro_security.allow_default_init_securityindex: true
    opendistro_security.authcz.admin_dn:
      - CN=MyDomain.com,O=MyOrganization,ST=CA,C=US
    opendistro_security.nodes_dn:
      - CN=elasticsearch,O=MyOrg2,ST=a,C=ES
      - CN=kibana,O=MyOrg22,ST=a,C=ES
    opendistro_security.audit.type: internal_elasticsearch
    opendistro_security.enable_snapshot_restore_privilege: true
    opendistro_security.check_snapshot_restore_write_privileges: true
    opendistro_security.restapi.roles_enabled: ["all_access", "security_rest_api_access"]
    cluster.routing.allocation.disk.threshold_enabled: false
    node.max_local_storage_nodes: 3
    opendistro_security.audit.config.disabled_rest_categories: NONE
    opendistro_security.audit.config.disabled_transport_categories: NONE
    

```

Configure the subjects of the certificates under`opendistro_security.authcz.admin_dn:` and `opendistro_security.nodes_dn` to match your previously obtained subjects (**do not** include the `subject=` prefix)

The rest of the settings are set to default, including the ES certificates path.



 #### Configure kibana.yml

The kibana.yml is configured in K8S by using a ConfigMap located in */kibana/kibana-conf.yaml*



```yaml
server.name: kibana
server.host: "0"
elasticsearch.hosts: https://elasticsearch:9200
elasticsearch.username: admin
elasticsearch.password: admin

elasticsearch.requestHeadersWhitelist: ["securitytenant","Authorization"]

opendistro_security.multitenancy.enabled: false
opendistro_security.multitenancy.tenants.preferred: ["Private", "Global"]
server.ssl.enabled: true
server.ssl.certificate: /usr/share/kibana/config/node2.pem
server.ssl.key: /usr/share/kibana/config/node-key2.pem

opendistro_security.allow_client_certificates: true
elasticsearch.ssl.certificate: /usr/share/kibana/config/node2.pem
elasticsearch.ssl.key: /usr/share/kibana/config/node-key2.pem

elasticsearch.ssl.certificateAuthorities: ["/usr/share/kibana/config/root-ca.pem"]
elasticsearch.ssl.verificationMode: full
```



**Security note:** The user is `admin` , this is not recommended for production environments as it may cause security issues (also there is a well-known issue with multitenancy when using admin, that's why it's disabled). 

You can configure your user following [Users and Roles](https://www.google.com/url?sa=t&rct=j&q=&esrc=s&source=web&cd=1&cad=rja&uact=8&ved=2ahUKEwj4nZ739LTkAhWQEBQKHYNsD8oQFjAAegQIAxAB&url=https%3A%2F%2Fopendistro.github.io%2Ffor-elasticsearch-docs%2Fdocs%2Falerting%2Fsecurity-roles%2F&usg=AOvVaw2GqjvLNXo4ReORIu6tu7yD) guide of OD.

The `elasticsearch.hosts` contains the default hostname of the Docker images we will use.



 #### Configure filebeat.yml

The filebeat.yml file is declared in */wazuh_managers/filebeat-conf.yaml* 

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: filebeat-config
  namespace: wazuh
data:
  filebeat.yml: |-    
    # Wazuh - Filebeat configuration file
    filebeat.modules:
      - module: wazuh
        alerts:
          enabled: true
        archives:
          enabled: false

    setup.template.json.enabled: true
    setup.template.json.path: '/etc/filebeat/wazuh-template.json'
    setup.template.json.name: 'wazuh'
    setup.template.overwrite: true
    setup.ilm.enabled: false
    output.elasticsearch:
      hosts: ['http://elasticsearch:9200']
      #ssl.certificate_authorities:
      #username:
      #password:
```



As you can see the `hosts` is already configured and the `ssl.certificate_authorities`, the `username` and the `password` can be set using the corresponding environment variables in every Wazuh Manager StatefulSet.

An example of `wazuh-master-sts.yaml`

https://github.com/wazuh/wazuh-kubernetes/blob/a1dcfe5d66b6868a34dfa8519105d1527ba14724/wazuh_managers/wazuh-master-sts.yaml#L51-L59

This way you can easily configure any parameter you need by just setting the associated env variable.



#### Configuring secrets

In order to load our local certificates in the pods we setup, we need to create a secret for each component that will store the certificate content.

There are three secrets by default:

- */wazuh_managers/filebeat-secret.yaml*
- */elastic_stack/elasticsearch/elasticsearch-secret.yaml*

- */kibana/kibana-secret.yaml*



Simply copy the content of the previously generated certs in the secret.

https://github.com/wazuh/wazuh-kubernetes/blob/a1dcfe5d66b6868a34dfa8519105d1527ba14724/elastic_stack/elasticsearch/elasticsearch-secret.yaml#L1-L17

**Security Note:** These certs are encrypted in base64 which is not secure, further security measures are required in order to securely manage the certs.



### Preparing the Docker images

There is a **prepared branch** to work with this Kubernetes configuration in our [Wazuh Docker repository](https://github.com/wazuh/wazuh-docker/tree/centos-openssl-fips)



Pull the stated branch and compile the images:

```
git clone https://github.com/wazuh/wazuh-docker
git checkout centos-openssl-fips
docker-compose build
```

If you execute `docker image list` you should see the following images:

![image](https://user-images.githubusercontent.com/46649922/64194844-5e048100-ce80-11e9-9e41-1339db20fb4c.png)


You can execute this directly on your node or create the images in your host and export them with:

 ```
docker save -o <path for generated tar file> <image name>
 ```

And after importing them in the desired node you can load them with:

```
docker load -i <path to image tar file>
```


### Configure Kibana HTTPS

To access Kibana using, you need to provide a certificate ARN in the */kibana/kibana-svc.yaml*

```
arn:aws:acm:us-east-1:111222333444:certificate/c69f6022-b24f-43d9-b9c8-dfe288d9443d
```



Substitute this with the ARN of your AWS certificate.

### Deploying

So we have our configuration files ready and the images properly load on the node.

To deploy the whole installation you can get the detailed deploy information in the [Deploy instructions](https://github.com/wazuh/wazuh-kubernetes/blob/docker-centos-fips/instructions.md)



If you want to go forward and execute all the deploy, navigate to your wazuh-kubernetes folder and run:

```

kubectl apply -f base/wazuh-ns.yaml
kubectl apply -f base/aws-gp2-storage-class.yaml

kubectl apply -f elastic_stack/elasticsearch/elasticsearch-svc.yaml
kubectl apply -f elastic_stack/elasticsearch/single-node/elasticsearch-api-svc.yaml
kubectl apply -f elastic_stack/elasticsearch/elasticsearch-secret.yaml
kubectl apply -f elastic_stack/elasticsearch/elasticsearch-conf.yaml
kubectl apply -f elastic_stack/elasticsearch/single-node/elasticsearch-sts.yaml


kubectl apply -f elastic_stack/kibana/kibana-svc.yaml
kubectl apply -f elastic_stack/kibana/kibana-secret.yaml
kubectl apply -f elastic_stack/kibana/kibana-conf.yaml
kubectl apply -f elastic_stack/kibana/kibana-deploy.yaml

kubectl apply -f wazuh_managers/wazuh-master-svc.yaml
kubectl apply -f wazuh_managers/wazuh-cluster-svc.yaml
kubectl apply -f wazuh_managers/wazuh-workers-svc.yaml

kubectl apply -f wazuh_managers/filebeat-secret.yaml
kubectl apply -f wazuh_managers/filebeat-conf.yaml
kubectl apply -f wazuh_managers/wazuh-master-conf.yaml
kubectl apply -f wazuh_managers/wazuh-worker-0-conf.yaml
kubectl apply -f wazuh_managers/wazuh-worker-1-conf.yaml

kubectl apply -f wazuh_managers/wazuh-master-sts.yaml
kubectl apply -f wazuh_managers/wazuh-worker-0-sts.yaml
kubectl apply -f wazuh_managers/wazuh-worker-1-sts.yaml
```



After the deploying you can verify that everything worked fine by executing:

```
kubectl get namespaces | grep wazuh
kubectl get services -n wazuh
kubectl get deployments -n wazuh
kubectl get statefulsets -n wazuh
kubectl get pods -n wazuh
kubectl get persistentvolumeclaim -n wazuh
kubectl get persistentvolume -n wazuh
```



You should get something like the following:

![2019-09-03_19-09](https://user-images.githubusercontent.com/46649922/64194892-72e11480-ce80-11e9-9582-204fb1849396.png)


Pay special attention to `READY`, `STATUS` and `RESTARTS` , your output should be the same if you didn't change the replicas.



### Accessing Kibana

Get your Kibana LoadBalancer IP by executing:

```
kubectl get svc -n wazuh
```

To access Kibana, copy the `EXTERNAL-IP` of the Kibana Loadbalancer obtained and , with your browser, navigate to it (remember to use https://).

Also, copy the Wazuh `EXTENAL-IP` as we will use lately to setup our Wazuh API

![opendistro_welcome_screen](https://user-images.githubusercontent.com/46649922/64195027-be93be00-ce80-11e9-89d1-e93f5ed88b87.png)


Insert the credentials defined in *kibana.yml *, by default **admin:admin**  and you will be logged into Kibana.

Go to the Wazuh App and insert the credentials for the Wazuh API, by default:

- Username: *foo*
- Password: *bar*
- URL: *http://<YOUR_WAZUH_EXTERNAL-IP>*
- Port: *55000*

And that's it, all the setup and configuration is completed and you can navigate through the alerts and dashboards.

![image](https://user-images.githubusercontent.com/46649922/64195160-13cfcf80-ce81-11e9-9984-fff6c60d2a4f.png)


### References

- https://kubernetes.io/docs/concepts/configuration/secret/

- https://opendistro.github.io/for-elasticsearch-docs/docs/security-configuration/generate-certificates/#generate-an-admin-certificatev

- https://aws.amazon.com/blogs/opensource/open-distro-for-elasticsearch-on-kubernetes/





































