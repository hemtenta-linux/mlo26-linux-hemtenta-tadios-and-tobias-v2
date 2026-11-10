#!/usr/bin/env bash

set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this script with sudo bash scripts/backup.sh"
    exit 1
fi

# Only root can read newly created backup files.
umask 077

# Use a predictable command search path when running through cron.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

backup_dir=/var/backups/todo-api

mkdir -p "$backup_dir"
chmod 700 "$backup_dir"

# Prevent two backups from running at the same time.
exec 9>"$backup_dir/.backup.lock"
if ! flock -n 9; then
    echo "Another backup is already running."
    exit 0
fi

cd /home/api/todo-api

# Include the time and process ID to give each backup a unique name.
timestamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"

database_file="$backup_dir/todo-db-$timestamp.dump"
logs_file="$backup_dir/todo-api-$timestamp.log.gz"

# Remove unfinished files if the script exits before completing them.
trap 'rm -f -- "$database_file.partial" "$logs_file.partial"' EXIT

# Run pg_dump inside the database container.
# The host shell writes its output to the backup directory on EC2.
docker compose \
    --env-file /etc/todo-api/api.env \
    exec -T db \
    pg_dump -U todo_api -d todo_db --format=custom \
    > "$database_file.partial"

# Rename the file only after the database export succeeds.
mv "$database_file.partial" "$database_file"

# Export and compress the last 24 hours of the API's systemd logs.
docker compose --env-file /etc/todo-api/api.env \
    logs --no-color --since 24h api \
    | gzip > "$logs_file.partial"

# Delete only our completed backup files older than seven days.
find "$backup_dir" -maxdepth 1 -type f \
    \( -name 'todo-db-*.dump' -o -name 'todo-api-*.log.gz' \) \
    -mmin +10080 -delete

echo "Backup completed: $timestamp"