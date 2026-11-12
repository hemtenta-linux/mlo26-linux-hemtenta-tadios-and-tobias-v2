#!/usr/bin/env bash

set -euo pipefail
umask 077


# Use a predictable command search path, including when run by cron.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# The settings file is readable only by root.
if [[ "$EUID" -ne 0 ]]; then
    echo "Run this script with sudo."
    exit 1
fi

if [[ "$#" -gt 1 || ( "$#" -eq 1 && "$1" != "--test" ) ]]; then
    echo "Usage: todo-api-monitor [--test]"
    exit 1
fi

source /etc/todo-api/monitor.env

if [[ -z "${DISCORD_WEBHOOK_URL:-}" ]]; then
    echo "Configure DISCORD_WEBHOOK_URL first."
    exit 1
fi

# Encode the message safely as JSON and send it to Discord.
send_notification() {
    local payload

    payload=$(printf '%s' "$1" | python3 -c '
import json, sys
print(json.dumps({
    "content": sys.stdin.read(),
    "allowed_mentions": {"parse": []}
}))
')

    curl --fail --silent --show-error \
        --connect-timeout 5 --max-time 15 \
        --header "Content-Type: application/json" \
        --data-binary "$payload" \
        "$DISCORD_WEBHOOK_URL" > /dev/null
}

# Test delivery without performing checks or changing the cooldown.
if [[ "${1:-}" == "--test" ]]; then
    send_notification "TEST: Monitoring works on $(hostname)."
    echo "Test notification sent."
    exit 0
fi

state_dir=/var/lib/todo-api-monitor
install -d -m 700 "$state_dir"

# Prevent two monitoring runs from sending alerts simultaneously.
exec 9>"$state_dir/monitor.lock"
if ! flock -n 9; then
    echo "Another monitoring check is running."
    exit 0
fi

message=""

# Check root filesystem usage.
disk_usage=$(df -P / | awk 'NR == 2 {gsub(/%/, "", $5); print $5}')

if (( disk_usage >= DISK_THRESHOLD )); then
    message+="Disk usage is ${disk_usage}%. "
fi

# Check API readiness. Continue even if the request fails.
http_status=$(curl --silent \
    --connect-timeout 3 --max-time 10 \
    --output /dev/null --write-out '%{http_code}' \
    "$MONITOR_URL" || true)

if [[ "$http_status" != "200" ]]; then
    message+="API readiness check failed. "
fi

# Count suspicious SSH log entries from the last five minutes.
ssh_events=$(
    journalctl -u ssh.service \
        --since "5 minutes ago" \
        --no-pager -o cat |
    awk '
        /Failed password|Failed publickey|Invalid user/ { count++ }
        END { print count + 0 }
    '
)

if (( ssh_events >= SSH_THRESHOLD )); then
    message+="SSH: ${ssh_events} suspicious log entries in the last 5 minutes. "
fi

# Use the last alert's timestamp to limit repeated notifications.
alert_file="$state_dir/last-alert"
cooldown=${COOLDOWN_SECONDS:-1800}

if [[ -z "$message" ]]; then
    echo "Monitoring OK."

    rm -f "$alert_file"
    exit 0
fi

echo "$message"

if [[ -f "$alert_file" ]]; then
    last_sent=$(stat -c %Y "$alert_file")
    now=$(date +%s)

    if (( now - last_sent < cooldown )); then
        echo "Waiting for the notification cooldown."
        exit 0
    fi
fi

send_notification "ALERT on $(hostname): $message"

touch "$alert_file"
echo "Alert sent."