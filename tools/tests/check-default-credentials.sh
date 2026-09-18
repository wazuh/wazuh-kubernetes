#!/bin/bash
# Wazuh Kubernetes Copyright (C) 2019, Wazuh Inc. (License GPLv2)
#
# Asserts that no account of a deployment authenticates with its own username
# as its password, and that the Wazuh indexer image carries none of the
# OpenSearch demo accounts.
#
# The images ship documented default passwords, so a deployment that has not
# been through the first-deployment password change fails this check. That is
# what it is for: see docs/ref/credentials.md.

set -o pipefail

NAMESPACE="wazuh"
INDEXER_POD=""
MANAGER_POD=""

# Accounts OpenSearch ships for its demo configuration. None of them has a role
# in a Wazuh deployment and the image must not contain them at all.
DEMO_USERS="anomalyadmin kibanaro logstash readall snapshotrestore"

# Accounts the Wazuh indexer image keeps.
INDEXER_USERS="admin kibanaserver wazuh-manager wazuh-admin wazuh-readonly wazuh-demo"

# Accounts the Wazuh API seeds its user database with.
API_USERS="wazuh wazuh-wui"

INTERNAL_USERS_FILE="/usr/share/wazuh-indexer/config/opensearch-security/internal_users.yml"

failures=0
checks=0

pass() { checks=$((checks + 1)); printf '  \033[32mok\033[0m    %s\n' "$1"; }
fail() { checks=$((checks + 1)); failures=$((failures + 1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; }
info() { printf '%s\n' "$1"; }

usage() {
  cat <<USAGE
Usage: check-default-credentials.sh [options]

  -n, --namespace <namespace>   Namespace of the deployment. Default: wazuh
  -i, --indexer-pod <pod>       Indexer pod. Default: the first pod labelled
                                app=wazuh-indexer
  -m, --manager-pod <pod>       Manager pod to reach the Wazuh API on. Default:
                                the first pod labelled
                                app=wazuh-manager,node-type=master
  -h, --help                    Show this help.

Everything is checked from inside the pods, so no published port and no
port-forward is needed. See docs/ref/credentials.md.
USAGE
}

while [ -n "$1" ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -n|--namespace) NAMESPACE="$2"; shift 2 ;;
    -i|--indexer-pod) INDEXER_POD="$2"; shift 2 ;;
    -m|--manager-pod) MANAGER_POD="$2"; shift 2 ;;
    *) usage >&2; exit 2 ;;
  esac
done

if ! command -v kubectl >/dev/null 2>&1; then
  echo "check-default-credentials: kubectl not found." >&2
  exit 2
fi

if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "check-default-credentials: namespace '${NAMESPACE}' not found. Pass --namespace." >&2
  exit 2
fi

# Resolves the name of the first pod matching a label selector.
first_pod() {
  kubectl -n "${NAMESPACE}" get pods -l "$1" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

[ -n "${INDEXER_POD}" ] || INDEXER_POD=$(first_pod 'app=wazuh-indexer')
[ -n "${MANAGER_POD}" ] || MANAGER_POD=$(first_pod 'app=wazuh-manager,node-type=master')

if [ -z "${INDEXER_POD}" ]; then
  echo "check-default-credentials: no pod labelled app=wazuh-indexer in '${NAMESPACE}'." >&2
  echo "check-default-credentials: pass --indexer-pod to name it explicitly." >&2
  exit 2
fi

if [ -z "${MANAGER_POD}" ]; then
  echo "check-default-credentials: no pod labelled app=wazuh-manager,node-type=master in '${NAMESPACE}'." >&2
  echo "check-default-credentials: pass --manager-pod to name it explicitly." >&2
  exit 2
fi

# Authenticates from inside the indexer pod, so the check does not need port
# 9200 to be reachable from outside the cluster, and cannot be made to pass by
# exposing it.
indexer_auth_code() {
  kubectl -n "${NAMESPACE}" exec "${INDEXER_POD}" -- \
    curl -sk -o /dev/null -w '%{http_code}' --max-time 15 \
    -u "$1:$2" 'https://localhost:9200/_plugins/_security/authinfo' 2>/dev/null
}

# POST, which is the method the endpoint accepts: a GET answers 405 whatever the
# credentials are, and a check that cannot tell a good password from a bad one is
# worse than no check.
api_auth_code() {
  kubectl -n "${NAMESPACE}" exec "${MANAGER_POD}" -- \
    curl -sk -o /dev/null -w '%{http_code}' --max-time 15 -X POST \
    -u "$1:$2" 'https://localhost:55000/security/user/authenticate' 2>/dev/null
}

################################################################################
info ""
info "The Wazuh indexer image"
################################################################################

# The user database in the image, not the one the cluster is running:
# password-tool.sh patches the security index and leaves this file alone, so it
# still shows what the image shipped.
users_file=$(kubectl -n "${NAMESPACE}" exec "${INDEXER_POD}" -- \
  cat "${INTERNAL_USERS_FILE}" 2>/dev/null)

if [ -z "${users_file}" ]; then
  fail "could not read ${INTERNAL_USERS_FILE} from ${INDEXER_POD}"
else
  for user in ${DEMO_USERS}; do
    if echo "${users_file}" | grep -q "^${user}:"; then
      fail "${INDEXER_POD} still ships the OpenSearch demo account '${user}'"
    else
      pass "${INDEXER_POD} does not ship the OpenSearch demo account '${user}'"
    fi
  done
fi

################################################################################
info ""
info "Wazuh indexer accounts (${INDEXER_POD})"
################################################################################

for user in ${INDEXER_USERS} ${DEMO_USERS}; do
  code=$(indexer_auth_code "${user}" "${user}")
  if [ -z "${code}" ] || [ "${code}" = "000" ]; then
    # Everything here is a check that a password is refused, and a cluster that
    # answers nothing would pass all of them.
    fail "${INDEXER_POD} did not answer while checking '${user}'"
  elif [ "${code}" = "200" ]; then
    fail "${user} authenticates with '${user}' as its password"
  else
    pass "${user} is refused with '${user}' as its password (HTTP ${code})"
  fi
done

################################################################################
info ""
info "Wazuh API accounts (${MANAGER_POD})"
################################################################################

for user in ${API_USERS}; do
  code=$(api_auth_code "${user}" "${user}")
  if [ -z "${code}" ] || [ "${code}" = "000" ]; then
    fail "no answer from the Wazuh API on ${MANAGER_POD} while checking '${user}'; the API is served by the manager master only"
  elif [ "${code}" = "200" ]; then
    fail "${user} authenticates with '${user}' as its password"
  else
    pass "${user} is refused with '${user}' as its password (HTTP ${code})"
  fi
done

info ""
info "The Wazuh API is served by the manager master only, so ${MANAGER_POD} is the"
info "node whose user database authenticates requests. Worker pods run no API and"
info "answer nothing on port 55000; pointing --manager-pod at one reports no answer."

info ""
if [ "${failures}" -eq 0 ]; then
  info "${checks} checks, all passed."
  exit 0
fi
info "${checks} checks, ${failures} failed."
info "A deployment that has not been through the first-deployment password change fails here."
info "See docs/ref/credentials.md."
exit 1
