#!/usr/bin/env bash
# Provision the production schema/workspace and a saved SQLcl connection.
# Supply DEMO_PRO_PASSWORD_FILE only when reusing an existing schema without
# an already validated saved connection. No password is accepted in argv.
set -euo pipefail
set +x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../aux/common.sh"
if [[ -f "$DEMO_HOME/.state/project.env" ]]; then
  load_project
fi
if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
  echo "Usage: $0 [--no-save-connection] (optional environment: DEMO_PRO_PASSWORD_FILE)"
  echo "One-time production schema/workspace setup; no project or application import is required."
  exit 0
fi
skip_connection=0
if [[ "${1:-}" == --no-save-connection ]]; then skip_connection=1; shift; fi
[[ $# -eq 0 ]] || die "Usage: $0 [--no-save-connection] (optional environment: DEMO_PRO_PASSWORD_FILE)"
export DEMO_SKIP_CONNECTION="$skip_connection"
require_tools python3
export DEMO_HOME SQLCL_BIN SCHEMA_NAME_PRO APEX_WORKSPACE_PRO DB_CONNECT_ADMIN DB_CONNECT_PRO
export SQLCL_TIMEOUT="${SQLCL_TIMEOUT:-180}"

python3 - <<'PY'
import json
import os
import re
import secrets
import signal
import stat
import string
import subprocess
import tempfile
from pathlib import Path

home = Path(os.environ['DEMO_HOME'])
sqlcl = os.environ['SQLCL_BIN']
schema = os.environ['SCHEMA_NAME_PRO']
workspace = os.environ['APEX_WORKSPACE_PRO']
admin = os.environ['DB_CONNECT_ADMIN']
target = os.environ['DB_CONNECT_PRO']
skip_connection = os.environ.get('DEMO_SKIP_CONNECTION') == '1'
try:
    timeout = int(os.environ.get('SQLCL_TIMEOUT', '180'))
    if timeout < 1:
        raise ValueError
except ValueError:
    raise SystemExit('SQLCL_TIMEOUT must be a positive number of seconds.')
for label, value in [('schema', schema), ('workspace', workspace)]:
    if not re.fullmatch(r'[A-Z][A-Z0-9_]{0,127}', value):
        raise SystemExit(f'Invalid {label}: use an uppercase simple identifier.')
for value in (admin, target):
    if not re.fullmatch(r'[A-Za-z0-9_/-]+', value):
        raise SystemExit('Connection names must contain letters, digits, _, / or -.')
if admin == target:
    raise SystemExit('Administrative and production connection names must differ.')
if not re.search(r'Release 26\.3\.', subprocess.check_output([sqlcl, '-version'], text=True, timeout=timeout)):
    raise SystemExit('Only SQLcl 26.3 is supported.')
state = home / '.state'
state.mkdir(mode=0o700, exist_ok=True)
logs = home / 'logs'
logs.mkdir(exist_ok=True)
password = ''
ansi = re.compile(r'\x1b\[[0-?]*[ -/]*[@-~]')
log_path = logs / 'setup-production.log'
log_flags = os.O_WRONLY | os.O_CREAT | os.O_APPEND | getattr(os, 'O_NOFOLLOW', 0)
log_fd = os.open(log_path, log_flags, 0o600)
os.fchmod(log_fd, 0o600)
os.close(log_fd)

def run(commands, connection=None):
    """Keep secret-bearing SQL out of argv, public temp paths, and logs."""
    prefix = ('set echo off\nset verify off\nset define off\n'
              'set serveroutput on\nset feedback off\nset heading off\n'
              'set pagesize 0\nwhenever sqlerror exit failure rollback\n'
              'whenever oserror exit failure rollback\n')
    sentinel = 'APEXCICD_SETUP_COMPLETE_' + secrets.token_hex(12)
    fd, raw_path = tempfile.mkstemp(prefix='production-', suffix='.sql', dir=state)
    path = Path(raw_path)
    timed_out = False
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(prefix + commands + '\nprompt ' + sentinel + '\nexit success\n')
        args = [sqlcl, '-S']
        args += ['-name', connection] if connection else ['/nolog']
        # The SQLcl command history can contain only this private script path.
        process = subprocess.Popen(args, stdin=subprocess.PIPE, text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            raw_output, _ = process.communicate(f'@"{path}"\n', timeout=timeout)
            returncode = process.returncode
        except subprocess.TimeoutExpired:
            timed_out = True
            # The SQLcl shell launcher may leave its Java child running unless
            # the complete isolated process group is terminated.
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                raw_output, _ = process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                raw_output, _ = process.communicate()
            returncode = 124
    finally:
        path.unlink(missing_ok=True)
    output = ansi.sub('', raw_output)
    if password:
        output = output.replace(password, '[REDACTED]')
    if timed_out:
        output += f'\nSQLcl timed out after {timeout} seconds.\n'
    with os.fdopen(os.open(log_path, log_flags, 0o600), 'a') as stream:
        stream.write(output)
    errors = re.search(
        r'ORA-\d+|PLS-\d+|TNS-\d+|SP2-\d+|\bConnection failed\b|'
        r'^\s*(?:Error\b|Unknown command\b|Invalid command\b)',
        output, re.I | re.M)
    finished = sentinel in [line.strip() for line in output.splitlines()]
    if returncode or errors or not finished:
        raise SystemExit('Production setup failed. See logs/setup-production.log (password redacted).\n' + output)
    return output

def quote(value):
    return "'" + value.replace("'", "''") + "'"

identity_sql = "select 'IDENTITY|' || user || '|' || sys_context('USERENV','DB_NAME') || '|' || sys_context('USERENV','SERVICE_NAME') from dual;"
output = run(identity_sql + "\nselect 'USER_EXISTS|' || count(*) from dba_users where username=" + quote(schema) + ';', admin)
identity = next((line.strip().split('|') for line in output.splitlines() if line.strip().startswith('IDENTITY|')), None)
if not identity or len(identity) != 4:
    raise SystemExit('Could not verify administrative database identity.')
if identity[1] != 'ADMIN':
    raise SystemExit('Production provisioning requires a saved connection authenticated as ADMIN. No DDL was executed.')
exists = 'USER_EXISTS|1' in output
names_output = run('connmgr list -flat')
names = {line.strip() for line in names_output.splitlines() if line.strip()}
saved_exists = target in names
if saved_exists:
    check = run(identity_sql, target)
    expected = 'IDENTITY|' + schema + '|' + '|'.join(identity[2:])
    if expected not in [line.strip() for line in check.splitlines()]:
        raise SystemExit('Existing saved target connection has a different schema or database/service. It was not modified.')
elif exists:
    print('The schema already exists; its password will not be changed.')

password_path = state / f'production-password-{schema}.txt'
supplied = os.environ.get('DEMO_PRO_PASSWORD_FILE')
if not saved_exists:
    source = Path(supplied).expanduser() if supplied else password_path
    if source.exists():
        if source.is_symlink() or not source.is_file():
            raise SystemExit('Password source must be a regular, non-symlink file.')
        if stat.S_IMODE(source.stat().st_mode) & 0o077:
            raise SystemExit('Password file must be private (chmod 600).')
        password = source.read_text().rstrip('\r\n')
    elif exists:
        raise SystemExit('Existing schema requires DEMO_PRO_PASSWORD_FILE (mode 600) or the prior local password file to create its saved connection.')
    elif supplied:
        raise SystemExit('DEMO_PRO_PASSWORD_FILE does not exist.')
    else:
        # Match Autonomous Database default complexity without embedding the username.
        alphabet = string.ascii_letters + string.digits + '_#'
        while True:
            password = ''.join(secrets.choice(alphabet) for _ in range(24))
            if (any(c.isupper() for c in password) and any(c.islower() for c in password)
                and any(c.isdigit() for c in password)
                and schema.casefold() not in password.casefold()):
                break
        fd = os.open(password_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as stream:
            stream.write(password + '\n')
        print(f'Generated schema password stored privately at {password_path}.')
    # Restrict the alphabet to avoid SQLcl and SQL delimiter interpretation.
    # Existing credentials outside this set can be saved manually in SQLcl first.
    if not re.fullmatch(r'[A-Za-z0-9_#@$!.-]{12,128}', password):
        raise SystemExit('Password must be 12-128 characters using letters, digits, _ # @ $ ! . or -. Alternatively save a valid target connection manually first.')

bindings = ('variable demo_schema varchar2(128)\n'
            'variable demo_workspace varchar2(128)\n'
            'variable demo_password varchar2(128)\n'
            'begin\n :demo_schema := ' + quote(schema) + ';\n'
            ' :demo_workspace := ' + quote(workspace) + ';\n'
            ' :demo_password := ' + quote(password) + ';\nend;\n/\n')
setup_sql = (home / 'scripts/setup/setup_production.sql').read_text()
run(bindings + setup_sql, admin)
if not saved_exists and not skip_connection:
    run(f'connmgr clone -original {admin} -username {schema} -nopwd {target}')
    # Only replace the new passwordless clone created above; pre-existing
    # saved connections take the validation-only branch and are never replaced.
    run(f'connect -name {target} -password "{password}"\n'
        + identity_sql + '\n'
        + f'connect -save {target} -savepwd -replace')
    print(f'Created saved SQLcl connection {target}.')
if saved_exists or not skip_connection:
    final_check = run(identity_sql, target)
    expected = 'IDENTITY|' + schema + '|' + '|'.join(identity[2:])
    if expected not in [line.strip() for line in final_check.splitlines()]:
        raise SystemExit('Final production identity check failed.')
else:
    # Verify the objects using ADMIN; the presenter saves and tests their own connection.
    verified = run("select 'SCHEMA_READY|' || count(*) from dba_users where username=" + quote(schema)
                   + " and account_status='OPEN';\nselect 'WORKSPACE_READY|' || count(*) from apex_workspace_schemas where workspace_name="
                   + quote(workspace) + " and schema=" + quote(schema) + ';', admin)
    if 'SCHEMA_READY|1' not in verified or 'WORKSPACE_READY|1' not in verified:
        raise SystemExit('Schema/workspace verification failed.')
    print('No SQLcl connection was created or changed. Create it manually using the private password file.')
metadata = {'schema': schema, 'workspace': workspace, 'connection': target,
            'database': identity[2], 'service': identity[3],
            'connection_pending': bool(skip_connection and not saved_exists)}
record = state / 'production-setup.json'
old_metadata = json.loads(record.read_text()) if record.exists() else {}
metadata['deployment_state'] = ('deployed' if (state / 'deployment.json').exists() else
                                'not_started' if not exists else old_metadata.get('deployment_state', 'unknown'))
record.write_text(json.dumps(metadata, indent=2) + '\n')
record.chmod(0o600)
print(f'Production schema/workspace ready: {schema}/{workspace}.')
print('APEX workspace users are managed separately; no APEX account password was created or changed.')
PY
