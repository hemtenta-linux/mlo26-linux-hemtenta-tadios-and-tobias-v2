#!/usr/bin/env bash

set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this script with sudo bash scripts/install-config.sh"
    exit 1
fi

cd /home/api/todo-api

for file in \
    /etc/todo-api/api.env \
    Dockerfile \
    compose.yaml \
    deploy/nginx-todo-api.conf
do
    if [[ ! -f "$file" ]]; then
        echo "Missing required file: $file"
        exit 1
    fi
done

if [[ ! -f /etc/nginx/sites-available/todo-api ]]; then
    install -o root -g root -m 644 \
        deploy/nginx-todo-api.conf /etc/nginx/sites-available/todo-api
fi

ln -sfn /etc/nginx/sites-available/todo-api \
    /etc/nginx/sites-enabled/todo-api

rm -f /etc/nginx/sites-enabled/default

nginx -t

systemctl enable --now docker

docker compose --env-file /etc/todo-api/api.env config --quiet
docker compose --env-file /etc/todo-api/api.env build api

# Free port 8000 if the systemd API service exists.
if systemctl cat todo-api.service > /dev/null 2>&1; then
    systemctl disable --now todo-api.service
fi

docker compose --env-file /etc/todo-api/api.env \
    up -d --wait --wait-timeout 120

systemctl enable --now nginx
systemctl reload nginx


ready_url="${READY_URL:-http://127.0.0.1/ready}"

curl --fail --show-error --silent \
    --retry 10 --retry-all-errors --retry-delay 1 \
    --retry-max-time 30 --max-time 3 \
    "$ready_url"

echo
echo "API and nginx deployment finished."
