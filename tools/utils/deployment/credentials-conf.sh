#!/bin/bash
# Wazuh Kubernetes Copyright (C) Wazuh Inc. (License GPLv2)
#
# Creates the passwords and the manager cluster key of one Wazuh deployment
# before its first start and writes them, one file per component plus
# cluster.key, into the directory kustomize's secretGenerator reads them from
# (see wazuh/kustomization.yml). Mirrors
# tools/utils/deployment/certificates-conf.sh for the credentials half of
# install-time credential generation (wazuh/wazuh-indexer#1928).

set -o pipefail

# The password rule of the Wazuh packages, shared with the installation assistant.
PASSWORD_POLICY="$(cd "$(dirname "$0")" && pwd)/password-policy.sh"
OUTPUT_DIR="./config/credentials"
FORCE=false
CLUSTER_KEY_FILE="cluster.key"
# Value the cluster key Secret shipped with before it was generated here.
CLUSTER_KEY_PLACEHOLDER="REPLACETHISCLUSTERKEYBEFOREDEPLO"

ALL_KEYS=(
  WAZUH_INDEXER_ADMIN_PASSWORD
  WAZUH_INDEXER_KIBANASERVER_PASSWORD
  WAZUH_INDEXER_MANAGER_PASSWORD
  WAZUH_MANAGER_API_PASSWORD
  WAZUH_MANAGER_WUI_PASSWORD
)

COMPONENTS=(indexer manager dashboard)
declare -A COMPONENT_KEYS=(
  [indexer]="WAZUH_INDEXER_ADMIN_PASSWORD WAZUH_INDEXER_KIBANASERVER_PASSWORD WAZUH_INDEXER_MANAGER_PASSWORD"
  [manager]="WAZUH_INDEXER_MANAGER_PASSWORD WAZUH_MANAGER_API_PASSWORD WAZUH_MANAGER_WUI_PASSWORD"
  [dashboard]="WAZUH_INDEXER_KIBANASERVER_PASSWORD WAZUH_MANAGER_WUI_PASSWORD"
)

error() {
  echo "credentials-conf.sh: $*" >&2
}

usage() {
  cat <<USAGE
Usage: $0 [--output <directory>] [--force]

  --output <directory>  Where to write indexer.env, manager.env,
                        dashboard.env and ${CLUSTER_KEY_FILE}. Default: ${OUTPUT_DIR}
  --force               Replace existing files. Only for a deployment that
                        has never been started: a started one keeps the
                        passwords it was first given.
  -h, --help            Show this help.

A key already set in the environment is validated and used instead of a
generated value, e.g.:

  WAZUH_INDEXER_ADMIN_PASSWORD='<password>' $0

Keys: ${ALL_KEYS[*]} WAZUH_CLUSTER_KEY

WAZUH_CLUSTER_KEY is the manager cluster key: exactly 32 characters from
A-Z a-z 0-9. When only ${CLUSTER_KEY_FILE} is missing, as on a deployment
created before this script wrote it, only that file is written; pass the
running key in WAZUH_CLUSTER_KEY to keep it.

The files this writes are read by kustomize's secretGenerator (files:), so
kustomize must be able to read them: run this script as the same user who
runs kubectl/kustomize, or with sudo if certificates-conf.sh's output
directory was also created with sudo (the files are then given to the user
who ran sudo, same as certificates-conf.sh does for certificates).
USAGE
}

while [ $# -gt 0 ]; do
  case $1 in
    --output)
      if [ -z "$2" ]; then
        error "--output needs a directory"
        exit 2
      fi
      OUTPUT_DIR="${2%/}"
      shift 2
      ;;
    --force) FORCE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      error "unknown option: $1"
      usage >&2
      exit 2
      ;;
  esac
done

# shellcheck source=password-policy.sh
if ! . "${PASSWORD_POLICY}" 2>/dev/null; then
  error "cannot read ${PASSWORD_POLICY}; run this script from a wazuh-kubernetes checkout"
  exit 1
fi

# Every component validates what it receives; a value one of them would
# reject is refused here, so the deployment does not find out at pod start.
check_password() {
  local key=$1 value=$2 reason
  if ! reason=$(common_passwordValidate "${value}" 2>&1); then
    error "${key} was rejected: ${reason}"
    return 1
  fi
}

# The managers refuse to start with a key that is not 32 alphanumeric
# characters, and the placeholder is public.
check_cluster_key() {
  local value=$1
  if ! printf '%s' "${value}" | grep -Eq '^[A-Za-z0-9]{32}$'; then
    error "WAZUH_CLUSTER_KEY was rejected: it must be exactly 32 characters from A-Z a-z 0-9"
    return 1
  fi
  if [ "${value}" = "${CLUSTER_KEY_PLACEHOLDER}" ]; then
    error "WAZUH_CLUSTER_KEY was rejected: it is the public placeholder the Secret used to ship with"
    return 1
  fi
}

existing=()
for component in "${COMPONENTS[@]}"; do
  if [ -e "${OUTPUT_DIR}/${component}.env" ] || [ -L "${OUTPUT_DIR}/${component}.env" ]; then
    existing+=("${OUTPUT_DIR}/${component}.env")
  fi
done
cluster_key_exists=false
if [ -e "${OUTPUT_DIR}/${CLUSTER_KEY_FILE}" ] || [ -L "${OUTPUT_DIR}/${CLUSTER_KEY_FILE}" ]; then
  cluster_key_exists=true
fi

# A deployment created before this script wrote the cluster key has every
# password file but no cluster.key: only that file is added.
CLUSTER_KEY_ONLY=false
if ! ${FORCE}; then
  if [ "${#existing[@]}" -eq "${#COMPONENTS[@]}" ] && ! ${cluster_key_exists}; then
    CLUSTER_KEY_ONLY=true
  elif [ "${#existing[@]}" -gt 0 ] || ${cluster_key_exists}; then
    ${cluster_key_exists} && existing+=("${OUTPUT_DIR}/${CLUSTER_KEY_FILE}")
    error "credentials already exist: ${existing[*]}"
    error "a deployment keeps the passwords it was first started with, so they are not replaced"
    error "use --force only if this deployment has never been started"
    exit 1
  fi
fi

declare -A VALUES SOURCES
failed=false
${CLUSTER_KEY_ONLY} || for key in "${ALL_KEYS[@]}"; do
  if [ -n "${!key}" ]; then
    check_password "${key}" "${!key}" || { failed=true; continue; }
    VALUES[${key}]="${!key}"
    SOURCES[${key}]="supplied"
  else
    VALUES[${key}]=$(common_passwordGenerate)
    SOURCES[${key}]="generated"
  fi
done

if [ -n "${WAZUH_CLUSTER_KEY}" ]; then
  if check_cluster_key "${WAZUH_CLUSTER_KEY}"; then
    CLUSTER_KEY="${WAZUH_CLUSTER_KEY}"
    SOURCES[WAZUH_CLUSTER_KEY]="supplied"
  else
    failed=true
  fi
else
  CLUSTER_KEY=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
  if check_cluster_key "${CLUSTER_KEY}" 2>/dev/null; then
    SOURCES[WAZUH_CLUSTER_KEY]="generated"
  else
    error "could not generate WAZUH_CLUSTER_KEY"
    failed=true
  fi
fi

if ${failed}; then
  error "nothing was written"
  exit 1
fi

# Same ownership convention as certificates-conf.sh: kustomize's
# secretGenerator reads these files as the user running kubectl, not as the
# container UID and not as root if this script was run with sudo.
export CRED_UID="${SUDO_UID:-$(id -u)}"
export CRED_GID="${SUDO_GID:-$(id -g)}"

umask 077
if ! mkdir -p "${OUTPUT_DIR}" 2>/dev/null || ! chmod 700 "${OUTPUT_DIR}" 2>/dev/null; then
  error "cannot create ${OUTPUT_DIR}"
  error "if certificates-conf.sh created its parent as root, run this script with sudo too;"
  error "the files are then given to the user who ran sudo"
  exit 1
fi

${CLUSTER_KEY_ONLY} || for component in "${COMPONENTS[@]}"; do
  target="${OUTPUT_DIR}/${component}.env"
  tmp=$(mktemp "${OUTPUT_DIR}/.${component}.env.XXXXXX") || {
    error "cannot write into ${OUTPUT_DIR}"
    exit 1
  }
  {
    echo "# Wazuh ${component} credentials, created by credentials-conf.sh on $(date -u '+%Y-%m-%dT%H:%M:%SZ')."
    echo "# Editing a value here does not change a deployment that has already started."
    echo "# Read by kustomize's secretGenerator (wazuh/kustomization.yml): edit the value"
    echo "# here only before the FIRST 'kubectl apply', not to rotate a running deployment."
    for key in ${COMPONENT_KEYS[${component}]}; do
      printf '%s=%s\n' "${key}" "${VALUES[${key}]}"
    done
  } > "${tmp}"
  chmod 600 "${tmp}"
  chown "${CRED_UID}:${CRED_GID}" "${tmp}"
  mv -f "${tmp}" "${target}"
done

# No trailing newline: secretGenerator copies the file verbatim into the
# Secret, and the managers read the key from it as WAZUH_CLUSTER_KEY.
tmp=$(mktemp "${OUTPUT_DIR}/.${CLUSTER_KEY_FILE}.XXXXXX") || {
  error "cannot write into ${OUTPUT_DIR}"
  exit 1
}
printf '%s' "${CLUSTER_KEY}" > "${tmp}"
chmod 600 "${tmp}"
chown "${CRED_UID}:${CRED_GID}" "${tmp}"
mv -f "${tmp}" "${OUTPUT_DIR}/${CLUSTER_KEY_FILE}"
chown "${CRED_UID}:${CRED_GID}" "${OUTPUT_DIR}"

if ${CLUSTER_KEY_ONLY}; then
  echo "WAZUH_CLUSTER_KEY: ${SOURCES[WAZUH_CLUSTER_KEY]}"
  echo "Cluster key written to ${OUTPUT_DIR}/${CLUSTER_KEY_FILE}; the existing password files were left as they are"
  exit 0
fi

for key in "${ALL_KEYS[@]}" WAZUH_CLUSTER_KEY; do
  echo "${key}: ${SOURCES[${key}]}"
done
echo "Credentials written to ${OUTPUT_DIR}: indexer.env, manager.env, dashboard.env, ${CLUSTER_KEY_FILE}"
echo "Log in to the Wazuh dashboard as 'admin'. Read its password with:"
echo "  grep '^WAZUH_INDEXER_ADMIN_PASSWORD=' ${OUTPUT_DIR}/indexer.env | cut -d= -f2-"
