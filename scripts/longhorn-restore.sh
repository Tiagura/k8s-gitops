#!/usr/bin/env bash
# longhorn-restore.sh
# Requirements: kubectl, jq
# Dry-run behavior: prints YAML to terminal only.
# Force behavior: forces restore even if PV/PVC already exists. Use with caution.

set -uo pipefail

STORAGE_CLASS="${STORAGE_CLASS:-longhorn}"
LONGHORN_NS="${LONGHORN_NS:-longhorn}"
LONGHORN_REPLICA_COUNT="${LONGHORN_REPLICA_COUNT:-2}"
LONGHORN_FRONTEND="${LONGHORN_FRONTEND:-blockdev}"

# pretty output helpers
info()  { echo -e "ℹ️  $*"; }
warn()  { echo -e "⚠️  $*"; }
error() { echo -e "❌ $*" >&2; }

# -------------------------
# Convert bytes to size string
# -------------------------
# bytes_to_size() {
#   local bytes=${1:-0}
#   if [[ -z "$bytes" || "$bytes" == "null" ]]; then
#     echo "1Gi"
#     return
#   fi

#   local kib=$((1024))
#   local mib=$((kib * 1024))
#   local gib=$((mib * 1024))

#   if (( bytes < gib )); then
#     local size_mi=$(( (bytes + mib - 1) / mib ))
#     echo "${size_mi}Mi"
#   else
#     local size_gi
#     size_gi=$(awk -v b="$bytes" -v g="$gib" 'BEGIN {s=b/g; printf "%0.2f", s}')
#     size_gi=$(echo "$size_gi" | sed 's/\.00$//;s/0$//')
#     echo "${size_gi}Gi"
#   fi
# }
bytes_to_size() {
  local bytes=${1:-0}
  if [[ -z "$bytes" || "$bytes" == "null" ]]; then
    echo "1Gi"
    return
  fi

  local mib=$((1024*1024))
  local gib=$((1024*1024*1024))

  if (( bytes < gib )); then
    # <1Gi → Mi, round up
    echo $(( (bytes + mib - 1)/mib ))Mi
  else
    # ≥1Gi → Gi, keep up to 2 decimals (1.1, 1.25, 1.75, etc.)
    awk -v b="$bytes" -v g="$gib" 'BEGIN {s=b/g; printf "%gGi\n", s}'
  fi
}


# -------------------------
# Global flags
# -------------------------
GLOBAL_FORCE="false"
GLOBAL_DRY_RUN="false"

parse_global_flags() {
  for a in "$@"; do
    case "$a" in
      --force) GLOBAL_FORCE="true" ;;
      --dry-run) GLOBAL_DRY_RUN="true" ;;
    esac
  done
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
      "StorageClass: \(.status.storageClassName // "-")",
      "Size (bytes): \(.status.size // "-")",
      "AccessMode: " + (.status.labels["longhorn.io/volume-access-mode"] // "-"),
      "DataTier: " + (.status.labels["data-tier"] // .status.labels["Data - Tier"] // "-"),
      "LastBackup: " + (.status.lastBackupName // "-"),
      "LastBackupAt: " + (.status.lastBackupAt // "-"),
      "---------------------------------------------------------"
    )
  '
}

# -------------------------
# Extract backup fields
# -------------------------
extract_backup_fields() {
  local vol="$1"
  [[ -z "$vol" ]] && return 1

  local raw ks pvc ns pv size last_backup_name volume_name data_tier backup_url

  raw=$(kubectl get backupvolumes.longhorn.io -n "$LONGHORN_NS" "$vol" -o json) || { warn "cannot read backupVolume $vol"; return 1; }

  ks=$(echo "$raw" | jq -r '(.status.labels["KubernetesStatus"] // "{}")')
  pvc=$(echo "$ks" | jq -r 'try (.pvcName) catch ""')
  ns=$(echo "$ks" | jq -r 'try (.namespace) catch ""')
  pv=$(echo "$ks" | jq -r 'try (.pvName) catch ""')

  size=$(echo "$raw" | jq -r '.status.size // empty')
  last_backup_name=$(echo "$raw" | jq -r '.status.lastBackupName // empty')
  volume_name=$(echo "$raw" | jq -r '.spec.volumeName // .status.volumeName // empty')
  data_tier=$(echo "$raw" | jq -r '.status.labels["data-tier"] // .status.labels["Data - Tier"] // empty')

  if [[ -n "$last_backup_name" ]]; then
    backup_url=$(kubectl get backups.longhorn.io -n "$LONGHORN_NS" "$last_backup_name" -o jsonpath='{.status.url}' 2>/dev/null || echo "")
  else
    backup_url=""
  fi

  printf '%s|%s|%s|%s|%s|%s|%s|%s' "$pvc" "$ns" "$size" "$last_backup_name" "$backup_url" "$data_tier" "$pv" "$volume_name"
}

# -------------------------
# Build manifests
# -------------------------
build_manifests() {
  local pvc_name="$1"; local ns="$2"; local size_bytes="$3"; local backup_url="$4"; local volume_name="$5"
  local size
  size=$(bytes_to_size "$size_bytes")

  cat <<EOF
apiVersion: longhorn.io/v1beta2
kind: Volume
metadata:
  name: ${volume_name}
spec:
  fromBackup: ${backup_url}
  frontend: ${LONGHORN_FRONTEND}
  size: "${size_bytes}"
  numberOfReplicas: ${LONGHORN_REPLICA_COUNT}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${pvc_name}
  namespace: ${ns}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ${STORAGE_CLASS}
  resources:
    requests:
      storage: ${size}
EOF
}

# -------------------------
# Ensure namespace exists
# -------------------------
ensure_namespace() {
  local ns="$1"
  local dry_run="${2:-false}"

  if [[ -z "$ns" || "$ns" == "-" ]]; then
    return 0
  fi

  if ! kubectl get namespace "$ns" >/dev/null 2>&1; then
    if [[ "$dry_run" == "true" ]]; then
      info "[DRY-RUN] Would create namespace: $ns"
    else
      info "Namespace $ns does not exist, creating..."
      kubectl create namespace "$ns"
    fi
  fi
}

# -------------------------
# Debounce restore
# -------------------------
should_proceed_restore() {
  local pvc_name="$1"; local ns="$2"; local force="$3"

  if kubectl get volumes.longhorn.io "$pvc_name" >/dev/null 2>&1; then
    [[ "$force" == "true" ]] && return 1
    warn "Skipping $pvc_name: Longhorn Volume already exists (use --force)"
    return 0
  fi

  if kubectl get pvc -n "$ns" "$pvc_name" >/dev/null 2>&1; then
    [[ "$force" == "true" ]] && return 1
    warn "Skipping $pvc_name: PVC already exists in namespace $ns (use --force)"
    return 0
  fi

  return 1
}

# -------------------------
# Restore a backupVolume
# -------------------------
restore_backupvolume() {
  local bv="$1"; local dry_run="$2"; local force="$3"

  info "Processing backupVolume: $bv"

  IFS='|' read -r pvc ns size_bytes last_backup backup_url data_tier pv volume_name <<< "$(extract_backup_fields "$bv")" || { warn "failed to extract fields"; return 1; }

  if [[ -z "$pvc" || -z "$backup_url" || -z "$volume_name" ]]; then
    warn "Skipping $bv: missing pvc name, volume name, or backup URL"
    return 0
  fi

  info " → pvc: $pvc"
  info " → namespace: ${ns:-default}"
  info " → last backup: $last_backup"
  info " → backup URL: $backup_url"
  info " → size: $size_bytes bytes"
  info " → data-tier: ${data_tier:--}"

  # Create namespace if missing
  ensure_namespace "${ns:-default}"

  # Debounce check
  should_proceed_restore "$volume_name" "${ns:-default}" "$force"
  [[ $? -eq 0 ]] && return 0

  # Build YAML
  manifest=$(build_manifests "$pvc" "${ns:-default}" "$size_bytes" "$backup_url" "$volume_name")

  if [[ "$dry_run" == "true" ]]; then
    echo
    echo "-------------------- DRY-RUN: $pvc --------------------"
    echo "$manifest"
    echo "-------------------- END DRY-RUN --------------------"
    return 0
  fi

  # Apply manifests (Volume + PVC) in one go
  if ! echo "$manifest" | kubectl apply -f - >/dev/null; then
      error "failed to apply manifests for $pvc"
      return 1
  fi

  # # Apply Volume
  # echo "$manifest" | awk '/^---$/ {exit} {print}' | kubectl apply -f - >/dev/null \
  #   || { error "failed to apply Longhorn Volume manifest for $volume_name"; return 1; }

  # # Apply PVC
  # echo "$manifest" | awk 'NR>1{p=0} /^---$/ {p=1; next} p==1{print}' | kubectl apply -f - >/dev/null \
  #   || { error "failed to apply PVC manifest for $pvc"; return 1; }

  info "Restore requested for $pvc (namespace: ${ns:-default}). Monitor Longhorn UI for progress."
}

# -------------------------
# Restore commands
# -------------------------
cmd_restore_one() {
  local target="$1"; shift || true
  local dry_run="$GLOBAL_DRY_RUN"; local force="$GLOBAL_FORCE"
  for f in "$@"; do case "$f" in --dry-run) dry_run="true" ;; --force) force="true" ;; esac; done

  if [[ -z "$target" ]]; then error "restore-one requires a target"; return 1; fi

  if kubectl get backupvolumes.longhorn.io -n "$LONGHORN_NS" "$target" >/dev/null 2>&1; then
    restore_backupvolume "$target" "$dry_run" "$force"
    return $?
  fi

  mapfile -t matches < <(kubectl get backupvolumes.longhorn.io -n "$LONGHORN_NS" -o json |
    jq -r --arg t "$target" '.items[] | select((.status.labels["KubernetesStatus"] // "") | contains($t)) | "\(.metadata.name)|\(.status.lastBackupAt)"')
  [[ ${#matches[@]} -eq 0 ]] && { error "No backupVolume found matching '$target'"; return 1; }

  selected=$(printf "%s\n" "${matches[@]}" | sort -t'|' -k2 -r | head -n1 | cut -d'|' -f1)
  info "Selected backupVolume: $selected"
  restore_backupvolume "$selected" "$dry_run" "$force"
}

cmd_restore_tier() {
  local tier="$1"; shift || true
  local dry_run="$GLOBAL_DRY_RUN"; local force="$GLOBAL_FORCE"
  for f in "$@"; do case "$f" in --dry-run) dry_run="true" ;; --force) force="true" ;; esac; done
  [[ -z "$tier" ]] && { error "restore-tier requires a tier"; return 1; }

  info "Finding volumes labeled data-tier = $tier"
  mapfile -t vols < <(kubectl get backupvolumes.longhorn.io -n "$LONGHORN_NS" -o json |
    jq -r --arg t "$tier" '.items[] | select((.status.labels["data-tier"] // .status.labels["Data - Tier"] // "") == $t) | .metadata.name')
  [[ ${#vols[@]} -eq 0 ]] && { warn "No backupVolumes found for data-tier '$tier'"; return 0; }

  for v in "${vols[@]}"; do restore_backupvolume "$v" "$dry_run" "$force"; done
}

cmd_restore_all() {
  local dry_run="$GLOBAL_DRY_RUN"; local force="$GLOBAL_FORCE"
  for f in "$@"; do case "$f" in --dry-run) dry_run="true" ;; --force) force="true" ;; esac; done

  info "Restoring ALL backupVolumes in $LONGHORN_NS"
  mapfile -t vols < <(kubectl get backupvolumes.longhorn.io -n "$LONGHORN_NS" -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n')
  for v in "${vols[@]}"; do restore_backupvolume "$v" "$dry_run" "$force"; done
}

# -------------------------
# Main
# -------------------------
main() {
  if [[ $# -lt 1 ]]; then
    cat <<EOF
Usage:
  $0 list
      - List backupVolumes with details.

  $0 restore-one <backupVolume-or-pvc-name> [--dry-run] [--force]
      - Restore a single volume. Accepts backupVolume name or PVC name fragment.

  $0 restore-tier <tier> [--dry-run] [--force]
      - Restore all volumes labeled with data-tier = <tier>.

  $0 restore-all [--dry-run] [--force]
      - Restore all volumes.

Global flags:
  --dry-run   (prints YAML only)
  --force     (force restore even if PV/PVC exists)
EOF
    exit 1
  fi

  parse_global_flags "$@"
  cmd="$1"; shift

  case "$cmd" in
    list) list_backups ;;
    restore-one) cmd_restore_one "$@" ;;
    restore-tier) cmd_restore_tier "$@" ;;
    restore-all) cmd_restore_all "$@" ;;
    *) error "Unknown command: $cmd"; exit 1 ;;
  esac
}

main "$@"
