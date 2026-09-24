#!/bin/bash

# Path configuration (adjust according to your folder structure)
CERT_TOOL="./wazuh-certs-tool.sh"
CONFIG_FILE="./config.yml"
OUTPUT_DIR="./wazuh-certificates" # Folder created by the script by default

# Parse arguments
DO_CERT=false
DO_COPY=false
DO_PRIV=false
AGENT_SAN=()

usage() {
  echo "Usage: $0 [--cert] [--copy] [--priv] [--agent-san <ip|dns>]..."
  echo "  --cert       Generate certificates using wazuh-certs-tool.sh"
  echo "  --copy       Copy certificates to the corresponding config directories"
  echo "  --priv       Give the certificate files to the user running the script,"
  echo "               so kustomize can read them"
  echo "  --agent-san  Additional address for the manager agent listener"
  echo "               certificates, such as the ingress load balancer FQDN."
  echo "               Repeat it for more than one."
}

while [ $# -gt 0 ]; do
  case $1 in
    --cert) DO_CERT=true; shift ;;
    --copy) DO_COPY=true; shift ;;
    --priv) DO_PRIV=true; shift ;;
    --agent-san)
      if [ -z "$2" ]; then
        echo "Missing <ip|dns> after --agent-san"
        usage
        exit 1
      fi
      AGENT_SAN+=(--agent-san "$2")
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

# If no flags provided, show usage
if ! $DO_CERT && ! $DO_COPY && ! $DO_PRIV; then
  usage
  exit 1
fi

# ---------------------------------------------------------------------------
# Parse config.yml to extract node names per section (indexer, manager, dashboard)
# ---------------------------------------------------------------------------
parse_config() {
  local section=""
  INDEXER_NODES=()
  MANAGER_NODES=()
  DASHBOARD_NODES=()

  while IFS= read -r line; do
    # Detect section headers (e.g., "  indexer:", "  manager:", "  dashboard:")
    if echo "$line" | grep -qE '^\s+indexer:\s*$'; then
      section="indexer"
      continue
    elif echo "$line" | grep -qE '^\s+manager:\s*$'; then
      section="manager"
      continue
    elif echo "$line" | grep -qE '^\s+dashboard:\s*$'; then
      section="dashboard"
      continue
    fi

    # Extract node name from "- name: <value>" lines
    if echo "$line" | grep -qE '^\s+-\s+name:'; then
      local name
      name=$(echo "$line" | sed 's/.*name:\s*//' | tr -d ' "'\''')
      case $section in
        indexer)   INDEXER_NODES+=("$name") ;;
        manager)   MANAGER_NODES+=("$name") ;;
        dashboard) DASHBOARD_NODES+=("$name") ;;
      esac
    fi
  done < "$CONFIG_FILE"
}

# Convert node name to directory name (replace . with _)
node_to_dir() {
  echo "$1" | tr '.' '_'
}

# ---------------------------------------------------------------------------
# Main logic
# ---------------------------------------------------------------------------

# Parse config.yml
# The certificates reach the cluster through kustomize, which reads them as the
# user running kubectl. That user, not the container UID, has to own them.
export CERT_UID="${SUDO_UID:-$(id -u)}"
export CERT_GID="${SUDO_GID:-$(id -g)}"
if $DO_COPY || $DO_PRIV; then
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file $CONFIG_FILE not found."
    exit 1
  fi
  parse_config
  echo "Detected indexer nodes:   ${INDEXER_NODES[*]}"
  echo "Detected manager nodes:   ${MANAGER_NODES[*]}"
  echo "Detected dashboard nodes: ${DASHBOARD_NODES[*]}"
fi

# 1. Generate certificates
if $DO_CERT; then
  # Ensure required files exist before proceeding
  if [[ ! -f "$CERT_TOOL" ]]; then
    echo "Error: Certificate tool '$CERT_TOOL' not found or not executable." >&2
    exit 1
  fi
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Configuration file '$CONFIG_FILE' not found." >&2
    exit 1
  fi
  echo "Generating certificates"
  bash $CERT_TOOL -A "${AGENT_SAN[@]}"
fi

# 2. Copy certificates to config directories
if $DO_COPY; then
  FIRST_INDEXER=true
  for node in "${INDEXER_NODES[@]}"; do
    dir_name=$(node_to_dir "$node")
    echo "Copying certificates for indexer: $node -> config/$dir_name/certs/"
    mkdir -p "./config/$dir_name/certs"
    cp "$OUTPUT_DIR/${node}"* "./config/$dir_name/certs/"
    if $FIRST_INDEXER; then
      cp "$OUTPUT_DIR"/admin* "./config/$dir_name/certs/"
      FIRST_INDEXER=false
    fi
  done

  for node in "${MANAGER_NODES[@]}"; do
    dir_name=$(node_to_dir "$node")
    # The agent listener (remoted) pair, ${node}-remoted.pem and
    # ${node}-remoted-key.pem, is copied by the glob below along with
    # ${node}.pem and ${node}-key.pem. The manager does not start without it.
    for cert in "${node}-remoted.pem" "${node}-remoted-key.pem"; do
      if [[ ! -f "$OUTPUT_DIR/$cert" ]]; then
        echo "Error: '$OUTPUT_DIR/$cert' not found. The agent listener certificate is" >&2
        echo "required by the Wazuh manager. Regenerate the certificates with a" >&2
        echo "wazuh-certs-tool.sh version that creates the remoted pair." >&2
        exit 1
      fi
    done
    echo "Copying certificates for manager: $node -> config/$dir_name/certs/"
    mkdir -p "./config/$dir_name/certs"
    cp "$OUTPUT_DIR/${node}"* "./config/$dir_name/certs/"
  done

  for node in "${DASHBOARD_NODES[@]}"; do
    dir_name=$(node_to_dir "$node")
    echo "Copying certificates for dashboard: $node -> config/$dir_name/certs/"
    mkdir -p "./config/$dir_name/certs"
    cp "$OUTPUT_DIR/${node}"* "./config/$dir_name/certs/"
  done
  echo "Copying root-ca certificates -> config/root-ca/certs/"
  mkdir -p "./config/root-ca/certs"
  cp "$OUTPUT_DIR"/root-ca* "./config/root-ca/certs/"
fi

# 3. Set ownership and permissions
if $DO_PRIV; then
  for node in "${INDEXER_NODES[@]}"; do
    dir_name=$(node_to_dir "$node")
    echo "Setting ownership for indexer $node (${CERT_UID}:${CERT_GID})"
    chown -R ${CERT_UID}:${CERT_GID} "./config/$dir_name/certs"
  done

  for node in "${MANAGER_NODES[@]}"; do
    dir_name=$(node_to_dir "$node")
    echo "Setting ownership for manager $node (${CERT_UID}:${CERT_GID})"
    chown -R ${CERT_UID}:${CERT_GID} "./config/$dir_name/certs"
  done

  for node in "${DASHBOARD_NODES[@]}"; do
    dir_name=$(node_to_dir "$node")
    echo "Setting ownership for dashboard $node (${CERT_UID}:${CERT_GID})"
    chown -R ${CERT_UID}:${CERT_GID} "./config/$dir_name/certs"
  done
  echo "Setting ownership for root-ca certificates (${CERT_UID}:${CERT_GID})"
  chown -R ${CERT_UID}:${CERT_GID} "./config/root-ca/certs"
fi

echo "Process completed."
