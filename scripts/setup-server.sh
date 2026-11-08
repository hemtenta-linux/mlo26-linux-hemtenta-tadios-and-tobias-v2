#!/usr/bin/env bash

# Stop if a command fails, a variable is unset, or a pipeline fails.
set -euo pipefail

# Installing packages and creating users requires root permissions.
if [[ "$EUID" -ne 0 ]]; then
    echo "Run this script with sudo bash setup-server.sh"
    exit 1
fi

# Refresh the package list and install the programs we need.
apt-get update

apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    #postgresql \
    #postgresql-client \
    docker.io \
    docker-compose-v2 \
    nginx \
    git \
    curl \
    cron \
    nano \
    ca-certificates \
    util-linux

# Create a dedicated application account if it does not exist.
if ! id api >/dev/null 2>&1; then
    useradd \
        --system \
        --user-group \
        --create-home \
        --home-dir /home/api \
        --shell /bin/bash \
        api
fi

# The owner can write; everyone else can read and enter the directory.
chmod 755 /home/api

# Add shortcuts that are loaded by new login shells.
cat > /etc/profile.d/todo-api.sh <<'EOF'
alias ll='ls -lah'
alias todo-status='systemctl status todo-api --no-pager'
alias todo-logs='sudo journalctl -u todo-api -n 50 --no-pager'
EOF

chmod 644 /etc/profile.d/todo-api.sh

# Start these services now and enable them at boot.
systemctl enable --now docker nginx cron

echo "Server setup finished."
echo "Next: clone the repository into /home/api/todo-api as the api user."