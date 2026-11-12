#!/usr/bin/env bash

set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this script with sudo bash scripts/backup.sh"
    exit 1
fi

umask 077
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

backup_dir=/var/backups/todo-api
mkdir -p "$backup_dir"
chmod 700 "$backup_dir"


exec 9>"$backup_dir/.backup.lock"
if ! flock -n 9; then
    echo "Another backup is already running."
    exit 0
fi

cd /home/api/todo-api
timestamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
database_file="$backup_dir/todo-db-$timestamp.dump"
logs_file="$backup_dir/todo-api-$timestamp.log.gz"

trap 'rm -f -- "$database_file.partial" "$logs_file.partial"' EXIT

docker compose --env-file /etc/todo-api/api.env \
    exec -T --interactive=false db \
    pg_dump -U todo_api -d todo_db --format=custom \
    > "$database_file.partial"

mv "$database_file.partial" "$database_file"


docker compose --env-file /etc/todo-api/api.env \
    logs --no-color --since 24h api \
    | gzip > "$logs_file.partial"

mv "$logs_file.partial" "$logs_file"


find "$backup_dir" -maxdepth 1 -type f \
    \( -name 'todo-db-*.dump' -o -name 'todo-api-*.log.gz' \) \
    -mmin +10080 -delete

echo "Backup completed: $timestamp"
