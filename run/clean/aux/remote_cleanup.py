#!/usr/bin/env python3
"""Plan or empty demo-owned repository content without deleting the repository.

This resets reachable branch/tag content, releases, Actions storage/history, and
repository deployments. It does not erase GitHub's retained PR refs/conversations,
issues, account-scoped packages, wiki, settings, secrets, or environments.
"""
import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import quote

API_VERSION = '2022-11-28'
EXCLUDED = ['repository identity/settings/permissions/secrets/environments',
            'issues and pull-request conversations/internal retained refs',
            'account-scoped or shared GitHub Packages', 'separate wiki repository',
            'GitHub retention/backups and unreachable historical objects']
UNAVAILABLE_RULESETS = 'Upgrade to GitHub Pro or make this repository public to enable this feature.'


class ApiError(RuntimeError):
    def __init__(self, status, message):
        self.status = status
        self.message = message
        super().__init__(f'GitHub API HTTP {status}: {message}')


def command(args, **kwargs):
    result = subprocess.run(args, text=True, capture_output=True, timeout=60, **kwargs)
    if result.returncode:
        raise RuntimeError(f'Command failed: {args[0]} {args[1]}: {result.stderr.strip()}')
    return result.stdout.strip()


class GitHub:
    def __init__(self, repository):
        self.repository = repository
        self.prefix = f'repos/{repository}'

    def request(self, route='', method='GET', payload=None, paginate=False):
        endpoint = self.prefix + ('/' + route if route else '')
        # No caller can issue DELETE against the repository endpoint itself.
        if method == 'DELETE' and not route:
            raise RuntimeError('Repository deletion is forbidden.')
        args = ['gh', 'api', '--hostname', 'github.com', '--method', method,
                '-H', 'Accept: application/vnd.github+json',
                '-H', f'X-GitHub-Api-Version: {API_VERSION}']
        if paginate:
            args += ['--paginate', '--slurp']
        if payload is not None:
            args += ['--input', '-']
        args += [endpoint]
        try:
            raw = command(args, input=json.dumps(payload) if payload is not None else None)
        except RuntimeError as exc:
            match = re.search(r'gh:\s*(.*?)\s*\(HTTP (\d{3})\)', str(exc), re.DOTALL)
            if match:
                raise ApiError(int(match[2]), match[1].strip()) from exc
            raise
        return json.loads(raw) if raw else None

    def list(self, route, key=None):
        separator = '&' if '?' in route else '?'
        pages = self.request(route + separator + 'per_page=100', paginate=True)
        return [item for page in pages for item in (page[key] if key else page)]


def canonical_url(value):
    match = re.fullmatch(r'https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?/?', value)
    if not match:
        match = re.fullmatch(r'git@github\.com:([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?', value)
    if not match:
        raise ValueError('Only an explicit github.com HTTPS/SSH repository origin is supported.')
    return match.group(1).lower()


def verify_local(project, project_name, repository, expected_url):
    project = project.resolve(strict=True)
    if canonical_url(expected_url) != repository.lower():
        raise ValueError('Configured GitHub URL differs from configured repository.')
    marker = json.loads((project / '.apexcicd-project.json').read_text())
    config = json.loads((project / '.dbtools/project.config.json').read_text())
    if marker != {'project': project_name, 'directory': str(project)} or config['project'] != project_name:
        raise ValueError('Active project name/path markers do not match.')
    origin = command(['git', '-C', str(project), 'remote', 'get-url', 'origin'])
    if canonical_url(origin) != repository.lower():
        raise ValueError('Active project origin differs from cleanup repository.')
    return str(project)


def inventory(api):
    repo = api.request()
    branches = api.list('branches')
    refs = api.list('git/matching-refs/tags')
    releases = api.list('releases')
    artifacts = api.list('actions/artifacts', 'artifacts')
    runs = api.list('actions/runs', 'workflow_runs')
    caches = api.list('actions/caches', 'actions_caches')
    deployments = api.list('deployments')
    rulesets_unavailable = None
    try:
        rulesets = api.list('rulesets?includes_parents=true')
    except ApiError as exc:
        if (repo.get('owner', {}).get('type') == 'User'
                and exc.status == 403 and exc.message == UNAVAILABLE_RULESETS):
            # This account plan cannot enable rulesets on this repository.
            # Branch protection flags are still checked independently below.
            rulesets = []
            rulesets_unavailable = exc.message
        else:
            raise
    assets = []
    for release in releases:
        assets += [dict(asset, release_id=release['id']) for asset in api.list(f"releases/{release['id']}/assets")]
    blockers = []
    if repo.get('archived') or repo.get('disabled'):
        blockers.append('Repository is archived or disabled.')
    if not repo.get('permissions', {}).get('admin'):
        blockers.append('Repository administrator permission is required for this full reset.')
    if any(b.get('protected') for b in branches):
        blockers.append('Protected branches exist. This script never removes or bypasses protections.')
    if any(r.get('enforcement') != 'disabled' for r in rulesets):
        blockers.append('Active/inherited rulesets exist. This script never removes or bypasses rulesets.')
    if any(r.get('status') != 'completed' for r in runs):
        blockers.append('Active workflow runs exist. Finish/cancel them before cleanup.')
    default = repo['default_branch']
    if not any(b['name'] == default for b in branches):
        blockers.append('Default branch is absent; this reset expects an initialized repository.')
    return dict(repository={'id': repo['id'], 'full_name': repo['full_name'],
                            'url': repo['html_url'], 'clone_url': repo['clone_url'],
                            'default_branch': default},
                branches=branches, tags=refs, releases=releases, release_assets=assets,
                actions_artifacts=artifacts, workflow_runs=runs, actions_caches=caches,
                deployments=deployments, rulesets=rulesets,
                rulesets_unavailable=rulesets_unavailable, blockers=blockers,
                excluded=EXCLUDED)


def signature(plan):
    """Compare identity and mutable cleanup resources immediately before writes."""
    return (plan['repository'],
            sorted((b['name'], b['commit']['sha'], b.get('protected', False)) for b in plan['branches']),
            sorted((t['ref'], t['object']['sha']) for t in plan['tags']),
            *[sorted(x['id'] for x in plan[k]) for k in ('releases', 'release_assets',
               'actions_artifacts', 'workflow_runs', 'actions_caches', 'deployments')],
            plan['blockers'])


def empty_default(api, plan):
    repo = plan['repository']; default = repo['default_branch']
    expected = next(b['commit']['sha'] for b in plan['branches'] if b['name'] == default)
    with tempfile.TemporaryDirectory(prefix='apexcicd-empty-') as raw:
        git = ['git', '-C', raw]
        command(git + ['init', '--initial-branch', 'cleanup-empty'])
        command(git + ['-c', 'user.name=APEX CI/CD Demo', '-c', 'user.email=apexcicd@localhost',
                       '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', 'commit', '--allow-empty', '-m',
                       'chore: reset demo repository to an empty tree'])
        commit = command(git + ['rev-parse', 'HEAD'])
        empty_tree = command(git + ['rev-parse', 'HEAD^{tree}'])
        if command(git + ['ls-tree', '-r', '--name-only', 'HEAD']):
            raise RuntimeError('Local reset commit is not an empty tree.')
        command(git + ['remote', 'add', 'origin', repo['clone_url']])
        command(git + ['push', f'--force-with-lease=refs/heads/{default}:{expected}',
                       'origin', f'HEAD:refs/heads/{default}'])
    remote_commit = api.request('git/commits/' + commit)
    if remote_commit['parents']:
        raise RuntimeError('Reset commit unexpectedly has parents.')
    # GitHub can return404 for its empty tree object. Verify the remote commit
    # references the exact locally verified empty-tree hash instead.
    if remote_commit['tree']['sha'] != empty_tree:
        raise RuntimeError('Reset default branch does not reference the verified empty tree.')
    return commit


def apply(api, plan, reset=empty_default):
    if plan['blockers']:
        raise RuntimeError('Cleanup blocked: ' + ' '.join(plan['blockers']))
    fresh = inventory(api)
    if signature(fresh) != signature(plan):
        raise RuntimeError('Repository inventory changed. Review a fresh dry-run before retrying.')
    commit = reset(api, plan)
    for asset in plan['release_assets']:
        api.request(f"releases/assets/{asset['id']}", method='DELETE')
    for release in plan['releases']:
        api.request(f"releases/{release['id']}", method='DELETE')
    for kind, route in [('actions_artifacts', 'actions/artifacts'),
                        ('workflow_runs', 'actions/runs'), ('actions_caches', 'actions/caches')]:
        for item in plan[kind]:
            api.request(f"{route}/{item['id']}", method='DELETE')
    for item in plan['deployments']:
        api.request(f"deployments/{item['id']}/statuses", method='POST',
                    payload={'state': 'inactive', 'auto_inactive': False})
        api.request(f"deployments/{item['id']}", method='DELETE')
    for tag in plan['tags']:
        if not tag['ref'].startswith('refs/tags/'):
            raise RuntimeError('Unexpected tag reference.')
        api.request('git/refs/' + quote(tag['ref'][5:], safe='/'), method='DELETE')
    for branch in plan['branches']:
        if branch['name'] != plan['repository']['default_branch']:
            api.request('git/refs/heads/' + quote(branch['name'], safe='/'), method='DELETE')
    final = inventory(api)
    keys = ('tags','releases','release_assets','actions_artifacts','workflow_runs','actions_caches','deployments')
    if any(final[k] for k in keys) or len(final['branches']) != 1:
        raise RuntimeError('Remote cleanup is incomplete or new content appeared; inspect retained inventory.')
    if final['repository'] != plan['repository'] or final['branches'][0]['commit']['sha'] != commit:
        raise RuntimeError('Repository identity/default branch changed during cleanup.')
    return final


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as stream:
        json.dump(value, stream, indent=2); stream.write('\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True)
    parser.add_argument('--project-name', required=True)
    parser.add_argument('--project-dir', required=True, type=Path)
    parser.add_argument('--url', required=True)
    parser.add_argument('--plan', required=True, type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--dry-run', action='store_true', help='Inventory only; no remote mutations.')
    mode.add_argument('--yes', action='store_true', help='Apply destructive cleanup after inventory verification.')
    mode.add_argument('--confirm', action='store_true', help='Prompt for exact repository name before applying.')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', args.repo):
        parser.error('Repository must be an explicit owner/name.')
    project = verify_local(args.project_dir, args.project_name, args.repo, args.url)
    api = GitHub(args.repo)
    plan = inventory(api)
    if plan['repository']['full_name'].lower() != args.repo.lower():
        raise RuntimeError('GitHub returned another repository identity.')
    plan.update(project=project, project_name=args.project_name,
                generated_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    save(args.plan, plan)
    print(f"Repository: {plan['repository']['full_name']} (ID {plan['repository']['id']})")
    for key in ('branches','tags','releases','release_assets','actions_artifacts','workflow_runs','actions_caches','deployments'):
        print(f'{key}: {len(plan[key])}')
    print('The default branch remains with one parentless commit and an empty tree.')
    print('Excluded: ' + '; '.join(EXCLUDED))
    if plan['rulesets_unavailable']:
        print('Rulesets unavailable on this repository plan: ' + plan['rulesets_unavailable'])
    print(f'Inventory plan: {args.plan}')
    if plan['blockers']:
        print('Blockers: ' + ' '.join(plan['blockers']))
    apply_requested = args.yes
    if args.confirm and not args.yes:
        if not sys.stdin.isatty():
            raise RuntimeError('Exact-repository confirmation requires a terminal.')
        apply_requested = input(f'Type {args.repo} to empty repository content: ') == args.repo
        if not apply_requested:
            raise RuntimeError('Remote cleanup cancelled.')
    if not apply_requested:
        print('DRY RUN: no remote content was changed. Use --yes or --confirm to apply.')
        return
    final = apply(api, plan)
    save(args.plan.with_name(args.plan.stem + '-result.json'), final)
    print('Remote content emptied. Repository ID, URL, and settings were preserved.')


if __name__ == '__main__':
    main()
