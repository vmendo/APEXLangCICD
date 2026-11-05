#!/usr/bin/env python3
"""Reject target collisions before applying a release artifact."""
import json
import sys
from pathlib import Path
from record_deployment import METADATA, object_set, source_inventory
project, snapshot, setup_path, manifest_path = map(Path, sys.argv[1:])
name, source = source_inventory(project)
before=json.loads(snapshot.read_text());setup=json.loads(setup_path.read_text())
old=json.loads(manifest_path.read_text()) if manifest_path.exists() else None
for key in ('database','service','schema','workspace'):
    if before[key]!=setup[key]:raise SystemExit('Target setup identity mismatch: '+key)
if old:
    if old.get('project_dir')!=str(project.resolve()):raise SystemExit('Prior deployment belongs to another project directory.')
    for key in ('database','service','schema','workspace','app_id'):
        if old[key]!=before[key]: raise SystemExit('Prior deployment identity mismatch: '+key)
    if old['project']!=name:raise SystemExit('Prior deployment belongs to another project.')
owned={(o['name'],o['type']) for o in old['objects']} if old else set()
collisions=((source|METADATA)&object_set(before))-owned
if collisions:raise SystemExit('Target objects predate demo ownership: '+repr(sorted(collisions)))
if before['application_exists'] and not (old and old.get('application_owned')):
    raise SystemExit('Target application already exists without demo ownership.')
print('Target ownership preflight passed.')
