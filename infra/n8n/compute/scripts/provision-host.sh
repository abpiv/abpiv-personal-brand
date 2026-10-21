#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "provision-host.sh must run as root" >&2
  exit 1
fi

: "${RELEASE_DIR:?Set RELEASE_DIR to the uploaded compute runtime directory}"
: "${GCP_PROJECT_ID:?Set GCP_PROJECT_ID}"
: "${BACKUP_BUCKET:?Set BACKUP_BUCKET}"

DATA_DEVICE="/dev/disk/by-id/google-abpiv-n8n-data"
DATA_MOUNT="/srv/n8n"

if [ ! -b "$DATA_DEVICE" ]; then
  echo "Attached data disk not found at $DATA_DEVICE" >&2
  exit 1
fi

if ! blkid "$DATA_DEVICE" >/dev/null 2>&1; then
  mkfs.ext4 -F -L abpiv-n8n-data "$DATA_DEVICE"
fi

data_uuid="$(blkid -s UUID -o value "$DATA_DEVICE")"
install -d -m 0755 "$DATA_MOUNT"
if ! grep -Fq "UUID=${data_uuid} ${DATA_MOUNT} " /etc/fstab; then
  sed -i "\\| ${DATA_MOUNT} |d" /etc/fstab
  printf 'UUID=%s %s ext4 defaults 0 2\n' "$data_uuid" "$DATA_MOUNT" >> /etc/fstab
fi
mount "$DATA_MOUNT" 2>/dev/null || mount --all
findmnt --noheadings --output UUID --target "$DATA_MOUNT" | grep -Fx "$data_uuid" >/dev/null
install -d -m 0755 /etc/abpiv-n8n
printf '%s\n' "$data_uuid" > /etc/abpiv-n8n/data-disk.uuid
chmod 0644 /etc/abpiv-n8n/data-disk.uuid

install -d -m 0700 "$DATA_MOUNT/postgres" "$DATA_MOUNT/backups" "$DATA_MOUNT/migration"
install -d -m 0750 "$DATA_MOUNT/state" "$DATA_MOUNT/binary"
chown -R 70:70 "$DATA_MOUNT/postgres"
chown -R 1000:1000 "$DATA_MOUNT/state" "$DATA_MOUNT/binary"

install -d -m 0755 /opt/abpiv-n8n
rsync --archive --delete --exclude tests/ --exclude nginx/current.conf "$RELEASE_DIR/" /opt/abpiv-n8n/
find /opt/abpiv-n8n/scripts -type f -name '*.sh' -exec chmod 0755 {} +
cp /opt/abpiv-n8n/nginx/maintenance.conf /opt/abpiv-n8n/nginx/current.conf
install -m 0755 /opt/abpiv-n8n/scripts/configure-container-firewall.sh /usr/local/sbin/abpiv-container-firewall
install -d -m 0755 /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/abpiv-container-firewall.conf <<'EOF'
[Service]
ExecStartPost=/usr/local/sbin/abpiv-container-firewall --enforce
EOF

cat > /etc/abpiv-n8n/runtime.conf <<EOF
GCP_PROJECT_ID=${GCP_PROJECT_ID}
BACKUP_BUCKET=${BACKUP_BUCKET}
COMPOSE_DIR=/opt/abpiv-n8n
EOF
chmod 0644 /etc/abpiv-n8n/runtime.conf
printf '%s\n' "stopped" > /etc/abpiv-n8n/mode

install -m 0644 /opt/abpiv-n8n/systemd/abpiv-n8n.service /etc/systemd/system/abpiv-n8n.service
install -m 0644 /opt/abpiv-n8n/systemd/abpiv-cloudflared.service /etc/systemd/system/abpiv-cloudflared.service
install -m 0644 /opt/abpiv-n8n/systemd/abpiv-n8n-backup.service /etc/systemd/system/abpiv-n8n-backup.service
install -m 0644 /opt/abpiv-n8n/systemd/abpiv-n8n-backup.timer /etc/systemd/system/abpiv-n8n-backup.timer
install -m 0644 /opt/abpiv-n8n/systemd/abpiv-n8n-health.service /etc/systemd/system/abpiv-n8n-health.service
install -m 0644 /opt/abpiv-n8n/systemd/abpiv-n8n-health.timer /etc/systemd/system/abpiv-n8n-health.timer
systemctl daemon-reload
systemctl disable --now abpiv-n8n.service abpiv-cloudflared.service abpiv-n8n-backup.timer abpiv-n8n-health.timer >/dev/null 2>&1 || true
/usr/local/sbin/abpiv-container-firewall --enforce
systemctl cat docker.service | grep -F 'ExecStartPost=/usr/local/sbin/abpiv-container-firewall --enforce' >/dev/null

install -d -m 0700 /run/n8n /run/cloudflared
install -m 0600 /dev/null /run/n8n/runtime.env
install -m 0600 /dev/null /run/n8n/postgres.env
/opt/abpiv-n8n/scripts/assert-data-disk.sh
docker compose --project-directory /opt/abpiv-n8n --file /opt/abpiv-n8n/docker-compose.yml config --quiet
docker compose --project-directory /opt/abpiv-n8n --file /opt/abpiv-n8n/docker-compose.yml pull --quiet
/opt/abpiv-n8n/scripts/restore-rehearsal.sh

# Host provisioning must leave every production runtime container stopped.
docker compose --project-directory /opt/abpiv-n8n --file /opt/abpiv-n8n/docker-compose.yml down --remove-orphans
rm -f /run/n8n/runtime.env /run/n8n/postgres.env /run/n8n/postgres-password /run/n8n/encryption-key /run/cloudflared/token

echo "Host provisioned; production containers and Tunnel remain stopped."
