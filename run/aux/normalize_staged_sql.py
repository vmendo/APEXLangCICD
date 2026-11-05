#!/usr/bin/env python3
"""Apply narrow SQLcl 26.3 compatibility fixes to native project sources/staging."""
import argparse
import json
import os
import re
import stat
import tempfile
from pathlib import Path

IDENTIFIER = re.compile(r'[A-Za-z][A-Za-z0-9_$#]*')
SIMPLE_PLACEHOLDER = re.compile(r'\$\{([A-Za-z][A-Za-z0-9_$#]*)\}')
PACKAGE_HEADER = re.compile(r'\bcreate\s+(?:or\s+replace\s+)?(?:(?:non)?editionable\s+)?package\s+(?!body\b)([A-Za-z][A-Za-z0-9_$#]*)(?:\s*\.\s*([A-Za-z][A-Za-z0-9_$#]*))?\s+(?:as|is)\b', re.I)


def safe_path(path, project):
    path.relative_to(project)
    current = project
    for component in path.relative_to(project).parts:
        current /= component
        if current.is_symlink():
            raise ValueError(f'Symlinked staged/source path is forbidden: {current}')
    if not path.resolve(strict=True).is_relative_to(project):
        raise ValueError(f'Path escapes the active project: {path}')
    return path


def sql_files(root, project):
    safe_path(root, project)
    for directory, dirs, files in os.walk(root, followlinks=False):
        for name in dirs + files:
            safe_path(Path(directory) / name, project)
        for name in sorted(files):
            if name.endswith('.sql'):
                yield Path(directory) / name


def normalization_plan(project):
    raw = Path(project).absolute()
    if raw.is_symlink():
        raise ValueError('Symlinked project roots are forbidden.')
    project = raw.resolve(strict=True)
    config_path = safe_path(project / '.dbtools/project.config.json', project)
    config = json.loads(config_path.read_text())
    schemas = config['schemas']
    if not schemas or any(not IDENTIFIER.fullmatch(s) for s in schemas):
        raise ValueError('Configured schemas must be unquoted simple identifiers.')
    configured = {s.casefold() for s in schemas}
    packages = {}
    for schema in schemas:
        root = project / 'src/database' / schema.lower() / 'package_specs'
        if not root.exists():
            # Still reject a dangling symlink instead of treating it as absent.
            if root.is_symlink():
                raise ValueError('Symlinked package source directory is forbidden.')
            continue
        for path in sql_files(root, project):
            name = path.stem
            header = PACKAGE_HEADER.search(path.read_text())
            if not IDENTIFIER.fullmatch(name) or not header:
                raise ValueError(f'Cannot verify an unquoted source package name: {path}')
            declared = header[2] or header[1]
            if declared.casefold() != name.casefold():
                raise ValueError(f'Source package filename/declaration mismatch: {path}')
            if header[2] and header[1].casefold() != schema.casefold():
                raise ValueError(f'Source package schema mismatch: {path}')
            packages[name.casefold()] = name.lower()
    stage = project / 'dist/releases/next'
    if not stage.is_dir():
        raise ValueError('The unreleased dist/releases/next directory is missing.')
    changes = []
    for path in sql_files(stage, project):
        original = path.read_bytes()
        text = original.decode('utf-8')
        # External package qualifiers can also be mistaken for schema names.
        # Accept only dotted identifiers found literally in the corresponding
        # original source file; a custom migration has no such source proof.
        source_text = ''
        relative = path.relative_to(stage).parts
        for index, part in enumerate(relative[:-2]):
            if part.casefold() in configured:
                candidate = project / 'src/database' / Path(*relative[index:])
                if candidate.is_file():
                    safe_path(candidate, project)
                    source_text = candidate.read_text()
                break
        def substitute(match):
            name = match[1].casefold()
            if name in configured:
                return match[0]
            if name in packages:
                return packages[name]
            if text[match.end():].startswith('.') and re.search(
                    r'(?<![A-Za-z0-9_$#])' + re.escape(match[1]) + r'\.', source_text, re.I):
                return match[1].lower()
            raise ValueError(f'Unknown simple staged SQL placeholder {match[0]} in {path.relative_to(project)}')
        normalized = SIMPLE_PLACEHOLDER.sub(substitute, text).encode('utf-8')
        if normalized != original:
            changes.append((path, original, normalized, stat.S_IMODE(path.stat().st_mode)))
    return project, changes


def normalize(project):
    project, changes = normalization_plan(project)
    # All placeholders and paths are validated before creating any output files.
    prepared = []
    try:
        for path, original, normalized, mode in changes:
            safe_path(path, project)
            if path.read_bytes() != original:
                raise ValueError('Staged SQL changed during normalization; retry from a clean stage.')
            fd, temporary = tempfile.mkstemp(prefix='.normalize-', dir=path.parent)
            prepared.append((Path(temporary), path))
            with os.fdopen(fd, 'wb') as stream:
                stream.write(normalized)
                stream.flush(); os.fsync(stream.fileno())
            os.chmod(temporary, mode)
        for temporary, path in prepared:
            os.replace(temporary, path)
    finally:
        for temporary, _ in prepared:
            temporary.unlink(missing_ok=True)
    print(f'Normalized known package qualifiers in {len(changes)} unreleased staged SQL file(s).')
    return len(changes)


def normalize_source_files(project, app_id):
    """Repair only case-mismatched report-layout file references from export."""
    project = Path(project).resolve(strict=True)
    config = json.loads(safe_path(project / '.dbtools/project.config.json', project).read_text())
    if not config.get('apex', {}).get('apexlang'):
        raise ValueError('Native APEXlang must be enabled for a fresh project.')
    roots = []
    for schema in config['schemas']:
        for deployment in (project / 'src/database' / schema.lower() / 'apex_apps').glob('*/deployments/default.json'):
            safe_path(deployment, project)
            if json.loads(deployment.read_text()).get('app', {}).get('id') == app_id:
                roots.append(deployment.parent.parent)
    if len(roots) != 1:
        raise ValueError('Native APEXlang source for the configured app is missing or ambiguous.')
    root = roots[0]
    safe_path(root / 'application.apx', project)
    changes = []
    for path in root.rglob('*.apx'):
        safe_path(path, project)
        original = path.read_text()
        def repair(match):
            reference = match[1]
            target = path.parent / reference
            if target.is_file() and target.name == reference:
                # On a case-insensitive filesystem existence alone is not proof
                # that the exact exported spelling matches the reference.
                if reference in {p.name for p in path.parent.iterdir()}:
                    safe_path(target, project)
                    return match[0]
            matches = [p for p in path.parent.iterdir() if p.name.casefold() == reference.casefold() and p.is_file()]
            if len(matches) != 1:
                raise ValueError(f'Missing or ambiguous native report layout file: {reference}')
            safe_path(matches[0], project)
            return match[0].replace(reference, matches[0].name)
        normalized = re.sub(r'(?m)^\s*pageFile:\s*([A-Za-z0-9_.-]+)\s*$', repair, original)
        if normalized != original:
            changes.append((path, normalized))
    for path, normalized in changes:
        path.write_text(normalized)
    print(f'Normalized report-layout reference case in {len(changes)} native source file(s).')
    return len(changes)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project-dir', type=Path, required=True)
    parser.add_argument('--source-files', action='store_true')
    parser.add_argument('--app-id', type=int)
    args = parser.parse_args()
    if args.source_files:
        if not args.app_id or args.app_id <= 0:
            parser.error('--source-files requires a positive --app-id')
        normalize_source_files(args.project_dir, args.app_id)
    else:
        normalize(args.project_dir)


if __name__ == '__main__':
    main()
