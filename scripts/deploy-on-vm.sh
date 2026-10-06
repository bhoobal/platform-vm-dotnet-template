#!/usr/bin/env bash
# Runs ON the VM via `az vm run-command invoke` (no SSH, no inbound access needed).
# Downloads a release zip from blob storage using the VM's managed identity, switches the
# `current` symlink, restarts the service, health-checks it, and rolls back on failure.
#
# Usage: deploy-on-vm.sh <storageAccount> <container> <blobName> <releaseId> <port> <keyVaultName> [secretName]
set -euo pipefail

ACCOUNT="$1"; CONTAINER="$2"; BLOB="$3"; RELEASE="$4"; PORT="${5:-8080}"
KEY_VAULT_NAME="$6"; SECRET_NAME="${7:-api-key}"
BASE=/opt/app
REL_DIR="$BASE/releases/$RELEASE"
PREVIOUS="$(readlink -f "$BASE/current" 2>/dev/null || true)"

command -v unzip >/dev/null || { apt-get update -qq && apt-get install -y -qq unzip; }

echo "[deploy] fetching token from IMDS"
TOKEN=$(curl -fsS -H 'Metadata: true' \
  'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F' \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')

echo "[deploy] downloading $BLOB"
mkdir -p "$REL_DIR"
curl -fsS \
  -H "Authorization: Bearer $TOKEN" -H 'x-ms-version: 2022-11-02' \
  "https://${ACCOUNT}.blob.core.windows.net/${CONTAINER}/${BLOB}" -o "/tmp/${RELEASE}.zip"
unzip -oq "/tmp/${RELEASE}.zip" -d "$REL_DIR"
rm -f "/tmp/${RELEASE}.zip"
chmod +x "$REL_DIR/SampleService"
chown -R svc:svc "$REL_DIR"

echo "[deploy] retrieving API key from Key Vault"
KEY_VAULT_TOKEN=$(curl -fsS -H 'Metadata: true' \
  'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net%2F' \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')

SECRET_URL="https://${KEY_VAULT_NAME}.vault.azure.net/secrets/${SECRET_NAME}?api-version=7.4"
SECRET_RESPONSE=''
for attempt in $(seq 1 12); do
  if SECRET_RESPONSE=$(curl -fsS -H "Authorization: Bearer $KEY_VAULT_TOKEN" "$SECRET_URL" 2>/dev/null); then
    break
  fi
  if [ "$attempt" -lt 12 ]; then sleep 10; fi
done
[ -n "$SECRET_RESPONSE" ] || { echo "[deploy] unable to retrieve Key Vault secret '$SECRET_NAME'"; exit 1; }

install -d -o root -g svc -m 0750 /etc/app
printf '%s' "$SECRET_RESPONSE" | python3 -c '
import grp
import json
import os
import sys

path = sys.argv[1]
value = json.load(sys.stdin)["value"]
if not value or any(char in value for char in "\r\n\0"):
    raise SystemExit("Key Vault secret must be a non-empty, single-line value")

value = value.replace("\\", "\\\\").replace("\"", "\\\"")
try:
    with open(path, encoding="utf-8") as current:
        lines = [line for line in current if not line.startswith("API_KEY=")]
except FileNotFoundError:
    lines = []

temporary_path = f"{path}.tmp.{os.getpid()}"
with open(temporary_path, "w", encoding="utf-8") as env_file:
    env_file.writelines(lines)
    env_file.write(f"API_KEY=\"{value}\"\n")
os.chmod(temporary_path, 0o640)
os.chown(temporary_path, 0, grp.getgrnam("svc").gr_gid)
os.replace(temporary_path, path)
' /etc/app/app.env

echo "[deploy] switching to release $RELEASE"
ln -sfn "$REL_DIR" "$BASE/current"
systemctl restart app.service

healthy() {
  for _ in $(seq 1 15); do
    code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/health" || true)
    [ "$code" = "200" ] && return 0
    sleep 2
  done
  return 1
}

if healthy; then
  echo "[deploy] DEPLOY_OK release=$RELEASE"
  # keep the 3 newest releases for fast rollback
  ls -1dt "$BASE"/releases/* | tail -n +4 | xargs -r rm -rf
else
  echo "[deploy] health check failed"
  journalctl -u app.service -n 30 --no-pager || true
  if [ -n "$PREVIOUS" ] && [ -d "$PREVIOUS" ]; then
    echo "[deploy] rolling back to $PREVIOUS"
    ln -sfn "$PREVIOUS" "$BASE/current"
    systemctl restart app.service
  fi
  echo "[deploy] DEPLOY_FAILED release=$RELEASE"
  exit 1
fi
