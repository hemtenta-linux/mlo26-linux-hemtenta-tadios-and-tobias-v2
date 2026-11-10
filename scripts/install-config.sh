#!/usr/bin/env bash

set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this script with sudo bash scripts/install-config.sh"
    exit 1
fi

cd /home/api/todo-api

# Check the files needed for Docker deployment.
for file in \
    /etc/todo-api/api.env \
    Dockerfile \
    compose.yaml \
    deploy/nginx-todo-api.conf \
    deploy/todo-api.cron \
    deploy/monitor.env \
    scripts/backup.sh \
    scripts/monitor.sh
do
    if [[ ! -f "$file" ]]; then
        echo "Missing required file: $file"
        exit 1
    fi
done

# Check script syntax before installing the scheduled jobs.
bash -n scripts/backup.sh
bash -n scripts/monitor.sh

install -o root -g root -m 750 \
    scripts/backup.sh /usr/local/sbin/todo-api-backup

install -o root -g root -m 750 \
    scripts/monitor.sh /usr/local/sbin/todo-api-monitor

# Preserve the server's existing webhook settings.
if [[ ! -f /etc/todo-api/monitor.env ]]; then
    install -o root -g root -m 600 \
        deploy/monitor.env /etc/todo-api/monitor.env
fi

# Preserve existing nginx settings, including future HTTPS configuration.
if [[ ! -f /etc/nginx/sites-available/todo-api ]]; then
    install -o root -g root -m 644 \
        deploy/nginx-todo-api.conf /etc/nginx/sites-available/todo-api
fi

ln -sfn /etc/nginx/sites-available/todo-api \
    /etc/nginx/sites-enabled/todo-api

rm -f /etc/nginx/sites-enabled/default

nginx -t

# Validate Compose and build before stopping the systemd API.
systemctl enable --now docker

docker compose --env-file /etc/todo-api/api.env config --quiet
docker compose --env-file /etc/todo-api/api.env build api

# Free port 8000 if the process-manager demonstration was installed.
if systemctl cat todo-api.service > /dev/null 2>&1; then
    systemctl disable --now todo-api.service
fi

# Start both containers and wait for their health checks.
docker compose --env-file /etc/todo-api/api.env \
    up -d --wait --wait-timeout 120

systemctl enable --now nginx cron
systemctl reload nginx

# Verify the complete path through nginx, the API and PostgreSQL.
curl --fail --show-error --silent \
    --retry 10 --retry-all-errors --retry-delay 1 \
    --retry-max-time 30 --max-time 3 \
    http://127.0.0.1/ready

touch /var/log/todo-api-backup.log /var/log/todo-api-monitor.log
chmod 600 /var/log/todo-api-backup.log /var/log/todo-api-monitor.log

install -o root -g root -m 644 \
    deploy/todo-api.cron /etc/cron.d/todo-api

# Ensure the cron file ends with a newline.
printf '\n' >> /etc/cron.d/todo-api

echo
echo "Docker deployment finished."