#!/usr/bin/env bash
# Export the todo database and archive Nginx logs for the scheduled backup job.
# Run as root so the script can manage private backups and switch to postgres.

# Stop on unhandled errors, unset variables and failed pipeline stages.
set -Eeuo pipefail
# New backup files and directories receive owner-only default permissions.
umask 077

# Environment variables can override these defaults for a deliberate backup setup.
BACKUP_DIR="${BACKUP_DIR:-/var/backups/todo-api}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
DATABASE_NAME="${DATABASE_NAME:-todo_db}"
NGINX_LOG_DIR="${NGINX_LOG_DIR:-/var/log/nginx}"

# Report validation errors to stderr and stop the backup.
fail() {
    printf 'Backup failed: %s\n' "$1" >&2
    exit 1
}

# Validate the destination and retention period before creating or removing files.
[[ "$EUID" -eq 0 ]] || fail "Run this script as root."
[[ "$BACKUP_DIR" == /* ]] || fail "BACKUP_DIR must be an absolute path."
BACKUP_DIR="$(realpath -m -- "$BACKUP_DIR")"
[[ "$BACKUP_DIR" =~ ^/[^/]+/[^/]+(/.*)?$ ]] || fail "Choose a dedicated backup directory."
[[ "$RETENTION_DAYS" =~ ^[0-9]{1,3}$ ]] || fail "RETENTION_DAYS must be an integer from 1 to 365."
# Interpret the supplied digits as decimal, including values with leading zeros.
RETENTION_DAYS=$((10#$RETENTION_DAYS))
(( RETENTION_DAYS >= 1 && RETENTION_DAYS <= 365 )) || fail "RETENTION_DAYS must be from 1 to 365."
[[ -n "$DATABASE_NAME" ]] || fail "DATABASE_NAME must not be empty."
[[ "$NGINX_LOG_DIR" == /* ]] || fail "NGINX_LOG_DIR must be an absolute path."

# A dedicated root-owned directory protects the database data inside each dump.
install -d -m 0700 -o root -g root -- "$BACKUP_DIR"
# File descriptor 9 holds an exclusive lock until this script exits.
exec 9>"$BACKUP_DIR/.backup.lock"
if ! flock -n 9; then
    printf 'Another backup is already running.\n'
    exit 0
fi

# Track unfinished files so cleanup can remove partial outputs after a failed run.
database_temp=""
logs_temp=""
cleanup() {
    if [[ -n "$database_temp" ]]; then
        rm -f -- "$database_temp"
    fi
    if [[ -n "$logs_temp" ]]; then
        rm -f -- "$logs_temp"
    fi
}
# Run cleanup on successful exit and ordinary error exits.
trap cleanup EXIT

# UTC time and the process id make completed backup names easy to identify.
timestamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
database_temp="$(mktemp "$BACKUP_DIR/.todo-db-XXXXXX.partial")"

# Root opens the output file. PostgreSQL only needs peer-authenticated read access.
# The custom pg_dump format is an archive that can be restored with pg_restore.
# shellcheck disable=SC2024
sudo -u postgres -- pg_dump --format=custom --dbname="$DATABASE_NAME" > "$database_temp"
# Publish the completed dump by renaming it after pg_dump succeeds and writes data.
[[ -s "$database_temp" ]] || fail "The database dump is empty."
mv -- "$database_temp" "$BACKUP_DIR/todo-db-$timestamp.dump"
database_temp=""
printf 'Created database backup todo-db-%s.dump\n' "$timestamp"

# Save a separate gzip-compressed tar archive containing the available Nginx logs.
if [[ -d "$NGINX_LOG_DIR" ]]; then
    logs_temp="$(mktemp "$BACKUP_DIR/.todo-nginx-XXXXXX.partial")"
    if tar -czf "$logs_temp" -C "$NGINX_LOG_DIR" .; then
        :
    else
        tar_status=$?
        # Active log files may change while tar reads them. Fatal errors still fail.
        if [[ "$tar_status" -ne 1 ]]; then
            fail "Could not archive Nginx logs."
        fi
        printf 'Nginx logs changed during archiving; the archive contains the readable snapshot.\n'
    fi
    mv -- "$logs_temp" "$BACKUP_DIR/todo-nginx-$timestamp.tar.gz"
    logs_temp=""
    printf 'Created log backup todo-nginx-%s.tar.gz\n' "$timestamp"
else
    printf 'Nginx log directory is absent; database backup completed and log backup skipped.\n'
fi

# Only this script's completed archives in the checked directory are eligible.
# -maxdepth 1 limits cleanup to this directory, and -mmin expresses retention in minutes.
find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type f \
    \( -name 'todo-db-*.dump' -o -name 'todo-nginx-*.tar.gz' \) \
    -mmin "+$((RETENTION_DAYS * 1440))" -delete
printf 'Backup completed at %s; retention is %s days.\n' "$(date -u +%FT%TZ)" "$RETENTION_DAYS"
