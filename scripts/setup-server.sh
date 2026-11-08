#!/usr/bin/env bash
# Prepare the operating system before cloning and deploying the todo application.
# Run this script on Ubuntu with sudo so it can install packages and create users.

# Fail on unhandled command errors, unset variables and failed pipeline stages.
# -E also lets ERR traps propagate into functions and subshell contexts.
set -Eeuo pipefail

# EUID is the effective user id. Root has id 0.
if (( EUID != 0 )); then
    printf 'Run this script as root, for example with sudo bash scripts/setup-server.sh.\n' >&2
    exit 1
fi

# Report the source line that failed to make an interrupted installation easier to diagnose.
trap 'printf "Server setup failed near line %s. Correct the error and run the script again.\n" "$LINENO" >&2' ERR

# Read the distribution's own metadata before using Ubuntu-specific package commands.
if [[ ! -r /etc/os-release ]]; then
    printf 'Cannot identify the operating system. This script requires Ubuntu 24.04 or later.\n' >&2
    exit 1
fi

# Sourcing this file provides ID and VERSION_ID for the version check below.
# shellcheck source=/dev/null
. /etc/os-release
if [[ ${ID:-} != ubuntu ]] || ! dpkg --compare-versions "${VERSION_ID:-0}" ge 24.04; then
    printf 'This script requires Ubuntu 24.04 or later.\n' >&2
    exit 1
fi

# Use unattended package defaults. update refreshes the available package list.
export DEBIAN_FRONTEND=noninteractive
apt-get update
# Install Python and its venv tools, PostgreSQL, Nginx, cron and administration tools.
apt-get install --yes --no-install-recommends \
    ca-certificates \
    cron \
    curl \
    git \
    nano \
    nginx \
    openssh-client \
    postgresql \
    postgresql-client \
    python3 \
    python3-pip \
    python3-venv \
    util-linux

# Create the application's Linux group and account when they are missing.
# Keeping these checks makes normal repeated installation possible.
if ! getent group api >/dev/null; then
    groupadd --system api
fi

if ! id api >/dev/null 2>&1; then
    useradd --system --gid api --create-home --home-dir /home/api --shell /bin/bash api
fi

# Validate an existing account before using it to run application code.
if [[ $(id -u api) == 0 || $(id -g api) == 0 || $(id -gn api) != api ]]; then
    printf 'The existing api account must be unprivileged and use the api primary group.\n' >&2
    exit 1
fi

# The service configuration expects this exact home directory and shell.
api_home=$(getent passwd api | cut -d: -f6)
api_shell=$(getent passwd api | cut -d: -f7)
if [[ $api_home != /home/api || $api_shell != /bin/bash ]]; then
    printf 'The existing api account must have home /home/api and shell /bin/bash.\n' >&2
    exit 1
fi

# Membership in these groups would give the application administrative capabilities.
case " $(id -nG api) " in
    *" sudo "*|*" wheel "*|*" docker "*)
        printf 'The api account must not belong to sudo, wheel or docker. Review its groups before continuing.\n' >&2
        exit 1
        ;;
esac

# Check the destination before setting its ownership and directory permissions.
if [[ -L /home/api ]]; then
    printf '/home/api must be a directory rather than a symbolic link.\n' >&2
    exit 1
fi

if [[ -e /home/api ]]; then
    if [[ ! -d /home/api || $(stat -c '%U:%G' /home/api) != api:api ]]; then
        printf 'The existing /home/api must be a directory owned by api:api. Existing files were preserved.\n' >&2
        exit 1
    fi
else
    install -d -m 0755 -o api -g api /home/api
fi
# The owner can write here, while other users can traverse and read the directory.
chmod 0755 /home/api

# Reserve a root-owned location for service settings. Credential files use mode 0600.
install -d -m 0750 -o root -g api /etc/todo-api

# Build the aliases in a temporary file, then publish the completed file by renaming it.
alias_file=$(mktemp /etc/profile.d/.todo-api.XXXXXX)
# Remove the temporary file if setup ends before it is installed.
trap 'rm -f -- "$alias_file"' EXIT
cat > "$alias_file" <<'ALIASES'
# Loaded by new login shells. Administrators can also source this file.
alias ll='ls -lah'
alias todo-status='systemctl status todo-api --no-pager'
alias todo-logs='sudo journalctl -u todo-api -n 50 --no-pager'
ALIASES
chmod 0644 "$alias_file"
chown root:root "$alias_file"
mv -f -- "$alias_file" /etc/profile.d/todo-api.sh
trap - EXIT

# enable configures startup at boot. --now also starts the services immediately.
systemctl enable --now postgresql nginx cron

printf '\nServer packages, the api account and aliases are ready.\n'
printf 'Clone the project as api into /home/api/todo-api, then configure the database and application.\n'
printf 'Aliases are in /etc/profile.d/todo-api.sh and are loaded by new login shells.\n'
