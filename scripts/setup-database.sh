#!/usr/bin/env bash
# Create the application's PostgreSQL role, database and protected connection settings.
# The Linux account api runs Python. The database role todo_api authenticates to PostgreSQL.

# Disable tracing before reading credentials, including when invoked with bash -x.
set +x
# Stop on unhandled errors and unset variables, and propagate pipeline failures.
set -Eeuo pipefail
# New credential and temporary files receive owner-only default permissions.
umask 077

# Provisioning uses the local PostgreSQL administrator and writes protected system files.
if (( EUID != 0 )); then
    printf 'Run this script as root, for example with sudo bash scripts/setup-database.sh.\n' >&2
    exit 1
fi

# Clear shell password variables on failure and when the script finishes.
trap 'unset database_password TODO_API_DATABASE_PASSWORD; printf "Database setup failed near line %s. Correct the error and run the script again.\n" "$LINENO" >&2' ERR
trap 'unset database_password TODO_API_DATABASE_PASSWORD' EXIT

# Check the tools supplied by the operating-system installation stage.
for required_command in python3 psql runuser flock pg_isready; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        printf 'Missing %s. Run setup-server.sh first.\n' "$required_command" >&2
        exit 1
    fi
done

# The account and its group are created by setup-server.sh.
if ! getent group api >/dev/null; then
    printf 'The api group is missing. Run setup-server.sh first.\n' >&2
    exit 1
fi

# File descriptor 9 holds a lock for the lifetime of this script.
# A second provisioning process waits here until the first one finishes.
install -d -m 0700 -o root -g root /run/todo-api
exec 9>/run/todo-api/database-setup.lock
flock 9

# Validate the settings directory before creating or reading the credentials file.
if [[ -L /etc/todo-api ]]; then
    printf '/etc/todo-api must be a directory rather than a symbolic link.\n' >&2
    exit 1
fi
install -d -m 0750 -o root -g api /etc/todo-api

# Use a directory the postgres operating-system account can access, then check the cluster.
cd /
pg_isready --host=/var/run/postgresql --port=5432 --username=postgres --dbname=postgres

# The Python helper reads or creates a protected systemd EnvironmentFile.
# shlex parses quotes without evaluating shell code or expanding dollar signs.
# Only the password is returned through the private command-substitution pipe.
database_password=$(python3 - /etc/todo-api/api.env <<'PYTHON'
import getpass
import os
from pathlib import Path
import shlex
import stat
import sys
import tempfile

path = Path(sys.argv[1])
# These settings match the database and role provisioned by the SQL below.
expected = {
    "DATABASE_NAME": "todo_db",
    "DATABASE_USER": "todo_api",
    "DATABASE_HOST": "127.0.0.1",
    "DATABASE_PORT": "5432",
}

try:
    if path.is_symlink():
        raise ValueError("The application environment file must not be a symbolic link.")

    if path.exists():
        # Reuse credentials only from a root-owned regular file with mode 0600.
        metadata = path.stat()
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0:
            raise ValueError("The existing environment file must be a regular file owned by root.")
        if stat.S_IMODE(metadata.st_mode) != 0o600:
            raise ValueError("The existing environment file must have permissions 0600.")

        # Parse quoted assignments as data. shlex performs no shell expansion.
        values = {}
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            tokens = shlex.split(line, comments=True, posix=True)
            if not tokens:
                continue
            if len(tokens) != 1 or "=" not in tokens[0]:
                raise ValueError(f"Invalid environment-file syntax on line {line_number}.")
            name, value = tokens[0].split("=", 1)
            values[name] = value

        for name, value in expected.items():
            if values.get(name) != value:
                raise ValueError(f"The existing environment file must set {name}={value}.")
        password = values.get("PASSWORD", "")
    else:
        # stdin contains this Python program, so read the password from the SSH terminal.
        # getpass disables terminal echo while the password is entered.
        with open("/dev/tty", "r+", encoding="utf-8") as terminal:
            password = getpass.getpass("Choose the todo_api database password: ", stream=terminal)
            confirmation = getpass.getpass("Repeat the database password: ", stream=terminal)
        if password != confirmation:
            raise ValueError("The passwords did not match.")

    # Each setting occupies one line in the systemd environment file.
    if not password or any(character in password for character in "\x00\r\n"):
        raise ValueError("The password must be nonempty and contain no NUL or newline characters.")

    if not path.exists():
        # Write the complete file first, then atomically move it to its final name.
        values = {**expected, "PASSWORD": password}
        descriptor, temporary_path = tempfile.mkstemp(prefix=".api.env.", dir=path.parent)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as output:
                for name, value in values.items():
                    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
                    output.write(f'{name}="{escaped}"\n')
                output.flush()
                os.fsync(output.fileno())
            os.chmod(temporary_path, 0o600)
            os.replace(temporary_path, path)
        finally:
            if os.path.exists(temporary_path):
                os.unlink(temporary_path)

    # Bash captures this value in database_password through command substitution.
    sys.stdout.write(password)
except (OSError, ValueError, EOFError, KeyboardInterrupt) as error:
    print(f"Cannot prepare application credentials: {error}", file=sys.stderr)
    sys.exit(1)
PYTHON
)

# Let the postgres child process read the password through its environment.
export TODO_API_DATABASE_PASSWORD="$database_password"

# -X ignores psql startup files. The secret travels in the environment, never
# as a command argument. psql quotes it as an SQL literal through :'password'.
# Create or update the login role inside one transaction, with restricted role privileges.
runuser -u postgres -- psql -X --quiet --no-password \
    --host=/var/run/postgresql --port=5432 --username=postgres --dbname=postgres \
    --set=ON_ERROR_STOP=1 --set=ECHO=none --set=VERBOSITY=terse <<'SQL'
\getenv password TODO_API_DATABASE_PASSWORD
SET log_statement = 'none';
SET log_min_duration_statement = -1;
SET log_min_error_statement = 'panic';
BEGIN;
SELECT 'CREATE ROLE todo_api LOGIN'
WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'todo_api')
\gexec
SET LOCAL password_encryption = 'scram-sha-256';
ALTER ROLE todo_api WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD :'password';
COMMIT;
SQL

# The password is supplied again only for the final application-login check.
unset TODO_API_DATABASE_PASSWORD

# CREATE DATABASE must run outside a transaction. An interrupted run can be
# retried because the role and environment file already contain the same secret.
runuser -u postgres -- psql -X --quiet --no-password \
    --host=/var/run/postgresql --port=5432 --username=postgres --dbname=postgres \
    --set=ON_ERROR_STOP=1 <<'SQL'
SELECT 'CREATE DATABASE todo_db OWNER todo_api TEMPLATE template0'
WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_database WHERE datname = 'todo_db')
\gexec
BEGIN;
ALTER DATABASE todo_db OWNER TO todo_api;
REVOKE ALL ON DATABASE todo_db FROM PUBLIC;
GRANT CONNECT, TEMPORARY ON DATABASE todo_db TO todo_api;
COMMIT;
SQL

# Grant schema, table and sequence access needed by the app, including existing tables.
runuser -u postgres -- psql -X --quiet --no-password \
    --host=/var/run/postgresql --port=5432 --username=postgres --dbname=todo_db \
    --set=ON_ERROR_STOP=1 <<'SQL'
BEGIN;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA public TO todo_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO todo_api;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO todo_api;
COMMIT;
SQL

# Verify a password-authenticated TCP connection using the same role as the application.
PGPASSWORD="$database_password" PGCONNECT_TIMEOUT=5 psql -X --quiet --no-password \
    --host=127.0.0.1 --port=5432 --username=todo_api --dbname=todo_db \
    --set=ON_ERROR_STOP=1 --command='SELECT 1;' >/dev/null
unset database_password

printf 'Database todo_db and application role todo_api are ready.\n'
printf 'Credentials are stored in /etc/todo-api/api.env with root ownership and permissions 0600.\n'
printf 'Rerunning this script reuses the saved password and preserves existing database rows.\n'
