#!/usr/bin/env bash
# create_namespaces_from_backups.sh
# Creates all namespaces found in Longhorn backupVolumes

set -eo pipefail

LONGHORN_NS="${LONGHORN_NS:-longhorn}"

info()  { echo -e "ℹ️  $*"; }
warn()  { echo -e "⚠️  $*"; }

# Ensure namespace exists
ensure_namespace() {
  local ns="$1"
  [[ -z "$ns" || "$ns" == "-" ]] && return 0
  if ! kubectl get namespace "$ns" >/dev/null 2>&1; then
    info "Creating namespace '$ns'..."
    kubectl create namespace "$ns"
  else
    info "Namespace '$ns' already exists."
  fi
}

# Fetch all backupVolumes and create namespaces
mapfile -t backupvols < <(kubectl get backupvolumes.longhorn.io -n "$LONGHORN_NS" -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n')

for bv in "${backupvols[@]}"; do
  ns=$(kubectl get backupvolumes.longhorn.io "$bv" -n "$LONGHORN_NS" -o json | \
       jq -r '(.status.labels.KubernetesStatus // "{}") | fromjson | .namespace // empty')

  if [[ -n "$ns" ]]; then
    ensure_namespace "$ns"
  else
    warn "BackupVolume '$bv' has no associated namespace. Skipping."
  fi
done

info "All namespaces from backupVolumes have been processed."