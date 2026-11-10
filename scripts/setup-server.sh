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
alias ll='ls -lah'
alias todo-status='systemctl status todo-api --no-pager'
alias todo-logs='sudo journalctl -u todo-api -n 50 --no-pager'
EOF

chmod 644 /etc/profile.d/todo-api.sh


systemctl enable --now docker nginx cron

echo "Server setup finished."
echo "Next: clone the repository into /home/api/todo-api as the api user."