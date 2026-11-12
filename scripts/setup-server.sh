#!/usr/bin/env bash

set -euo pipefail


if [[ "$EUID" -ne 0 ]]; then
    echo "Run this script with sudo bash setup-server.sh"
    exit 1
fi


apt-get update

apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    docker.io \
    docker-compose-v2 \
    nginx \
    git \
    curl \
    cron \
    nano \
    ca-certificates \
    util-linux


if ! id api >/dev/null 2>&1; then
    useradd \
        --system \
        --user-group \
        --create-home \
        --home-dir /home/api \
        --shell /bin/bash \
        api
fi


chmod 755 /home/api

cat > /etc/profile.d/todo-api.sh <<'EOF'
# General shortcuts
alias ll='ls -lah'
alias todo-cd='cd /home/api/todo-api'

# Docker shortcuts
alias docker-status='sudo docker ps'
alias docker-all='sudo docker ps -a'
alias docker-images='sudo docker images'

# Compose commands for this project
alias todo-compose='sudo docker compose -f /home/api/todo-api/compose.yaml --env-file /etc/todo-api/api.env'

alias todo-status='todo-compose ps'
alias todo-logs='todo-compose logs --tail 50 api'
alias todo-follow='todo-compose logs --tail 50 --follow api'
alias todo-start='todo-compose up -d --wait'
alias todo-stop='todo-compose stop'
alias todo-restart='todo-compose restart api'
EOF

chmod 644 /etc/profile.d/todo-api.sh


systemctl enable --now docker nginx cron

echo "Server setup finished."
echo "Next: clone the repository into /home/api/todo-api as the api user."
