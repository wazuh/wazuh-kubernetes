#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $DIR

echo "Root CA"

openssl genrsa -out root-ca-key.pem 2048

openssl req -days 3650 -new -x509 -sha256 -key root-ca-key.pem -out root-ca.pem -subj "/C=US/L=California/O=Company/CN=root-ca"

echo "Admin cert"

echo "create: admin-key-temp.pem"

openssl genrsa -out admin-key-temp.pem 2048

echo "create: admin-key.pem"

openssl pkcs8 -inform PEM -outform PEM -in admin-key-temp.pem -topk8 -nocrypt -v1 PBE-SHA1-3DES -out admin-key.pem

echo "create: admin.csr"

openssl req -days 3650 -new -key admin-key.pem -out admin.csr -subj "/C=US/L=California/O=Company/CN=admin"

echo "create: admin.pem"

openssl x509 -req -days 3650 -in admin.csr -CA root-ca.pem -CAkey root-ca-key.pem -CAcreateserial -sha256 -out admin.pem


echo "* Node cert"

echo "create: node-key-temp.pem"

openssl genrsa -out node-key-temp.pem 2048

echo "create: node-key.pem"

openssl pkcs8 -inform PEM -outform PEM -in node-key-temp.pem -topk8 -nocrypt -v1 PBE-SHA1-3DES -out node-key.pem

echo "create: node.csr"

openssl req -days 3650 -new -key node-key.pem -out node.csr -subj "/C=US/L=California/O=Company/CN=*.wazuh-indexer"

echo "create: node.pem"

openssl x509 -req -days 3650 -in node.csr -CA root-ca.pem -CAkey root-ca-key.pem -CAcreateserial -sha256 -out node.pem

echo "* dashboard cert"

echo "create: dashboard-key-temp.pem"

openssl genrsa -out dashboard-key-temp.pem 2048

echo "create: dashboard-key.pem"

openssl pkcs8 -inform PEM -outform PEM -in dashboard-key-temp.pem -topk8 -nocrypt -v1 PBE-SHA1-3DES -out dashboard-key.pem

echo "create: dashboard.csr"

openssl req -days 3650 -new -key dashboard-key.pem -out dashboard.csr -subj "/C=US/L=California/O=Company/CN=dashboard"

echo "create: dashboard.pem"

openssl x509 -req -days 3650 -in dashboard.csr -CA root-ca.pem -CAkey root-ca-key.pem -CAcreateserial -sha256 -out dashboard.pem



echo "* Filebeat cert"

echo "create: filebeat-key-temp.pem"

openssl genrsa -out filebeat-key-temp.pem 2048

echo "create: filebeat-key.pem"

openssl pkcs8 -inform PEM -outform PEM -in filebeat-key-temp.pem -topk8 -nocrypt -v1 PBE-SHA1-3DES -out filebeat-key.pem

echo "create: filebeat.csr"

openssl req -days 3650 -new -key filebeat-key.pem -out filebeat.csr -subj "/C=US/L=California/O=Company/CN=filebeat"

echo "create: filebeat.pem"

openssl x509 -req -days 3650 -in filebeat.csr -CA root-ca.pem -CAkey root-ca-key.pem -CAcreateserial -sha256 -out filebeat.pem
