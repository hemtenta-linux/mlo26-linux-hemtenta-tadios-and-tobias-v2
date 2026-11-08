#!/usr/bin/env bash

set -euo pipefail
umask 077

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this script with sudo."
    exit 1
fi

# Accept a normal run or a manual notification test.
if [[ "$#" -gt 1 || ( "$#" -eq 1 && "$1" != "--test" ) ]]; then
    echo "Usage: todo-api-monitor [--test]"
    exit 1
fi

# Load settings from the root-owned file installed by install-config.sh.
source /etc/todo-api/monitor.env

if [[ -z "$DISCORD_WEBHOOK_URL" ]]; then
    echo "Set DISCORD_WEBHOOK_URL in /etc/todo-api/monitor.env first."
    exit 1
fi

# Convert the message to JSON and send it to Discord.
send_notification() {
    local message="$1"
    local payload

    payload=$(printf '%s' "$message" | python3 -c '
import json
import sys

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

# Test delivery without changing the monitoring state.
if [[ "${1:-}" == "--test" ]]; then
    send_notification "TEST: Monitoring works on $(hostname)."
    echo "Test notification sent."
    exit 0
fi

state_dir=/var/lib/todo-api-monitor
mkdir -p "$state_dir"
chmod 700 "$state_dir"

# Prevent overlapping monitoring runs.
exec 9>"$state_dir/monitor.lock"
if ! flock -n 9; then
    echo "Another monitoring check is running."
    exit 0
fi

status=ok
message=""

# Read the percentage used on the root filesystem.
disk_usage=$(df -P / | awk 'NR == 2 {gsub(/%/, "", $5); print $5}')

if (( disk_usage >= DISK_THRESHOLD )); then
    status=problem
    message+="Disk usage is ${disk_usage}%."
    message+=$'\n'
fi

# Require HTTP 200 from nginx's readiness endpoint.
# A failed curl request is handled as a monitoring problem below.
http_status=$(curl --silent \
    --connect-timeout 3 --max-time 10 \
    --output /dev/null --write-out '%{http_code}' \
    "$MONITOR_URL" || true)

if [[ "$http_status" != "200" ]]; then
    status=problem
    message+="API readiness check failed."
    message+=$'\n'
fi

# Remember the last successfully delivered notification.
state_file="$state_dir/last-notification"
last_status=ok
last_sent=0

if [[ -f "$state_file" ]]; then
    read -r last_status last_sent < "$state_file"
fi

now=$(date +%s)

if [[ "$status" == "ok" ]]; then
    echo "Monitoring OK."

    # No notification is needed if everything was already healthy.
    if [[ "$last_status" == "ok" ]]; then
        exit 0
    fi

    message="RECOVERY: API readiness and disk usage are normal on $(hostname)."
else
    echo "$message"

    # Wait before repeating an alert for an ongoing problem.
    if [[ "$last_status" == "problem" ]] \
        && (( now - last_sent < COOLDOWN_SECONDS )); then
        echo "Waiting for the notification cooldown."
        exit 0
    fi

    message="ALERT on $(hostname):"$'\n'"$message"
fi

send_notification "$message"

# Save state only after Discord accepts the notification.
printf '%s %s\n' "$status" "$now" > "$state_file.tmp"
mv "$state_file.tmp" "$state_file"

echo "Notification sent."