#!/usr/bin/env bash

set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this script with sudo bash scripts/setup-monitoring.sh"
    exit 1
fi

cd /home/api/todo-api


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

bash -n scripts/monitor.sh

install -o root -g root -m 750 \
    scripts/monitor.sh /usr/local/sbin/todo-api-monitor


install -d -o root -g root -m 700 /etc/todo-api

if [[ ! -f /etc/todo-api/monitor.env ]]; then
    install -o root -g root -m 600 \
        deploy/monitor.env /etc/todo-api/monitor.env
fi


sed -i 's/\r$//' /etc/todo-api/monitor.env
chown root:root /etc/todo-api/monitor.env
chmod 600 /etc/todo-api/monitor.env


touch /var/log/todo-api-monitor.log
chown root:root /var/log/todo-api-monitor.log
chmod 600 /var/log/todo-api-monitor.log


install -o root -g root -m 644 \
    deploy/todo-api-monitor.cron /etc/cron.d/todo-api-monitor

printf '\n' >> /etc/cron.d/todo-api-monitor


if [[ -f /etc/cron.d/todo-api-backup ]]; then
    rm -f /etc/cron.d/todo-api
fi

systemctl enable --now cron

echo "Monitoring script and schedule installed."
echo "Configure /etc/todo-api/monitor.env."
echo "Test with: sudo /usr/local/sbin/todo-api-monitor --test"