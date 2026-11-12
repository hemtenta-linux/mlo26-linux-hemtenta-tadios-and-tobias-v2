#!/usr/bin/env bash

set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this script with sudo bash scripts/setup-database.sh"
    exit 1
fi


umask 077


cd /home/api/todo-api


mkdir -p /etc/todo-api
chmod 700 /etc/todo-api


if [[ ! -f /etc/todo-api/api.env ]]; then
    database_password=$(python3 -c 'import secrets; print(secrets.token_hex(24))')

    cat > /etc/todo-api/api.env <<EOF
DATABASE_NAME=todo_db
DATABASE_USER=todo_api
PASSWORD=$database_password
DATABASE_HOST=127.0.0.1
DATABASE_PORT=5432
EOF

    echo "Created database settings."
else
    echo "Using existing database settings."
fi

chmod 600 /etc/todo-api/api.env

docker compose \
    --env-file /etc/todo-api/api.env \
    up -d --wait --wait-timeout 120 db

echo "PostgreSQL is running in Docker."
