#!/usr/bin/env python3
"""Validate timeout recovery ownership offline; never alter deployment state or DBs."""
import argparse
import hashlib
import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path, PurePosixPath
from record_deployment import METADATA, object_set, source_inventory

IDENTITY = ('database', 'service', 'schema', 'workspace', 'app_id')
CHANGESET = re.compile(r'^\s*--\s*changeset\s+([^\s:]+):([^\s]+)([^\r\n]*)$', re.I | re.M)
LOGICAL = re.compile(r'\blogicalFilePath\s*:\s*(?:"([^"]+)"|\x27([^\x27]+)\x27|(\S+))', re.I)


def read_json(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError(f'A regular JSON file is required: {path}')
    return json.loads(path.read_text())


def changelog_keys(inventory):
    rows = inventory.get('changelog')
    if not isinstance(rows, list):
        raise ValueError('A complete changelog inventory is required for recovery.')
    result = set()
    for row in rows:
        key = tuple(row.get(k) for k in ('id', 'author', 'filename'))
        if not all(isinstance(value, str) and value for value in key):
            raise ValueError('Invalid changelog identity in recovery inventory.')
        if key in result:
            raise ValueError('Duplicate changelog identity in recovery inventory.')
        result.add(key)
    return result


def logical_path(attributes, fallback):
    found = LOGICAL.search(attributes)
    return next(value for value in found.groups() if value is not None) if found else fallback


def artifact_changesets(artifact):
    """Read exact Liquibase ID/author/logical-file identities from a release ZIP."""
    result = set()
    with zipfile.ZipFile(artifact) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Release artifact has ambiguous duplicate members.')
        for name in names:
            path = PurePosixPath(name)
            if path.is_absolute() or '..' in path.parts or '\\' in name:
                raise ValueError('Unsafe artifact member path.')
            if name.endswith('.sql'):
                text = archive.read(name).decode('utf-8')
                if not re.search(r'^\s*--\s*liquibase\s+formatted\s+sql\b', text, re.I | re.M):
                    continue
                global_match = re.search(r'^\s*--\s*(logicalFilePath\s*:[^\r\n]+)$', text, re.I | re.M)
                fallback = logical_path(global_match[1], name) if global_match else name
                for change in CHANGESET.finditer(text):
                    author, identifier, attributes = change.groups()
                    result.add((identifier, author, logical_path(attributes, fallback)))
            elif name.endswith('.xml'):
                text = archive.read(name).decode('utf-8')
                if not re.search(r'<(?:[A-Za-z0-9_]+:)?databaseChangeLog\b', text):
                    continue
                root = ET.fromstring(text)
                fallback = root.get('logicalFilePath', name)
                for change in root.iter():
                    if change.tag.rsplit('}', 1)[-1] != 'changeSet':
                        continue
                    identifier, author = change.get('id'), change.get('author')
                    if not identifier or not author:
                        raise ValueError('Artifact contains a changeset without ID/author.')
                    result.add((identifier, author, change.get('logicalFilePath', fallback)))
    if not result:
        raise ValueError('No verified Liquibase changesets were found in the release artifact.')
    return result


def validate(args):
    project = args.project_dir.resolve(strict=True)
    attempt = read_json(args.attempt)
    if Path(attempt['project_dir']).resolve() != project or attempt['version'] != args.version:
        raise ValueError('Deployment attempt belongs to another project or version.')
    snapshot = Path(attempt['snapshot_dir']).resolve(strict=True)
    before_path = snapshot / 'before.json'
    before, current = read_json(before_path), read_json(args.inventory)
    for key in IDENTITY:
        if before.get(key) is None or before.get(key) != current.get(key):
            raise ValueError(f'Deployment recovery target identity mismatch: {key}')
    for inventory in (before, current):
        if not isinstance(inventory.get('application_exists'), bool):
            raise ValueError('Application existence must be recorded explicitly.')
        if isinstance(inventory['app_id'], bool) or not isinstance(inventory['app_id'], int) or inventory['app_id'] <= 0:
            raise ValueError('Recovery requires the same positive integer target application ID.')
    name, source = source_inventory(project)
    prior_objects, current_objects = object_set(before), object_set(current)
    unexpected = current_objects - prior_objects - source - METADATA
    generated_indexes = {item for item in unexpected if item[1] == 'INDEX'}
    foreign_objects = unexpected - generated_indexes
    if foreign_objects:
        raise ValueError(f'Unexpected demo-scope objects appeared after the attempt: {sorted(foreign_objects)}')
    before_rows, current_rows = changelog_keys(before), changelog_keys(current)
    artifact_rows = artifact_changesets(args.artifact)
    foreign_rows = current_rows - before_rows - artifact_rows
    if foreign_rows:
        raise ValueError(f'Changelog contains rows outside the original inventory and release artifact: {sorted(foreign_rows)}')
    if not before_rows <= current_rows:
        raise ValueError('Previously recorded migration history disappeared after the attempt.')
    summary = dict(recoverable=True, project=name, project_dir=str(project), version=args.version,
                   snapshot_dir=str(snapshot), before_inventory=str(before_path),
                   current_inventory=str(args.inventory.resolve()), artifact=str(args.artifact.resolve()),
                   artifact_sha256=hashlib.sha256(args.artifact.read_bytes()).hexdigest(),
                   identity={key: before[key] for key in IDENTITY},
                   original_changesets=len(before_rows), artifact_changesets=len(artifact_rows),
                   applied_release_changesets=len((current_rows-before_rows) & artifact_rows),
                   current_business_objects=len(current_objects),
                   generated_indexes=[{'name': n, 'type': t} for n,t in sorted(generated_indexes)],
                   application_exists_before=before['application_exists'],
                   application_exists_current=current['application_exists'])
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for flag in ('project-dir', 'attempt', 'inventory', 'artifact', 'output'):
        parser.add_argument('--' + flag, type=Path, required=True)
    parser.add_argument('--version', required=True)
    args = parser.parse_args()
    summary = validate(args)
    if args.output.exists() or args.output.is_symlink():
        raise ValueError('Recovery summary already exists; choose a new audit output path.')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='resume-', dir=args.output.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(summary, stream, indent=2); stream.write('\n')
        # Link creates the final name atomically without replacing prior evidence.
        os.link(temporary, args.output)
    finally:
        Path(temporary).unlink(missing_ok=True)
    print(f'Recovery ownership preflight passed; original snapshot: {summary["snapshot_dir"]}.')


if __name__ == '__main__':
    main()
