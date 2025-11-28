#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# CONFIG
# ------------------------------------------------------------
CONTROLLER_NS="sealed-secrets"
CONTROLLER_SECRET="sealed-secrets-key"
LOCAL_BOOTSTRAP_FILE="infrastructure/controllers/sealed-secrets/sealed-secrets-key.yaml"
SEARCH_DIRS=("infrastructure" "monitoring" "user-apps")
SEALED_PATTERN="*-sealed.yaml"
DAYS_VALID=365

ROTATE_TMP="./.sealed-secrets-rotation"
mkdir -p "$ROTATE_TMP"

OLD_KEY_PEM="$ROTATE_TMP/old.key.pem"
OLD_CERT_PEM="$ROTATE_TMP/old.crt.pem"
NEW_KEY_PEM="$ROTATE_TMP/new.key.pem"
NEW_CERT_PEM="$ROTATE_TMP/new.crt.pem"

# ------------------------------------------------------------
# Verify TMP exists
# ------------------------------------------------------------
if [[ ! -d "$ROTATE_TMP" ]]; then
  echo "ERROR: mktemp directory was not created: $ROTATE_TMP" >&2
  exit 1
fi

# ------------------------------------------------------------
# Cleanup mode
# ------------------------------------------------------------
if [[ "${1:-}" == "cleanup" ]]; then
    echo "Cleanup mode. Removing backup files..."

    # remove rotation tmp folder
    if [[ -d "$ROTATE_TMP" ]]; then
        rm -rf "$ROTATE_TMP"
        echo "   ✔ removed folder: $ROTATE_TMP"
    else
        echo "   ⚠ nothing to remove at: $ROTATE_TMP"
    fi

    # remove all *.bak files next to sealed secrets
    find ./infrastructure ./monitoring ./user-apps -type f -name "*-sealed.yaml.bak" -exec rm -v {} \; || true

    echo "Cleanup completed."
    exit 0
fi

# ------------------------------------------------------------
# 1. Extract old controller keypair from cluster secret
# ------------------------------------------------------------
echo "1) Extracting tls.key & tls.crt from secret: ${CONTROLLER_SECRET}"

kubectl -n "${CONTROLLER_NS}" get secret "${CONTROLLER_SECRET}" \
  -o jsonpath='{.data.tls\.key}' | base64 -d > "${OLD_KEY_PEM}"

kubectl -n "${CONTROLLER_NS}" get secret "${CONTROLLER_SECRET}" \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > "${OLD_CERT_PEM}"

if [[ ! -s "$OLD_KEY_PEM" ]]; then
    echo "ERROR: tls.key could not be extracted." >&2
    exit 1
fi

echo "   ✔ extracted private key: ${OLD_KEY_PEM}"
echo "   ✔ extracted public cert: ${OLD_CERT_PEM}"
echo

# ------------------------------------------------------------
# 2. Generate new keypair for secrets resealing
# ------------------------------------------------------------
echo "2) Generating new keypair..."

openssl req -x509 -nodes -newkey rsa:4096 \
    -keyout "${NEW_KEY_PEM}" \
    -out "${NEW_CERT_PEM}" \
    -days ${DAYS_VALID} \
    -subj "/CN=sealed-secrets" >/dev/null 2>&1

echo "   ✔ new key: ${NEW_KEY_PEM}"
echo "   ✔ new cert: ${NEW_CERT_PEM}"
echo

# ------------------------------------------------------------
# 3. Write new/rotated sealed-secrets-key.yaml
# ------------------------------------------------------------
echo "3) Updating local bootstrap sealed-secrets-key.yaml..."

if [[ -f "${LOCAL_BOOTSTRAP_FILE}" ]]; then
    # copy the original to ROTATE_TMP as backup
    mkdir -p "${ROTATE_TMP}"
    cp "${LOCAL_BOOTSTRAP_FILE}" "${ROTATE_TMP}/sealed-secrets-key.yaml.bak"
    echo "   ✔ backup created in: ${ROTATE_TMP}/sealed-secrets-key.yaml.bak"
fi

# encode new keypair to base64
crt_b64=$(base64 -w0 < "${NEW_CERT_PEM}")
key_b64=$(base64 -w0 < "${NEW_KEY_PEM}")

# write new bootstrap secret
cat > "${LOCAL_BOOTSTRAP_FILE}" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: sealed-secrets-key
  namespace: ${CONTROLLER_NS}
type: kubernetes.io/tls
data:
  tls.crt: ${crt_b64}
  tls.key: ${key_b64}
EOF

echo "   ✔ secret keys manifest file updated: ${LOCAL_BOOTSTRAP_FILE}"
echo

# ------------------------------------------------------------
# 4. Find & process all *-sealed.yaml files
# ------------------------------------------------------------
echo "4) Processing sealed secrets..."

mapfile -t FILES < <(find "${SEARCH_DIRS[@]}" -type f -name "${SEALED_PATTERN}")

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "No sealed files found matching ${SEALED_PATTERN}"
    exit 0
fi

echo "Found ${#FILES[@]} sealed secrets:"
printf "  - %s\n" "${FILES[@]}"
echo

for f in "${FILES[@]}"; do
    echo "  Resealing: ${f}"

    bak="${f}.bak"
    if [[ ! -f "$bak" ]]; then
        cp "${f}" "${bak}"
        echo "   ✔ backup: ${bak}"
    else
        echo "   ✔ backup already exists"
    fi

    decoded="$ROTATE_TMP/decoded-$(basename "$f")"
    resealed="$ROTATE_TMP/resealed-$(basename "$f")"

    # ---- decode using old private key ----
    kubeseal --recovery-unseal \
      --recovery-private-key "${OLD_KEY_PEM}" \
      < "${f}" > "${decoded}"

    echo "   ✔ decoded"

    # ---- reseal using NEW cert ----
    kubeseal --format yaml --scope=cluster-wide \
      --cert "${NEW_CERT_PEM}" \
      < "${decoded}" > "${resealed}"

    echo "   ✔ resealed"

    # ---- replace file ----
    mv "${resealed}" "${f}"
done

echo
echo "DONE — all secrets resealed using new keypair."
echo

# ------------------------------------------------------------
# FINAL INSTRUCTIONS
# ------------------------------------------------------------
cat <<EOF
Next steps:

1) Commit all changed files:
   git add *-sealed.yaml
   git commit -m "<message>"
   git push

2) Apply the updated sealed-secrets-key.yaml to the cluster:
   kubectl replace -f ${LOCAL_BOOTSTRAP_FILE}

3) Redeploy the sealed-secrets controller to load the new keypair:
      kubectl -n ${CONTROLLER_NS} rollout restart deploy/sealed-secrets

4) Wait until ArgoCD syncs to the new sealed secrets. Verify that all sealed secrets are unsealed correctly.

5) Optionally, after verifying everything is working, delete the backup files in:
   ${ROTATE_TMP} and the *.bak files next to each sealed secret.
   Note: You can run this script in cleanup mode to do this automatically:
      ./scripts/rotate-seal-key.sh cleanup
EOF