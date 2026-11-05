#!/usr/bin/env python3
"""Map the native APEXlang controller generated in the published artifact."""
import json
import os
import re
import sys
import zipfile
from pathlib import Path, PurePosixPath
import xml.etree.ElementTree as ET

artifact, inventory, output = map(Path, sys.argv[1:])
before = json.loads(inventory.read_text())
app = int(os.environ['APEX_APP_ID'])
target = int(os.environ['APEX_APP_ID_PRO'])
schema = os.environ['SCHEMA_NAME_PRO']
workspace = os.environ['APEX_WORKSPACE_PRO']
if (before['schema'], before['workspace'], before['app_id']) != (schema, workspace, target):
    raise SystemExit('Target inventory differs from configured schema/workspace/application.')
with zipfile.ZipFile(artifact) as archive:
    defaults = [name for name in archive.namelist() if name.endswith('env/default.properties')]
    candidates = []
    for name in archive.namelist():
        if not name.endswith('.xml') or '/apex/' not in '/' + name:
            continue
        xml = archive.read(name).decode()
        if 'runApexScript' not in xml or 'apex import -input ' not in xml:
            continue
        root = ET.fromstring(xml)
        source = '\n'.join(root.itertext())
        if not re.search(r"l_app_id\s+varchar2\(255\)\s*:=\s*q'\[" + str(app) + r"\]'", source):
            continue
        prefixes = set(re.findall(r'\$\{apex\.([A-Za-z0-9_-]+)\.schema\}', source))
        if len(prefixes) != 1:
            raise SystemExit('Native APEXlang controller parameters are missing or ambiguous.')
        alias = prefixes.pop()
        for key in ('schema', 'workspace', 'appId'):
            if '${apex.' + alias + '.' + key + '}' not in source:
                raise SystemExit('Unverified APEX override parameter: ' + key)
        # Bind the controller to the actual APEXlang payload, not a comment or
        # a different application's controller in a cumulative release ZIP.
        input_match = re.search(r'(?m)^apex import -input ([A-Za-z0-9_-]+)\s*$', source)
        if not input_match or input_match[1] != alias:
            raise SystemExit('Unexpected native APEXlang import path.')
        payload = str(PurePosixPath(name).parent / alias)
        if payload + '/application.apx' not in archive.namelist():
            raise SystemExit('Native APEXlang application source is missing from the artifact.')
        deployment = json.loads(archive.read(payload + '/deployments/default.json'))
        if deployment.get('app', {}).get('id') != app:
            raise SystemExit('Native APEXlang payload application ID differs from its controller.')
        candidates.append(alias)
    if len(defaults) != 1 or len(candidates) != 1:
        raise SystemExit('Release defaults/native APEXlang controller is missing or ambiguous.')
    content = archive.read(defaults[0]).decode()
alias = candidates[0]
source_schema = os.environ['SCHEMA_NAME'].lower()
pattern = r'(?m)^parameter\.' + re.escape(source_schema) + r'\s*=.*$'
if len(re.findall(pattern, content)) != 1:
    raise SystemExit('Source schema substitution parameter is missing or ambiguous.')
content = re.sub(pattern, 'parameter.' + source_schema + '=' + schema, content)
for key, value in {'schema': schema, 'workspace': workspace, 'appId': str(target)}.items():
    content += f'\nparameter.apex.{alias}.{key}={value}\n'
output.write_text(content)
output.chmod(0o600)
print(f'Prepared native APEXlang mappings for {alias}: application {app} -> {target}; {output}.')
