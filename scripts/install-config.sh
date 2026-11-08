#!/usr/bin/env bash
# Install the systemd service, Nginx site and recurring jobs after the app is cloned.
# The Linux venv and database credentials must already be prepared.

# Treat unhandled errors, unset variables and failed pipeline stages as failures.
set -Eeuo pipefail
# Default file permissions allow owner access and limited group access.
umask 027
# Use a predictable search path when this script is run from different environments.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Print errors on stderr and return a failing exit status to the caller.
fail() {
    printf 'Configuration installation failed: %s\n' "$1" >&2
    exit 1
}

# The service file uses a fixed project location, so validate it before installing files.
[[ "$EUID" -eq 0 ]] || fail "Run this script as root."
[[ "$#" -le 1 ]] || fail "Usage: install-config.sh [/home/api/todo-api]"
repo_dir="$(realpath -e -- "${1:-/home/api/todo-api}")"
[[ "$repo_dir" == /home/api/todo-api ]] || fail "The service expects /home/api/todo-api."

# Check commands, source files and earlier installation stages before changing the system.
for command_name in systemctl systemd-run systemd-analyze nginx curl install flock; do
    command -v "$command_name" > /dev/null || fail "Required command is missing: $command_name"
done
for source_file in deploy/todo-api.service deploy/nginx-todo-api.conf deploy/todo-api.cron \
    deploy/monitor.env.example scripts/backup.sh scripts/monitor.sh app.py db_setup.py; do
    [[ -f "$repo_dir/$source_file" ]] || fail "Required source file is missing: $source_file"
done
[[ -x "$repo_dir/venv/bin/python" ]] || fail "Create the api user's Linux venv and install requirements first."
[[ -f /etc/todo-api/api.env && ! -L /etc/todo-api/api.env ]] \
    || fail "Run setup-database.sh to create /etc/todo-api/api.env first."
getent passwd api > /dev/null || fail "Run setup-server.sh to create the api user first."
# Parse each scheduled script to catch Bash syntax errors before it is installed.
for script_file in "$repo_dir/scripts/backup.sh" "$repo_dir/scripts/monitor.sh"; do
    bash -n "$script_file"
done

# Keep one installer active at a time. The lock is released when this process exits.
exec 9>/run/lock/todo-api-install.lock
flock -n 9 || fail "Another configuration installation is running."

# Protect the settings directory and credentials with explicit ownership and permissions.
install -d -o root -g root -m 0750 /etc/todo-api
chown root:root /etc/todo-api/api.env
chmod 0600 /etc/todo-api/api.env
[[ ! -L /etc/todo-api/monitor.env ]] || fail "Monitoring settings must not be a symbolic link."
# Create initial monitoring settings on the first installation.
if [[ ! -e /etc/todo-api/monitor.env ]]; then
    install -o root -g root -m 0600 "$repo_dir/deploy/monitor.env.example" /etc/todo-api/monitor.env
fi
[[ -f /etc/todo-api/monitor.env && ! -L /etc/todo-api/monitor.env ]] \
    || fail "Monitoring settings must be a regular root-owned file."
chown root:root /etc/todo-api/monitor.env
chmod 0600 /etc/todo-api/monitor.env

# Cron runs these installed, root-owned copies of the backup and monitoring scripts.
# install copies a file and applies its owner, group and permission mode.
install -o root -g root -m 0750 "$repo_dir/scripts/backup.sh" /usr/local/sbin/todo-api-backup
install -o root -g root -m 0750 "$repo_dir/scripts/monitor.sh" /usr/local/sbin/todo-api-monitor
install -o root -g root -m 0644 "$repo_dir/deploy/todo-api.service" /etc/systemd/system/todo-api.service
# Prepare private backup/state directories and log files for the recurring root jobs.
install -d -o root -g root -m 0700 /var/backups/todo-api /var/lib/todo-api-monitor
touch /var/log/todo-api-backup.log /var/log/todo-api-monitor.log
chown root:root /var/log/todo-api-backup.log /var/log/todo-api-monitor.log
chmod 0600 /var/log/todo-api-backup.log /var/log/todo-api-monitor.log

# sites-available stores the configuration. A link in sites-enabled activates the site.
site_file=/etc/nginx/sites-available/todo-api
site_link=/etc/nginx/sites-enabled/todo-api
default_link=/etc/nginx/sites-enabled/default
[[ ! -L "$site_file" ]] || fail "The Nginx site must not be a symbolic link."
# Use the template when the administrator has not already created this site's file.
if [[ ! -e "$site_file" ]]; then
    install -o root -g root -m 0644 "$repo_dir/deploy/nginx-todo-api.conf" "$site_file"
fi
[[ -f "$site_file" && ! -L "$site_file" ]] || fail "The Nginx site must be a regular file."
chown root:root "$site_file"
chmod 0644 "$site_file"

# Record link changes so a failed installation can restore the previous site links.
site_link_created=false
default_link_target=""
configuration_complete=false
nginx_reloaded=false
rollback_links() {
    # Capture the original exit status before cleanup commands run.
    local exit_status=$?
    if [[ "$configuration_complete" == false && "$exit_status" -ne 0 ]]; then
        if [[ "$site_link_created" == true && -L "$site_link" ]]; then
            unlink "$site_link"
        fi
        if [[ -n "$default_link_target" && ! -e "$default_link" && ! -L "$default_link" ]]; then
            ln -s -- "$default_link_target" "$default_link"
        fi
        if [[ "$nginx_reloaded" == true ]]; then
            if nginx -t; then
                systemctl reload-or-restart nginx.service \
                    || printf 'Reload the restored Nginx configuration manually.\n' >&2
            fi
        fi
        printf 'Installation stopped. The previous Nginx site links were restored.\n' >&2
    fi
}
# EXIT also runs after a failed command. Successful installation removes this trap below.
trap rollback_links EXIT

# Activate our site, or validate an existing link to the same configuration.
if [[ -L "$site_link" ]]; then
    [[ "$(realpath -e -- "$site_link")" == "$site_file" ]] \
        || fail "An existing todo-api site link points to a different configuration."
elif [[ -e "$site_link" ]]; then
    fail "An existing todo-api site is not a symbolic link."
else
    ln -s -- "$site_file" "$site_link"
    site_link_created=true
fi

# Disable Ubuntu's standard site so our site can become the default server on port 80.
if [[ -L "$default_link" ]]; then
    [[ "$(realpath -m -- "$default_link")" == /etc/nginx/sites-available/default ]] \
        || fail "The default Nginx site has a custom target. Review it manually."
    default_link_target="$(readlink -- "$default_link")"
    unlink "$default_link"
elif [[ -e "$default_link" ]]; then
    fail "The default Nginx site is a regular file. Review it manually."
fi

# Validate both configurations before starting the application.
nginx -t
systemd-analyze verify /etc/systemd/system/todo-api.service
# Ask systemd to reread the unit file that was installed above.
systemctl daemon-reload
# Run table initialization once as api. Systemd reads the root-owned environment file
# and passes its settings to this temporary service's Python process.
systemd-run --unit="todo-api-init-$$" --wait --collect --pipe \
    --property=User=api --property=Group=api \
    --property=WorkingDirectory=/home/api/todo-api \
    --property=EnvironmentFile=/etc/todo-api/api.env \
    --property=Environment=PYTHONDONTWRITEBYTECODE=1 \
    -- /home/api/todo-api/venv/bin/python db_setup.py

# Enable startup at boot and restart the API with its current code and settings.
systemctl enable todo-api.service nginx.service cron.service
systemctl restart todo-api.service
# Give Uvicorn time to start, checking database readiness on each attempt.
api_ready=false
for _attempt in {1..15}; do
    if curl --silent --fail --max-time 2 http://127.0.0.1:8000/ready > /dev/null; then
        api_ready=true
        break
    fi
    sleep 1
done
[[ "$api_ready" == true ]] || fail "The API did not become ready. Check journalctl -u todo-api."

# Load the checked proxy configuration and verify the HTTP path through Nginx.
systemctl reload-or-restart nginx.service
nginx_reloaded=true
curl --silent --show-error --fail --max-time 5 http://127.0.0.1/ready > /dev/null
# Install the schedule after both the API and its proxy respond successfully.
install -o root -g root -m 0644 "$repo_dir/deploy/todo-api.cron" /etc/cron.d/todo-api
systemctl start cron.service
# Mark success so normal script exit completes the installation.
configuration_complete=true
trap - EXIT
printf 'Todo API is ready through Nginx. Backup and monitoring schedules are installed.\n'
printf 'Set the Discord webhook in /etc/todo-api/monitor.env and run todo-api-monitor --test.\n'
