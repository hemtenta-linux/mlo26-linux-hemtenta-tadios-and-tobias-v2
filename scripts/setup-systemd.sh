#!/usr/bin/env bash


set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this script with sudo bash scripts/setup-systemd.sh"
    exit 1
fi

cd /home/api/todo-api

for file in \
    /etc/todo-api/api.env \
    compose.yaml \
    requirements.txt \
    db_setup.py \
    app.py \
    deploy/todo-api.service \
    deploy/nginx-todo-api.conf
do
    if [[ ! -f "$file" ]]; then
        echo "Missing required file: $file"
        exit 1
    fi
done


systemctl enable --now docker
docker compose --env-file /etc/todo-api/api.env \
    up -d --wait --wait-timeout 120 db

sudo -u api -H python3 -m venv venv
sudo -u api -H venv/bin/python -m pip install -r requirements.txt

install -o root -g root -m 644 \
    deploy/todo-api.service /etc/systemd/system/todo-api.service
systemd-analyze verify /etc/systemd/system/todo-api.service


if [[ ! -f /etc/nginx/sites-available/todo-api ]]; then
    install -o root -g root -m 644 \
        deploy/nginx-todo-api.conf /etc/nginx/sites-available/todo-api
fi

ln -sfn /etc/nginx/sites-available/todo-api \
    /etc/nginx/sites-enabled/todo-api
rm -f /etc/nginx/sites-enabled/default
nginx -t


docker compose --env-file /etc/todo-api/api.env stop api

systemctl daemon-reload
systemctl enable todo-api.service
systemctl restart todo-api.service

systemctl enable --now nginx
systemctl reload nginx

ready_url="${READY_URL:-http://127.0.0.1/ready}"
curl --fail --show-error --silent \
    --retry 10 --retry-all-errors --retry-delay 1 \
    --retry-max-time 30 --max-time 3 \
    "$ready_url"

echo
echo "Systemd API demonstration ready."
