#!/usr/bin/env bash

set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this script with sudo bash scripts/setup-backup.sh"
    exit 1
fi

cd /home/api/todo-api

for file in scripts/backup.sh deploy/todo-api-backup.cron; do
    if [[ ! -f "$file" ]]; then
        echo "Missing required file: $file"
        exit 1
    fi
done


bash -n scripts/backup.sh


install -o root -g root -m 750 \
    scripts/backup.sh /usr/local/sbin/todo-api-backup


install -d -o root -g root -m 700 /var/backups/todo-api

touch /var/log/todo-api-backup.log
chown root:root /var/log/todo-api-backup.log
chmod 600 /var/log/todo-api-backup.log


install -o root -g root -m 644 \
    deploy/todo-api-backup.cron /etc/cron.d/todo-api-backup

printf '\n' >> /etc/cron.d/todo-api-backup


if [[ -f /etc/cron.d/todo-api-monitor ]]; then
    rm -f /etc/cron.d/todo-api
fi

systemctl enable --now cron

echo "Backup script and daily schedule installed."
echo "Test with: sudo /usr/local/sbin/todo-api-backup"
