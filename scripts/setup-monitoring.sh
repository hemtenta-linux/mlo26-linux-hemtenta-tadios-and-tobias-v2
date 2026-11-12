#!/usr/bin/env bash

set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this script with sudo bash scripts/setup-monitoring.sh"
    exit 1
fi

cd /home/api/todo-api

# Check that the required files exist.
for file in \
    scripts/monitor.sh \
    deploy/monitor.env \
    deploy/todo-api-monitor.cron
do
    if [[ ! -f "$file" ]]; then
        echo "Missing required file: $file"
        exit 1
    fi
done

# Check the script syntax before installing it.
bash -n scripts/monitor.sh

install -o root -g root -m 750 \
    scripts/monitor.sh /usr/local/sbin/todo-api-monitor

# Install settings only if they do not already exist.
install -d -o root -g root -m 700 /etc/todo-api

if [[ ! -f /etc/todo-api/monitor.env ]]; then
    install -o root -g root -m 600 \
        deploy/monitor.env /etc/todo-api/monitor.env
fi

# Remove Windows line endings and protect the webhook.
sed -i 's/\r$//' /etc/todo-api/monitor.env
chown root:root /etc/todo-api/monitor.env
chmod 600 /etc/todo-api/monitor.env

# Prepare the log without deleting existing entries.
touch /var/log/todo-api-monitor.log
chown root:root /var/log/todo-api-monitor.log
chmod 600 /var/log/todo-api-monitor.log

# Install the automatic monitoring schedule.
install -o root -g root -m 644 \
    deploy/todo-api-monitor.cron /etc/cron.d/todo-api-monitor

printf '\n' >> /etc/cron.d/todo-api-monitor

# Remove the old combined schedule once both separate schedules exist.
if [[ -f /etc/cron.d/todo-api-backup ]]; then
    rm -f /etc/cron.d/todo-api
fi

systemctl enable --now cron

echo "Monitoring script and schedule installed."
echo "Configure /etc/todo-api/monitor.env."
echo "Test with: sudo /usr/local/sbin/todo-api-monitor --test"