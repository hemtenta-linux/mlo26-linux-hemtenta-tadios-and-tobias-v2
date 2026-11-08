#!/usr/bin/env bash

set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this script with sudo bash scripts/install-config.sh"
    exit 1
fi

cd /home/api/todo-api

# Check required files before installing anything.
for file in \
    /etc/todo-api/api.env \
    deploy/todo-api.service \
    deploy/nginx-todo-api.conf \
    deploy/todo-api.cron \
    deploy/monitor.env.example \
    scripts/backup.sh \
    scripts/monitor.sh
do
    if [[ ! -f "$file" ]]; then
        echo "Missing required file: $file"
        exit 1
    fi
done

# Create the Python environment and install dependencies as the API user.
sudo -u api -H python3 -m venv venv
sudo -u api -H venv/bin/python -m pip install -r requirements.txt

# Install the service and scheduled scripts with root ownership.
install -o root -g root -m 644 \
    deploy/todo-api.service /etc/systemd/system/todo-api.service

install -o root -g root -m 750 \
    scripts/backup.sh /usr/local/sbin/todo-api-backup

install -o root -g root -m 750 \
    scripts/monitor.sh /usr/local/sbin/todo-api-monitor

# Keep existing monitoring settings when running this script again.
if [[ ! -f /etc/todo-api/monitor.env ]]; then
    install -o root -g root -m 600 \
        deploy/monitor.env.example /etc/todo-api/monitor.env
fi

# Keep an existing nginx configuration, including future HTTPS settings.
if [[ ! -f /etc/nginx/sites-available/todo-api ]]; then
    install -o root -g root -m 644 \
        deploy/nginx-todo-api.conf /etc/nginx/sites-available/todo-api
fi

# Enable our site and remove Ubuntu's default site link.
ln -sfn /etc/nginx/sites-available/todo-api \
    /etc/nginx/sites-enabled/todo-api

rm -f /etc/nginx/sites-enabled/default

# Check configurations before starting the API.
nginx -t
systemd-analyze verify /etc/systemd/system/todo-api.service

# Reload service definitions and start the services.
systemctl daemon-reload
systemctl enable todo-api
systemctl restart todo-api

systemctl enable --now nginx cron
systemctl reload nginx

# Wait briefly for the API and database to become ready through nginx.
curl --fail --show-error --silent \
    --retry 10 --retry-connrefused --retry-delay 1 \
    --retry-max-time 30 --max-time 3 \
    http://127.0.0.1/ready

# Create private log files for scheduled jobs.
touch /var/log/todo-api-backup.log /var/log/todo-api-monitor.log
chmod 600 /var/log/todo-api-backup.log /var/log/todo-api-monitor.log

# Install the schedule after the readiness check succeeds.
install -o root -g root -m 644 \
    deploy/todo-api.cron /etc/cron.d/todo-api

echo
echo "Installation finished."
echo "Configure the Discord webhook in /etc/todo-api/monitor.env."