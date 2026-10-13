#!/bin/bash
# Wazuh Kubernetes Copyright (C) 2019, Wazuh Inc. (License GPLv2)
#
# Asserts that every account of a deployment authenticates with its generated
# password, that none of them authenticates with its own username as its
# password, that the Wazuh indexer image carries none of the OpenSearch demo
# accounts, and that every manager node runs on the generated cluster key.
#
# The packages refuse to start without a resolved credential, so a deployment
# that answers at all has already been through credentials-conf.sh and its
# first start. This check is about confirming resolution stayed consistent
# end to end, not about catching a shipped default: there no longer is one.
# See docs/ref/credentials.md.
 
set -o pipefail
 
NAMESPACE="wazuh"
INDEXER_POD=""
MANAGER_POD=""
CREDENTIALS_DIR="./config/credentials"
 
# Accounts OpenSearch ships for its demo configuration. None of them has a role
# in a Wazuh deployment and the image must not contain them at all.
DEMO_USERS="anomalyadmin kibanaro logstash readall snapshotrestore"
 
# Accounts the Wazuh indexer image keeps. wazuh-admin, wazuh-readonly and
# wazuh-demo do not ship in 5.0.0.
INDEXER_USERS="admin kibanaserver wazuh-manager"
 
# Accounts the Wazuh API seeds its user database with.
API_USERS="wazuh wazuh-internal-client"
 
INTERNAL_USERS_FILE="/usr/share/wazuh-indexer/config/opensearch-security/internal_users.yml"

# Value the cluster key Secret shipped with before credentials-conf.sh
# generated it.
CLUSTER_KEY_PLACEHOLDER="REPLACETHISCLUSTERKEYBEFOREDEPLO"
 
failures=0
checks=0
 
pass() { checks=$((checks + 1)); printf '  \033[32mok\033[0m    %s\n' "$1"; }
fail() { checks=$((checks + 1)); failures=$((failures + 1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; }
info() { printf '%s\n' "$1"; }
 
usage() {
  cat <<USAGE
Usage: check-default-credentials.sh [options]
 
  -n, --namespace <namespace>       Namespace of the deployment. Default: wazuh
  -i, --indexer-pod <pod>           Indexer pod. Default: the first pod labelled
                                    app=wazuh-indexer
  -m, --manager-pod <pod>           Manager pod to reach the Wazuh API on. Default:
                                    the first pod labelled
                                    app=wazuh-manager,node-type=master
  -c, --credentials-dir <dir>       Where credentials-conf.sh wrote indexer.env,
                                    manager.env, dashboard.env and cluster.key. Default:
                                    ${CREDENTIALS_DIR} (run this from the same
                                    directory as credentials-conf.sh, i.e. wazuh/)
  -h, --help                        Show this help.
 
Reads the generated passwords from the credentials-conf.sh output on disk, then
checks from inside the pods that every account authenticates with its own
generated password and with no other pod's copy of a shared one, and that none
of them still authenticates with its own username as its password. No published
port and no port-forward is needed.
 
See docs/ref/credentials.md.
USAGE
}
 
while [ -n "$1" ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -n|--namespace) NAMESPACE="$2"; shift 2 ;;
    -i|--indexer-pod) INDEXER_POD="$2"; shift 2 ;;
    -m|--manager-pod) MANAGER_POD="$2"; shift 2 ;;
    -c|--credentials-dir) CREDENTIALS_DIR="${2%/}"; shift 2 ;;
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
 
# Reads the values credentials-conf.sh wrote, so this checks the same
# passwords the deployment was actually given, not a guess at them.
missing=()
for file in indexer.env manager.env cluster.key; do
  [ -r "${CREDENTIALS_DIR}/${file}" ] || missing+=("${CREDENTIALS_DIR}/${file}")
done
if [ "${#missing[@]}" -gt 0 ]; then
  echo "check-default-credentials: cannot read: ${missing[*]}" >&2
  echo "check-default-credentials: run this from the same directory as credentials-conf.sh (wazuh/)," >&2
  echo "check-default-credentials: or pass --credentials-dir." >&2
  exit 2
fi
# shellcheck source=/dev/null
. "${CREDENTIALS_DIR}/indexer.env"
# shellcheck source=/dev/null
. "${CREDENTIALS_DIR}/manager.env"
for key in WAZUH_INDEXER_ADMIN_PASSWORD WAZUH_INDEXER_KIBANASERVER_PASSWORD \
           WAZUH_INDEXER_MANAGER_PASSWORD WAZUH_MANAGER_API_PASSWORD WAZUH_MANAGER_WUI_PASSWORD; do
  if [ -z "${!key}" ]; then
    echo "check-default-credentials: ${key} is not set in ${CREDENTIALS_DIR}/{indexer,manager}.env" >&2
    exit 2
  fi
done
 
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
# exposing it. The credentials reach curl on stdin (-K -), never as arguments,
# so they are not in the process list of this host or of the pod.
curl_user() {
  printf 'user = "%s:%s"\n' "$1" "$2"
}

indexer_auth_code() {
  curl_user "$1" "$2" | kubectl -n "${NAMESPACE}" exec -i "${INDEXER_POD}" -- \
    curl -sk -K - -o /dev/null -w '%{http_code}' --max-time 15 \
    'https://localhost:9200/_plugins/_security/authinfo' 2>/dev/null
}
 
# POST, which is the method the endpoint accepts: a GET answers 405 whatever the
# credentials are, and a check that cannot tell a good password from a bad one is
# worse than no check.
api_auth_code() {
  curl_user "$1" "$2" | kubectl -n "${NAMESPACE}" exec -i "${MANAGER_POD}" -- \
    curl -sk -K - -o /dev/null -w '%{http_code}' --max-time 15 -X POST \
    'https://localhost:55000/security/user/authenticate' 2>/dev/null
}
 
# Retries a 429: rate limiting says nothing about the password.
auth_code() {
  local code=""
  local attempt
  for attempt in 1 2 3; do
    code=$("$@")
    [ "${code}" = "429" ] || break
    sleep 5
  done
  printf '%s' "${code}"
}
 
# The cluster key the manager is running with, from its own configuration.
cluster_key_of() {
  kubectl -n "${NAMESPACE}" exec "$1" -- \
    /var/wazuh-manager/bin/wazuh-manager-conf get cluster.key 2>/dev/null | tr -d '\r'
}

# The same test the manager's credentials resolver makes before it skips
# seeding the Wazuh API user database.
node_type() {
  kubectl -n "${NAMESPACE}" exec "$1" -- \
    /var/wazuh-manager/bin/wazuh-manager-conf get cluster.node_type 2>/dev/null | tr -d '\r'
}
 
# Prints "<account> default|changed|missing|absent" from the RBAC database of a
# manager pod. Opened read-only: a check must not create what it is checking.
api_db_state() {
  kubectl -n "${NAMESPACE}" exec -i "$1" -- \
    /var/wazuh-manager/framework/python/bin/python3 - ${API_USERS} 2>/dev/null <<'PROBE'
import os
import sqlite3
import sys
 
try:
    from api.constants import SECURITY_PATH
    from werkzeug.security import check_password_hash
 
    database = os.path.join(SECURITY_PATH, "rbac.db")
    users = {}
 
    if os.path.exists(database):
        connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
        try:
            if connection.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'users'"
            ).fetchone():
                users = dict(connection.execute("SELECT username, password FROM users"))
        finally:
            connection.close()
 
    for username in sys.argv[1:]:
        if not users:
            print(username, "absent")
        elif username not in users:
            print(username, "missing")
        elif check_password_hash(users[username], username):
            print(username, "default")
        else:
            print(username, "changed")
except Exception:
    sys.exit(1)
PROBE
}
 
################################################################################
info ""
info "The Wazuh indexer image"
################################################################################
 
# The user database in the image, not the one the cluster is running: it still
# shows what the image shipped, before resolve-credentials wrote the digests.
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
 
declare -A INDEXER_PASSWORD_OF=(
  [admin]="${WAZUH_INDEXER_ADMIN_PASSWORD}"
  [kibanaserver]="${WAZUH_INDEXER_KIBANASERVER_PASSWORD}"
  [wazuh-manager]="${WAZUH_INDEXER_MANAGER_PASSWORD}"
)
 
for user in ${INDEXER_USERS}; do
  weak_code=$(auth_code indexer_auth_code "${user}" "${user}")
  if [ -z "${weak_code}" ] || [ "${weak_code}" = "000" ]; then
    fail "${INDEXER_POD} did not answer while checking '${user}'"
  elif [ "${weak_code}" = "200" ]; then
    fail "${user} authenticates with '${user}' as its password"
  else
    pass "${user} is refused with '${user}' as its password (HTTP ${weak_code})"
  fi
 
  real_code=$(auth_code indexer_auth_code "${user}" "${INDEXER_PASSWORD_OF[${user}]}")
  if [ "${real_code}" = "200" ]; then
    pass "${user} authenticates with its generated password"
  else
    fail "${user} does not authenticate with the password in ${CREDENTIALS_DIR}/indexer.env (HTTP ${real_code})"
  fi
done
 
for user in ${DEMO_USERS}; do
  code=$(auth_code indexer_auth_code "${user}" "${user}")
  if [ -z "${code}" ] || [ "${code}" = "000" ]; then
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
 
declare -A API_PASSWORD_OF=(
  [wazuh]="${WAZUH_MANAGER_API_PASSWORD}"
  [wazuh-internal-client]="${WAZUH_MANAGER_WUI_PASSWORD}"
)
 
for user in ${API_USERS}; do
  weak_code=$(auth_code api_auth_code "${user}" "${user}")
  if [ -z "${weak_code}" ] || [ "${weak_code}" = "000" ]; then
    fail "no answer from the Wazuh API on ${MANAGER_POD} while checking '${user}'; the API is served by the manager master only"
  elif [ "${weak_code}" = "200" ]; then
    fail "${user} authenticates with '${user}' as its password"
  else
    pass "${user} is refused with '${user}' as its password (HTTP ${weak_code})"
  fi
 
  real_code=$(auth_code api_auth_code "${user}" "${API_PASSWORD_OF[${user}]}")
  if [ "${real_code}" = "200" ]; then
    pass "${user} authenticates with its generated password"
  else
    fail "${user} does not authenticate with the password in ${CREDENTIALS_DIR}/manager.env (HTTP ${real_code})"
  fi
done
 
################################################################################
info ""
info "Wazuh API accounts of each manager pod"
################################################################################
 
# A worker seeds no Wazuh API user database at all while it stays a worker: the
# manager's own credentials resolver checks cluster.node_type before deciding
# whether to seed rbac.db, and only a promoted worker would seed it from
# manager.env. So "absent" on a worker is the expected, healthy state, not a
# missed credential — checked against the same node_type the resolver itself
# reads, not assumed from the pod's labels.
MANAGER_PODS=$(kubectl -n "${NAMESPACE}" get pods -l 'app=wazuh-manager' \
  -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
 
if [ -z "${MANAGER_PODS}" ]; then
  fail "no pod labelled app=wazuh-manager in '${NAMESPACE}'"
fi
 
for pod in ${MANAGER_PODS}; do
  db_state=$(api_db_state "${pod}")
  if [ -z "${db_state}" ]; then
    fail "could not read the Wazuh API user database of ${pod}"
    continue
  fi
 
  for user in ${API_USERS}; do
    case "$(printf '%s\n' "${db_state}" | awk -v u="${user}" '$1 == u {print $2}')" in
      changed) pass "${pod}: ${user} does not have '${user}' as its password" ;;
      default) fail "${pod}: ${user} has '${user}' as its password" ;;
      missing) fail "${pod}: ${user} is not in the Wazuh API user database" ;;
      absent)
        if [ "$(node_type "${pod}")" = "worker" ]; then
          pass "${pod}: cluster worker, no Wazuh API user database to hold '${user}'"
        else
          fail "${pod}: no Wazuh API user database, so ${user} would be seeded with '${user}' as its password"
        fi
        ;;
      *) fail "${pod}: could not read the state of '${user}'" ;;
    esac
  done
done
 
info ""
################################################################################
info ""
info "Manager cluster key of each manager pod"
################################################################################

CLUSTER_KEY=$(cat "${CREDENTIALS_DIR}/cluster.key")

for pod in ${MANAGER_PODS}; do
  running_key=$(cluster_key_of "${pod}")
  if [ -z "${running_key}" ]; then
    fail "${pod}: could not read its cluster key"
  elif [ "${running_key}" = "${CLUSTER_KEY_PLACEHOLDER}" ]; then
    fail "${pod}: runs on the public placeholder cluster key"
  elif [ "${running_key}" != "${CLUSTER_KEY}" ]; then
    fail "${pod}: its cluster key is not the one in ${CREDENTIALS_DIR}/cluster.key"
  else
    pass "${pod}: runs on the generated cluster key"
  fi
done

info ""
info "The Wazuh API is served by the manager master only, so ${MANAGER_POD} is the"
info "node whose user database authenticates requests over HTTP. Worker pods run no"
info "API and answer nothing on port 55000; pointing --manager-pod at one reports no"
info "answer, which is why their accounts are read from the database above instead."
 
info ""
if [ "${failures}" -eq 0 ]; then
  info "${checks} checks, all passed."
  exit 0
fi
info "${checks} checks, ${failures} failed."
info "A deployment that skipped credentials-conf.sh before its first start never came up at all,"
info "so a failure here means resolution went inconsistent somewhere, not that a default was left."
info "See docs/ref/credentials.md."
exit 1
