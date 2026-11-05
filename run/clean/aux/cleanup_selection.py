#!/usr/bin/env python3
"""Select only application/page IDs present in a verified cleanup inventory."""
import argparse
import json
import sys


def select(inventory, kind, selected=None, skip=False, yes=False):
    if skip and selected:
        raise ValueError('Selection and skip cannot be combined.')
    key = 'apps' if kind == 'app' else 'pages'
    entries = inventory[key]
    allowed = {}
    for entry in entries:
        ident = entry['id']
        if isinstance(ident, bool) or not isinstance(ident, int):
            raise ValueError('Inventory IDs must be integers.')
        allowed[ident] = entry.get('name', '')
    if skip:
        return 'SKIP'
    print(f"{kind.title()} inventory in workspace {inventory['workspace']}:", file=sys.stderr)
    for ident, name in sorted(allowed.items()):
        safe = ''.join(c if c.isprintable() else ' ' for c in str(name))
        print(f'  {ident}: {safe}', file=sys.stderr)
    if selected is None:
        if not allowed:
            print('Nothing to delete.', file=sys.stderr)
            return 'SKIP'
        if yes:
            raise ValueError(f'Explicit {kind} IDs or --skip-{kind} are required with --yes.')
        if not sys.stdin.isatty():
            raise ValueError('Interactive selection needs a terminal; supply explicit IDs or skip.')
        print(f'Enter {kind} ID' + ('s separated by commas' if kind == 'page' else '') + ' to delete (Enter to skip): ', end='', file=sys.stderr, flush=True)
        selected = sys.stdin.readline().strip()
        if selected.lower() in ('', 's', 'skip'):
            return 'SKIP'
    values = selected.split(',')
    if any(not v.strip().isascii() or not v.strip().isdigit() for v in values):
        raise ValueError('IDs must be positive integers.')
    ids = list(dict.fromkeys(int(v.strip()) for v in values))
    if kind == 'app' and len(ids) != 1:
        raise ValueError('Select exactly one application.')
    if any(i <= 0 or i not in allowed for i in ids):
        raise ValueError('Selection is outside the inventory or is page zero. Use skip if already removed.')
    return ','.join(map(str, ids))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inventory', required=True)
    parser.add_argument('--kind', choices=('app', 'page'), required=True)
    parser.add_argument('--selected')
    parser.add_argument('--skip', action='store_true')
    parser.add_argument('--yes', action='store_true')
    args = parser.parse_args()
    try:
        with open(args.inventory) as stream:
            result = select(json.load(stream), args.kind, args.selected, args.skip, args.yes)
        print(result)
    except (ValueError, KeyError, OSError) as error:
        parser.exit(1, f'ERROR: {error}\n')


if __name__ == '__main__':
    main()
