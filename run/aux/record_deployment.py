#!/usr/bin/env python3
"""Record explicit ownership after a verified deployment; never access a database."""
import argparse
import json
import os
import re
import tempfile
from pathlib import Path

TYPES = {'tables': 'TABLE', 'indexes': 'INDEX', 'sequences': 'SEQUENCE',
         'views': 'VIEW', 'materialized_views': 'MATERIALIZED VIEW',
         'package_specs': 'PACKAGE', 'package_bodies': 'PACKAGE BODY',
         'procedures': 'PROCEDURE', 'functions': 'FUNCTION', 'triggers': 'TRIGGER',
         'types': 'TYPE', 'type_bodies': 'TYPE BODY', 'synonyms': 'SYNONYM'}
METADATA = {('DATABASECHANGELOG', 'TABLE'), ('DATABASECHANGELOGLOCK', 'TABLE'),
            ('DATABASECHANGELOG_ACTIONS', 'TABLE'), ('DATABASECHANGELOG_DETAILS', 'VIEW'),
            ('DATABASECHANGELOG_ACTIONS_TRG', 'TRIGGER'), ('DATABASECHANGELOG_ACTIONS_PK', 'INDEX')}
IDENTIFIER = re.compile(r'[A-Z][A-Z0-9_$#]{0,127}')

def source_inventory(project):
    """Use the typed SQLcl 26.3 source tree, not SQL text inference."""
    config = json.loads((project / '.dbtools/project.config.json').read_text())
    schemas = config['schemas']
    if len(schemas) != 1:
        raise ValueError('Ownership recording requires exactly one source schema.')
    root = project / 'src/database' / schemas[0].lower()
    objects = set()
    for path in root.glob('*/*.sql'):
        folder = path.parent.name
        if folder in ('comments', 'ref_constraints', 'constraints'):
            # SQLcl names these files after qualified table/column pairs.
            # They are not independently droppable USER_OBJECTS entries.
            continue
        name = path.stem.upper()
        if not name.startswith('DEMO_TRN_'):
            continue
        if not IDENTIFIER.fullmatch(name):
            raise ValueError(f'Unsupported source identifier: {name}')
        if folder not in TYPES:
            raise ValueError(f'Unsupported SQLcl source object category: {folder}')
        objects.add((name, TYPES[folder]))
    if not any(kind == 'TABLE' for _, kind in objects):
        raise ValueError('No DEMO_TRN_ tables were found in the exported source inventory.')
    return config['project'], objects

def object_set(inventory):
    result = set()
    for obj in inventory['objects']:
        name, kind = obj['name'], obj['type']
        # Recycle-bin names and unrelated quoted identifiers are not demo-owned.
        if not name.startswith('DEMO_TRN_') and (name, kind) not in METADATA:
            continue
        if not IDENTIFIER.fullmatch(name):
            raise ValueError('Invalid target object identifier.')
        result.add((name, kind))
    return result

def record(args):
    project = Path(args.project_dir).resolve(strict=True)
    project_name, source = source_inventory(project)
    setup = json.loads(Path(args.production_setup).read_text())
    before = json.loads(Path(args.before).read_text())
    after = json.loads(Path(args.after).read_text())
    output = Path(args.output)
    old = json.loads(output.read_text()) if output.exists() else None
    for key in ('database', 'service', 'schema', 'workspace'):
        if before[key] != setup[key] or after[key] != setup[key]:
            raise ValueError(f'Production identity mismatch: {key}')
    if before['app_id'] != after['app_id']:
        raise ValueError('Application identity changed during deployment.')
    if old:
        for key, value in [('project', project_name), ('project_dir', str(project)),
                           ('database', setup['database']), ('service', setup['service']),
                           ('schema', setup['schema']), ('workspace', setup['workspace']),
                           ('app_id', after['app_id'])]:
            if old.get(key) != value:
                raise ValueError(f'Existing deployment manifest belongs to another demo: {key}')
    previous = {(x['name'], x['type']) for x in old['objects']} if old else set()
    prior, current = object_set(before), object_set(after)
    collisions = (source & prior) - previous
    if collisions:
        raise ValueError(f'Source objects predate this demo deployment: {sorted(collisions)}')
    if before['application_exists'] and not (old and old.get('application_owned')):
        raise ValueError('Target application predates this demo deployment.')
    if not after['application_exists'] or not source <= current:
        raise ValueError('Post-deployment application or source object inventory is incomplete.')
    owned = previous | source | ((current - prior) & METADATA)
    changelog = after.get('changelog')
    metadata_tables = {name for name, kind in owned if (name, kind) in METADATA and kind == 'TABLE'}
    if metadata_tables and changelog is None:
        # Objects are recorded, but cleanup will refuse metadata removal without rows.
        changelog = None
    manifest = dict(project=project_name, project_dir=str(project), version=args.version,
                    database=setup['database'], service=setup['service'], schema=setup['schema'],
                    workspace=setup['workspace'], app_id=after['app_id'], application_owned=True,
                    objects=[{'name': n, 'type': t} for n, t in sorted(owned)],
                    changelog=changelog)
    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='deployment-', dir=output.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(manifest, stream, indent=2); stream.write('\n')
        os.replace(temporary, output)
    finally:
        Path(temporary).unlink(missing_ok=True)
    print(f'Recorded {len(owned)} demo-owned objects at {output}.')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for flag in ('project-dir', 'production-setup', 'version', 'before', 'after', 'output'):
        parser.add_argument('--' + flag, required=True)
    record(parser.parse_args())

if __name__ == '__main__':
    main()
