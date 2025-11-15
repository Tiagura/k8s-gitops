#!/usr/bin/env bash
# longhorn-restore.sh
# Restores Longhorn backupVolumes safely:
#   1. Creates Volume from backup
#   2. Pins Volume to a node
#   3. Waits for restore to complete
#   4. Creates PVC bound to restored Volume

set -uo pipefail

STORAGE_CLASS="${STORAGE_CLASS:-longhorn}"
LONGHORN_NS="${LONGHORN_NS:-longhorn}"
LONGHORN_REPLICA_COUNT="${LONGHORN_REPLICA_COUNT:-2}"
LONGHORN_FRONTEND="${LONGHORN_FRONTEND:-blockdev}"
LONGHORN_RECLAIM_POLICY="${LONGHORN_RECLAIM_POLICY:-Delete}"
FS_TYPE="${FS_TYPE:-ext4}"
RESTORE_POLL_INTERVAL="${RESTORE_POLL_INTERVAL:-5}"  # seconds

DRY_RUN=${DRY_RUN:-false}

info()  { echo -e "ℹ️  $*"; }
warn()  { echo -e "⚠️  $*"; }
error() { echo -e "❌ $*" >&2; }

# -------------------------
# Convert bytes to size string
# -------------------------
bytes_to_size() {
  local bytes=${1:-0}
  if [[ -z "$bytes" || "$bytes" == "null" ]]; then
    echo "1Gi"
    return
  fi
  local mib=$((1024*1024))
  local gib=$((1024*1024*1024))
  if (( bytes < gib )); then
    echo $(( (bytes + mib - 1)/mib ))Mi
  else
    awk -v b="$bytes" -v g="$gib" 'BEGIN {s=b/g; printf "%gGi\n", s}'
  fi
}

# -------------------------
# Translate access mode from Longhorn label to Kubernetes
# -------------------------
translate_access_mode() {
  local mode="$1"
  case "${mode,,}" in
    rwx) echo "ReadWriteMany" ;;
    rwo|rw) echo "ReadWriteOnce" ;;
    ro|rom) echo "ReadOnlyMany" ;;
    *) echo "ReadWriteOnce" ;;
  esac
}

# -------------------------
# Ensure namespace exists
# -------------------------
ensure_namespace() {
  local ns="$1"
  [[ -z "$ns" || "$ns" == "-" ]] && return 0
  if ! kubectl get namespace "$ns" >/dev/null 2>&1; then
    if [[ "$DRY_RUN" == "true" ]]; then
      info "[DRY-RUN] Would create namespace $ns"
    else
      info "Creating namespace $ns..."
      kubectl create namespace "$ns"
    fi
  fi
}

# -------------------------
# Wait for volume restore
# -------------------------
wait_for_restore() {
  local vol="$1"
  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY-RUN] Would wait for restore to complete for $vol"
    return
  fi

  info "Waiting for restore to complete for $vol..."
  while :; do
    state=$(kubectl get volumes.longhorn.io "$vol" -n "$LONGHORN_NS" -o jsonpath='{.status.state}')
    [[ "$state" == "detached" || "$state" == "healthy" ]] && break
    sleep "$RESTORE_POLL_INTERVAL"
  done
  info "Restore completed for $vol (state: $state)"
}

# -------------------------
# Wait for PVC to bind
# -------------------------
wait_for_pvc_bind() {
  local pvc="$1"
  local ns="$2"

  info "Waiting for PVC $pvc in namespace $ns to bind…"

  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY-RUN] Would wait for PVC $pvc to bind"
    return
  fi

  while true; do
    phase=$(kubectl get pvc "$pvc" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")

    if [[ "$phase" == "Bound" ]]; then
      info "PVC $pvc successfully bound."
      break
    fi

    sleep 2
  done
}

# -------------------------
# Build Volume, PV, PVC YAML
# -------------------------
build_manifests() {
  local pvc_name="$1" ns="$2" size_bytes="$3" backup_url="$4" volume_name="$5" access_mode="$6" pv_name="$7"

  local size
  size=$(bytes_to_size "$size_bytes")
  local access_mode_translated
  access_mode_translated=$(translate_access_mode "$access_mode")

  cat <<EOF
# Longhorn Volume
apiVersion: longhorn.io/v1beta2
kind: Volume
metadata:
  name: ${volume_name}
  namespace: ${LONGHORN_NS}
spec:
  fromBackup: ${backup_url}
  frontend: ${LONGHORN_FRONTEND}
  size: "${size_bytes}"
  numberOfReplicas: ${LONGHORN_REPLICA_COUNT}
---
# PV
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${volume_name}
  annotations:
    pv.kubernetes.io/bound-by-controller: "yes"
    longhorn.io/volume-scheduling-error: ""
spec:
  capacity:
    storage: ${size}
  volumeMode: Filesystem
  storageClassName: ${STORAGE_CLASS}
  accessModes:
    - ${access_mode_translated}
  persistentVolumeReclaimPolicy: ${LONGHORN_RECLAIM_POLICY}
  csi:
    driver: driver.longhorn.io
    volumeHandle: ${volume_name}
    fsType: ${FS_TYPE}
    volumeAttributes:
      numberOfReplicas: "${LONGHORN_REPLICA_COUNT}"
      staleReplicaTimeout: "20"
      diskSelector: ""
      nodeSelector: ""
---
# PVC
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${pvc_name}
  namespace: ${ns}
spec:
  accessModes:
    - ${access_mode_translated}
  storageClassName: ${STORAGE_CLASS}
  resources:
    requests:
      storage: ${size}
EOF
}

# -------------------------
# Restore a single backupVolume
# -------------------------
restore_backupvolume() {
  local bv="$1"
  info "Processing backupVolume: $bv"

  local raw pvc ns last_backup volume_name size_bytes access_mode backup_url pv
  raw=$(kubectl get backupvolumes.longhorn.io "$bv" -n "$LONGHORN_NS" -o json)
  pvc=$(echo "$raw" | jq -r '(.status.labels.KubernetesStatus // "{}") | fromjson | .pvcName // empty')
  ns=$(echo "$raw" | jq -r '(.status.labels.KubernetesStatus // "{}") | fromjson | .namespace // empty')
  last_backup=$(echo "$raw" | jq -r '.status.lastBackupName // empty')
  volume_name=$(echo "$raw" | jq -r '.status.volumeName // .spec.volumeName // empty')
  size_bytes=$(echo "$raw" | jq -r '.status.size // empty')
  access_mode=$(echo "$raw" | jq -r '.status.labels["longhorn.io/volume-access-mode"] // "rwo"')
  backup_url=$(kubectl get backups.longhorn.io "$last_backup" -n "$LONGHORN_NS" -o jsonpath='{.status.url}')

  # **Extract original PV name from backup metadata**
  pv=$(echo "$raw" | jq -r '(.status.labels.KubernetesStatus // "{}") | fromjson | .pvName // empty')
  pv="${pv:-}"   # default to empty if unset

  [[ -z "$pvc" || -z "$last_backup" || -z "$volume_name" ]] && { warn "Skipping $bv: missing pvc, backup, or volume name"; return; }

  ensure_namespace "$ns"
  local manifest
  manifest=$(build_manifests "$pvc" "$ns" "$size_bytes" "$backup_url" "$volume_name" "$access_mode" "$pv")

  # Create Volume
  if ! kubectl get volumes.longhorn.io "$volume_name" -n "$LONGHORN_NS" >/dev/null 2>&1; then
    if [[ "$DRY_RUN" == "true" ]]; then
      info "[DRY-RUN] Would create Longhorn Volume $volume_name"
      echo "$manifest" | awk '/^# Longhorn Volume$/,/^---$/'
    else
      info "Creating Longhorn Volume $volume_name..."
      echo "$manifest" | awk '/^# Longhorn Volume$/,/^---$/' | kubectl apply -f -
    fi
  else
    info "Volume $volume_name already exists"
  fi

  # Wait for restore
  wait_for_restore "$volume_name"

  # Create PV
  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY-RUN] Would create PV $volume_name"
    echo "$manifest" | awk '/^# PV$/,/^---$/'
  else
    info "Creating PV $volume_name..."
    echo "$manifest" | awk '/^# PV$/,/^---$/' | kubectl apply -f -
  fi

  # Create PVC
  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY-RUN] Would create PVC $pvc"
    echo "$manifest" | awk '/^# PVC$/,/^$/ {if ($0 !~ /^---$/) print}'
  else
    info "Creating PVC $pvc..."
    echo "$manifest" | awk '/^# PVC$/,/^$/ {if ($0 !~ /^---$/) print}' | kubectl apply -f -
  fi

  wait_for_pvc_bind "$pvc" "$ns"

  info "Restore complete for PVC $pvc (ns: $ns)"
}

# -------------------------
# List backups
# -------------------------
list_backups() {
  echo
  echo "---------------------------------------------------------"
  echo "   Longhorn backup volumes (namespace: $LONGHORN_NS)"
  echo "---------------------------------------------------------"
  kubectl get backupvolumes.longhorn.io -n "$LONGHORN_NS" -o json |
  jq -r '
    .items[] |
    .metadata.name as $bv |
    (.spec.volumeName // .status.volumeName // "-") as $vol |
    (.status.labels.KubernetesStatus // "{}" | fromjson) as $kstatus |
    (
      "BackupVolume: \($bv)",
      "VolumeName: \($vol)",
      "PVC Name: \($kstatus.pvcName // "-")",
      "PVC Namespace: \($kstatus.namespace // "-")",
      "PV Name: \($kstatus.pvName // "-")",
      "StorageClass: " + (.status.storageClassName // "-"),
      "Size (bytes): " + (.status.size // "-"),
      "AccessMode: " + (.status.labels["longhorn.io/volume-access-mode"] // "-"),
      "DataTier: " + (.status.labels["data-tier"] // .status.labels["Data - Tier"] // "-"),
      "LastBackup: " + (.status.lastBackupName // "-"),
      "LastBackupAt: " + (.status.lastBackupAt // "-"),
      "---------------------------------------------------------"
    )
  '
}

# -------------------------
# Resolve PVC → backupVolume
# -------------------------
resolve_backupvolume_by_pvc() {
  local pvc="$1"
  kubectl get backupvolumes.longhorn.io -n "$LONGHORN_NS" -o json \
    | jq -r --arg pvc "$pvc" '
        .items[]
        | select((.status.labels.KubernetesStatus // "{}") | fromjson | .pvcName == $pvc)
        | .metadata.name
      '
}

# -------------------------
# Restore commands
# -------------------------
cmd_restore_one() {
  local target="$1"; shift
  [[ -z "$target" ]] && { error "restore-one requires a target"; return 1; }

  if kubectl get backupvolumes.longhorn.io -n "$LONGHORN_NS" "$target" >/dev/null 2>&1; then
    restore_backupvolume "$target"
    return
  fi

  bv=$(resolve_backupvolume_by_pvc "$target")
  if [[ -n "$bv" ]]; then
    info "Resolved PVC '$target' to backupVolume '$bv'"
    restore_backupvolume "$bv"
  else
    error "Could not find a backupVolume for PVC '$target'"
    return 1
  fi
}

cmd_restore_tier() {
  local tier="$1"; shift
  [[ -z "$tier" ]] && { error "restore-tier requires a tier"; return 1; }

  mapfile -t vols < <(kubectl get backupvolumes.longhorn.io -n "$LONGHORN_NS" -o json \
    | jq -r --arg t "$tier" '.items[] | select((.status.labels["data-tier"] // .status.labels["Data - Tier"] // "") == $t) | .metadata.name')
  [[ ${#vols[@]} -eq 0 ]] && { warn "No backupVolumes found for data-tier '$tier'"; return; }

  for v in "${vols[@]}"; do restore_backupvolume "$v"; done
}

cmd_restore_all() {
  mapfile -t vols < <(kubectl get backupvolumes.longhorn.io -n "$LONGHORN_NS" -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n')
  for v in "${vols[@]}"; do restore_backupvolume "$v"; done
}

# -------------------------
# Global flag parser
# -------------------------
parse_global_flags() {
  for f in "$@"; do
    case "$f" in
      --dry-run) DRY_RUN=true ;;
    esac
  done
}

# -------------------------
# Main
# -------------------------
main() {
  # Check if last argument is --dry-run
  if [[ "${!#}" == "--dry-run" ]]; then
    DRY_RUN=true
    # Remove last argument
    set -- "${@:1:$(($#-1))}"
  fi

  if [[ $# -lt 1 ]]; then
    print_usage
    exit 1
  fi

  cmd="$1"; shift

  case "$cmd" in
    list) list_backups ;;
    restore-one) 
      if [[ $# -lt 1 ]]; then
        error "restore-one requires a backupVolume or PVC name"
        print_usage
        exit 1
      fi
      cmd_restore_one "$@" 
      ;;
    restore-tier) 
      if [[ $# -lt 1 ]]; then
        error "restore-tier requires a tier name"
        print_usage
        exit 1
      fi
      cmd_restore_tier "$@" 
      ;;
    restore-all)
      cmd_restore_all  # no args needed
      ;;
    *) error "Unknown command: $cmd"; print_usage; exit 1 ;;
  esac
}

print_usage() {
  cat <<EOF
Usage:
  $0 list
      - List backupVolumes with details.

  $0 restore-one <backupVolume-or-pvc-name> [--dry-run]
      - Restore a single volume. Accepts backupVolume name or PVC name fragment.

  $0 restore-tier <standard|important|critical> [--dry-run]
      - Restore all volumes labeled with data-tier = <tier>.

  $0 restore-all [--dry-run]
      - Restore all volumes.

Global flags:
  --dry-run   (prints YAML only)
EOF
}

main "$@"