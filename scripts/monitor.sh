#!/usr/bin/env bash
# Check root-disk usage and API readiness, then send Discord alerts when needed.
# Cron runs the installed copy every five minutes. --test sends a labelled test message.

# Stop on unhandled errors, unset variables and failed pipeline stages.
set -Eeuo pipefail
# State and temporary files receive owner-only default permissions.
umask 077

# Report a configuration or runtime failure to stderr with a failing exit status.
fail() {
    printf 'Monitoring failed: %s\n' "$1" >&2
    exit 1
}

# Root can read the protected webhook settings and write the monitoring state.
[[ "$EUID" -eq 0 ]] || fail "Run this script as root."
# Accept either a normal scheduled run or the explicit manual test option.
test_mode=false
if [[ "$#" -eq 1 && "$1" == '--test' ]]; then
    test_mode=true
elif [[ "$#" -ne 0 ]]; then
    fail "Usage: todo-api-monitor [--test]"
fi

# Validate the owner and permissions before sourcing the settings as trusted Bash code.
CONFIG_FILE="${MONITOR_CONFIG:-/etc/todo-api/monitor.env}"
[[ "$CONFIG_FILE" == /* ]] || fail "MONITOR_CONFIG must be an absolute path."
if [[ -e "$CONFIG_FILE" ]]; then
    [[ -f "$CONFIG_FILE" && ! -L "$CONFIG_FILE" ]] || fail "The configuration must be a regular file."
    [[ "$(stat -c %u -- "$CONFIG_FILE")" -eq 0 ]] || fail "The configuration must belong to root."
    config_mode="$(stat -c %a -- "$CONFIG_FILE")"
    (( (8#$config_mode & 077) == 0 )) || fail "The configuration must only be accessible to root."
    # This is a trusted, root-owned shell configuration file.
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# Apply defaults to settings that are missing or empty after the configuration is loaded.
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"
DISK_THRESHOLD="${DISK_THRESHOLD:-80}"
MONITOR_URL="${MONITOR_URL:-http://127.0.0.1:8000/ready}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-1800}"
STATE_DIR="${MONITOR_STATE_DIR:-/var/lib/todo-api-monitor}"

# Validate numeric limits before using them in arithmetic comparisons.
# The 10# prefix treats numeric strings with leading zeros as decimal values.
[[ "$DISK_THRESHOLD" =~ ^[0-9]{1,3}$ ]] || fail "DISK_THRESHOLD must be an integer from 1 to 100."
DISK_THRESHOLD=$((10#$DISK_THRESHOLD))
(( DISK_THRESHOLD >= 1 && DISK_THRESHOLD <= 100 )) || fail "DISK_THRESHOLD must be from 1 to 100."
[[ "$COOLDOWN_SECONDS" =~ ^[0-9]{1,6}$ ]] || fail "COOLDOWN_SECONDS must be an integer from 0 to 604800."
COOLDOWN_SECONDS=$((10#$COOLDOWN_SECONDS))
(( COOLDOWN_SECONDS <= 604800 )) || fail "COOLDOWN_SECONDS must not exceed 604800."
[[ "$MONITOR_URL" == http://* || "$MONITOR_URL" == https://* ]] || fail "MONITOR_URL must be an HTTP or HTTPS URL."

# Return success only when the webhook request succeeds, so state updates can follow it.
send_notification() {
    local message="$1"
    local payload

    if [[ -z "$DISCORD_WEBHOOK_URL" ]]; then
        printf 'Discord webhook is not configured; notification was not sent.\n' >&2
        return 1
    fi

    # Encode quotes and newlines correctly as JSON and disable automatic Discord mentions.
    payload="$(printf '%s' "$message" | python3 -c \
        'import json, sys; print(json.dumps({"content": sys.stdin.read(), "allowed_mentions": {"parse": []}}))')"
    # Bound connection and total request time so a notification cannot wait indefinitely.
    if ! curl --silent --fail --connect-timeout 5 --max-time 15 \
        --header 'Content-Type: application/json' \
        --data-binary "$payload" --url "$DISCORD_WEBHOOK_URL" \
        > /dev/null 2>&1; then
        printf 'Discord delivery failed; notification state was not updated.\n' >&2
        return 1
    fi
}

# Finish the manual test before loading or updating the production notification state.
if [[ "$test_mode" == true ]]; then
    send_notification "TEST: Todo API monitoring notification from $(hostname). This is a manual notification test."
    printf 'Test notification delivered. Production notification state was not changed.\n'
    exit 0
fi

# Keep state private and use a lock to prevent overlapping scheduled checks.
[[ "$STATE_DIR" == /* ]] || fail "MONITOR_STATE_DIR must be an absolute path."
STATE_DIR="$(realpath -m -- "$STATE_DIR")"
[[ "$STATE_DIR" =~ ^/[^/]+/[^/]+(/.*)?$ ]] || fail "Choose a dedicated monitoring state directory."
install -d -m 0700 -o root -g root -- "$STATE_DIR"
exec 9>"$STATE_DIR/monitor.lock"
if ! flock -n 9; then
    printf 'Another monitoring check is already running.\n'
    exit 0
fi

# problem_key identifies failure categories; problems contains their readable descriptions.
problem_key=""
problems=()
disk_usage=""
# df -P provides a predictable table. Field 5 contains the root filesystem usage percent.
if disk_usage="$(df -P / | awk 'NR == 2 {sub(/%$/, "", $5); print $5}')" \
    && [[ "$disk_usage" =~ ^[0-9]+$ ]]; then
    if (( disk_usage >= DISK_THRESHOLD )); then
        problem_key="disk"
        problems+=("Root disk usage is ${disk_usage}% (threshold ${DISK_THRESHOLD}%).")
    fi
else
    problem_key="disk"
    problems+=("Could not determine root disk usage.")
fi

# /ready checks PostgreSQL access as well as the API. Require HTTP 200 for success.
# curl reports the HTTP code through stdout while discarding the response body.
http_status=""
if ! http_status="$(curl --silent --connect-timeout 3 --max-time 10 \
    --output /dev/null --write-out '%{http_code}' --url "$MONITOR_URL" 2>/dev/null)" \
    || [[ "$http_status" != '200' ]]; then
    problem_key="${problem_key:+$problem_key,}api"
    problems+=("The API readiness check failed.")
fi

# State stores two lines: the last successfully notified category and its Unix timestamp.
state_file="$STATE_DIR/notification.state"
last_key="ok"
last_sent=0
# Validate saved state before using its values in comparisons and arithmetic.
if [[ -f "$state_file" ]]; then
    mapfile -t saved_state < "$state_file"
    if [[ "${saved_state[0]:-}" =~ ^(ok|disk|api|disk,api)$ \
        && "${saved_state[1]:-}" =~ ^[0-9]{1,12}$ ]]; then
        last_key="${saved_state[0]}"
        last_sent=$((10#${saved_state[1]}))
    fi
fi

# Compare the current health result with the last notification that succeeded.
now="$(date +%s)"
if [[ -z "$problem_key" ]]; then
    printf 'Monitoring OK at %s.\n' "$(date -u +%FT%TZ)"
    # Send recovery when the previous delivered state recorded a problem.
    [[ "$last_key" != 'ok' ]] || exit 0
    current_key="ok"
    message="RECOVERY: Todo API on $(hostname). API readiness and root disk usage are normal."
else
    printf 'Monitoring alert at %s: %s\n' "$(date -u +%FT%TZ)" "${problems[*]}"
    # Repeated failures of the same category wait for the configured cooldown.
    # A change in failure categories can produce an immediate new alert.
    if [[ "$problem_key" == "$last_key" ]] \
        && (( now >= last_sent && now - last_sent < COOLDOWN_SECONDS )); then
        printf 'The same alert was already delivered; waiting for the notification cooldown.\n'
        exit 0
    fi
    current_key="$problem_key"
    printf -v message 'ALERT: Todo API on %s.\n' "$(hostname)"
    for problem in "${problems[@]}"; do
        message+="$problem"$'\n'
    done
fi

# A failed request exits before the state is written, allowing the next cron run to retry.
send_notification "$message"
# Update state only after successful delivery. Failed alerts and recoveries retry.
# Rename a complete temporary file into place so readers see a complete state record.
state_temp="$(mktemp "$STATE_DIR/.notification-XXXXXX")"
trap 'rm -f -- "$state_temp"' EXIT
printf '%s\n%s\n' "$current_key" "$now" > "$state_temp"
mv -- "$state_temp" "$state_file"
trap - EXIT
printf 'Notification delivered and state saved.\n'
