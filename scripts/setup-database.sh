#!/usr/bin/env bash

set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this script with sudo bash scripts/setup-database.sh"
    exit 1
fi

# Newly created files are readable and writable only by their owner.
umask 077

# The repository will be cloned here during server setup.
cd /home/api/todo-api

# Store server credentials outside the Git repository.
mkdir -p /etc/todo-api
chmod 700 /etc/todo-api

# Generate credentials only on the first run.
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

# Start PostgreSQL and wait for its health check to pass.
docker compose \
    --env-file /etc/todo-api/api.env \
    up -d --wait --wait-timeout 120 db

echo "PostgreSQL is running in Docker."