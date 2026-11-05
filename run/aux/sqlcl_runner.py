#!/usr/bin/env python3
"""Run SQLcl with bounded execution and detect errors hidden by a zero exit code."""
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

binary, connection, log_name, timeout = sys.argv[1:]
body = sys.stdin.read()
script = "set echo off\nset verify off\nwhenever sqlerror exit failure rollback\nwhenever oserror exit failure rollback\n" + body + "\nprompt APEXCICD_STAGE_COMPLETE\nexit success\n"
try:
    process = subprocess.Popen([binary, '-S', '-name', connection], text=True,
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, start_new_session=True)
    if Path(log_name).name.startswith('deploy-'):
        started = time.monotonic()
        remaining_input = script
        while True:
            remaining = int(timeout) - (time.monotonic() - started)
            if remaining <= 0:
                raise subprocess.TimeoutExpired(process.args, int(timeout))
            try:
                output, _ = process.communicate(remaining_input, timeout=min(15, remaining))
                break
            except subprocess.TimeoutExpired:
                remaining_input = None
                if time.monotonic() - started >= int(timeout):
                    raise
                print(f'SQLcl deployment is still running ({int(time.monotonic()-started)}s elapsed; limit {timeout}s).', flush=True)
    else:
        output, _ = process.communicate(script, timeout=int(timeout))
    code = process.returncode
except subprocess.TimeoutExpired as exc:
    os.killpg(process.pid, signal.SIGTERM)
    try:
        output, _ = process.communicate(timeout=3)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        output, _ = process.communicate()
    output += '\nERROR: SQLcl stage timed out; inspect database state before retrying.\n'
    code = 124
# Strip ANSI sequences before storing/inspecting output.
output = re.sub(r'\x1b\[[0-9;]*[A-Za-z]', '', output)
path = Path(log_name)
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as stream:
    stream.write(output)
print(output, end='')
print(f'Log: {path}')
errors = re.search(r'\b(?:ORA|SP2|PLS|TNS)-\d+|(?im:^\s*(?:error\b|connection failed\b|unknown command\b|invalid command\b))|(?im:^\s*Errors:\s*[1-9]\d*)', output)
if code or errors or 'APEXCICD_STAGE_COMPLETE' not in output:
    sys.exit(code if code else 1)
