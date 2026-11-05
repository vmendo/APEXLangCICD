#!/usr/bin/env python3
"""Select a free production APEX ID from a read-only administrator inventory."""
import argparse
import json
import os
import re
import shlex
import tempfile
from decimal import Decimal
from pathlib import Path


def load(path):
    if path.is_symlink():
        raise ValueError(f'Refusing a symlinked state file: {path}')
    return json.loads(path.read_text()) if path.exists() else None


def read_inventory(path):
    identities, occupied = set(), set()
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if line.startswith('APEXCICD_IDENTITY|'):
            parts = line.split('|')
            if len(parts) != 4 or parts[1] != 'ADMIN' or not all(parts[2:]):
                raise ValueError('Administrator inventory identity is invalid.')
            identities.add(tuple(parts[2:]))
        elif line.startswith('APEXCICD_APPID|'):
            value = line.split('|', 1)[1]
            if not re.fullmatch(r'[0-9]+(?:\.[0-9]+)?', value):
                raise ValueError('Administrator inventory has an invalid application ID.')
            number = Decimal(value)
            if number <= 0:
                raise ValueError('Administrator inventory has an invalid application ID.')
            # APEX includes fractional internal/translated application IDs.
            # Our targets are integer IDs, so fractional entries cannot collide.
            if number == number.to_integral_value():
                occupied.add(int(number))
    if len(identities) != 1:
        raise ValueError('Exactly one administrator database identity is required.')
    return next(iter(identities)), occupied


def valid_id(value):
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ValueError('Application IDs must be positive integers.')
    return value


def validate_identity(record, identity, label):
    for key, expected in identity.items():
        if record.get(key) != expected:
            raise ValueError(f'{label} identity mismatch: {key}')


def update_env(content, app_id, preferred):
    for name, value in (('APEX_APP_ID_PRO', app_id), ('APEX_APP_ID_PRO_PREFERRED', preferred)):
        pattern = r'(?m)^(?:export[ \t]+)?' + name + r'[ \t]*=[^\r\n]*$'
        line = f'{name}={value}'
        if re.search(pattern, content):
            content = re.sub(pattern, line, content)
        else:
            content += ('' if not content or content.endswith('\n') else '\n') + line + '\n'
    return content


def validate_project_env(content, project, directory):
    values = {}
    for line in content.splitlines():
        match = re.match(r'^(?:export\s+)?(PROJECT_NAME|PROJECT_DIR)=(.*)$', line)
        if match:
            decoded = shlex.split(match[2])
            if len(decoded) != 1:
                raise ValueError('Project environment identity is invalid.')
            values[match[1]] = decoded[0]
    if values.get('PROJECT_NAME') != project or str(Path(values.get('PROJECT_DIR', '')).resolve()) != directory:
        raise ValueError('Project environment belongs to another active project.')


def atomic_pair(state_path, state_content, env_path, env_content):
    prepared = []
    try:
        for path, content in ((state_path, state_content), (env_path, env_content)):
            path.parent.mkdir(parents=True, exist_ok=True)
            fd, raw = tempfile.mkstemp(prefix=path.name + '-', dir=path.parent)
            prepared.append((Path(raw), path))
            with os.fdopen(fd, 'w') as stream:
                stream.write(content)
                stream.flush()
                os.fsync(stream.fileno())
        # Each individual replacement is atomic; both files are prepared first.
        for temporary, destination in prepared:
            os.replace(temporary, destination)
    finally:
        for temporary, _ in prepared:
            temporary.unlink(missing_ok=True)


def select(args):
    if args.attempt.exists() or args.attempt.is_symlink():
        raise ValueError('An incomplete deployment attempt blocks application ID selection.')
    if args.project_env.is_symlink() or not args.project_env.is_file():
        raise ValueError('A regular active project environment file is required.')
    directory = str(args.project_dir.resolve(strict=True))
    (database, service), occupied = read_inventory(args.inventory)
    preferred = valid_id(args.preferred)
    identity = dict(project=args.project_name, project_dir=directory,
                    database=database, service=service, schema=args.schema,
                    workspace=args.workspace)
    state, deployed, setup = load(args.state), load(args.deployment), load(args.setup)
    if setup:
        validate_identity(setup, {key: identity[key] for key in
                          ('database', 'service', 'schema', 'workspace')}, 'Production setup')
    if state:
        validate_identity(state, identity, 'Selected application')
        valid_id(state['app_id'])
    if deployed:
        validate_identity(deployed, identity, 'Deployment manifest')
        if not deployed.get('application_owned'):
            raise ValueError('Deployment manifest does not establish application ownership.')
        selected = valid_id(deployed['app_id'])
        if state and selected != state['app_id']:
            raise ValueError('Deployed application ID differs from the pinned selection.')
    elif state and state['app_id'] not in occupied:
        selected = state['app_id']
    else:
        selected = preferred
        while selected in occupied:
            selected += 1
    content = args.project_env.read_text()
    validate_project_env(content, args.project_name, directory)
    new_env = update_env(content, selected, preferred)
    record = dict(identity, app_id=selected, preferred=preferred)
    atomic_pair(args.state, json.dumps(record, indent=2) + '\n', args.project_env, new_env)
    print(selected)
    return selected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for flag in ('inventory', 'state', 'project-env', 'project-dir', 'deployment', 'attempt', 'setup'):
        parser.add_argument('--' + flag, required=True, type=Path)
    for flag in ('project-name', 'schema', 'workspace'):
        parser.add_argument('--' + flag, required=True)
    parser.add_argument('--preferred', required=True, type=int)
    select(parser.parse_args())


if __name__ == '__main__':
    main()
