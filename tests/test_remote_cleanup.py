"""Offline remote-reset checks: all GitHub and Git writes are mocked."""
import contextlib
import copy
import importlib.util
import io
import json
import stat
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('remote_cleanup', ROOT / 'run/clean/aux/remote_cleanup.py')
REMOTE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REMOTE)


class FakeGitHub:
    def __init__(self):
        self.calls = []
        self.cleaned = False
        self.protected = False
        self.active = False
        self.rules = []
        self.repo_id = 7

    def request(self, route='', method='GET', payload=None, **kwargs):
        self.calls.append((method, route, payload))
        if method == 'DELETE' and not route:
            raise AssertionError('A repository DELETE must never be sent.')
        if method == 'GET' and not route:
            return dict(id=self.repo_id, full_name='owner/demo',
                        html_url='https://github.com/owner/demo',
                        clone_url='https://github.com/owner/demo.git',
                        default_branch='main', permissions={'admin': True}, owner={'type': 'User'})
        return None

    def list(self, route, key=None):
        self.calls.append(('GET_LIST', route, key))
        if route == 'branches':
            branches = [dict(name='main', protected=self.protected,
                             commit={'sha': 'new' if self.cleaned else 'old'})]
            if not self.cleaned:
                branches.append(dict(name='feature/a', protected=False, commit={'sha': 'feature'}))
            return branches
        if self.cleaned:
            return []
        return copy.deepcopy({
            'git/matching-refs/tags': [{'ref': 'refs/tags/v1.0', 'object': {'sha': 'tag'}}],
            'releases': [{'id': 10}], 'releases/10/assets': [{'id': 11}],
            'actions/artifacts': [{'id': 12}],
            'actions/runs': [{'id': 13, 'status': 'queued' if self.active else 'completed'}],
            'actions/caches': [{'id': 14}], 'deployments': [{'id': 15}],
            'rulesets?includes_parents=true': self.rules,
        }[route])


class RemoteCleanupTests(unittest.TestCase):
    def test_inventory_is_read_only_and_includes_release_assets(self):
        api = FakeGitHub()
        plan = REMOTE.inventory(api)
        self.assertEqual(plan['release_assets'][0]['id'], 11)
        self.assertTrue(all(call[0] in ('GET', 'GET_LIST') for call in api.calls))

    def test_main_defaults_to_dry_run_and_saves_private_plan(self):
        api = FakeGitHub()
        with tempfile.TemporaryDirectory() as raw:
            plan = Path(raw) / 'plan.json'
            args = ['remote_cleanup.py', '--repo', 'owner/demo', '--project-name', 'Demo',
                    '--project-dir', raw, '--url', 'https://github.com/owner/demo.git',
                    '--plan', str(plan)]
            with patch.object(REMOTE.sys, 'argv', args), \
                    patch.object(REMOTE, 'verify_local', return_value=raw), \
                    patch.object(REMOTE, 'GitHub', return_value=api), \
                    patch.object(REMOTE, 'apply') as apply, \
                    contextlib.redirect_stdout(io.StringIO()) as output:
                REMOTE.main()
            apply.assert_not_called()
            self.assertIn('DRY RUN', output.getvalue())
            self.assertEqual(stat.S_IMODE(plan.stat().st_mode), 0o600)
            self.assertTrue(all(c[0] in ('GET', 'GET_LIST') for c in api.calls))

    def test_exact_delete_endpoints_and_repository_preservation(self):
        api = FakeGitHub()
        plan = REMOTE.inventory(api)
        def reset(fake, _plan):
            fake.cleaned = True
            return 'new'
        final = REMOTE.apply(api, plan, reset=reset)
        writes = [c for c in api.calls if c[0] in ('DELETE', 'POST', 'PATCH')]
        self.assertEqual(writes, [
            ('DELETE', 'releases/assets/11', None),
            ('DELETE', 'releases/10', None),
            ('DELETE', 'actions/artifacts/12', None),
            ('DELETE', 'actions/runs/13', None),
            ('DELETE', 'actions/caches/14', None),
            ('POST', 'deployments/15/statuses', {'state': 'inactive', 'auto_inactive': False}),
            ('DELETE', 'deployments/15', None),
            ('DELETE', 'git/refs/tags/v1.0', None),
            ('DELETE', 'git/refs/heads/feature/a', None),
        ])
        self.assertEqual(final['repository'], plan['repository'])
        self.assertEqual([b['name'] for b in final['branches']], ['main'])
        self.assertFalse(any(c[0] == 'DELETE' and not c[1] for c in api.calls))

    def test_repository_delete_is_forbidden_before_command_execution(self):
        with patch.object(REMOTE, 'command') as command:
            with self.assertRaisesRegex(RuntimeError, 'forbidden'):
                REMOTE.GitHub('owner/demo').request(method='DELETE')
            command.assert_not_called()

    def test_pagination_for_array_and_object_response_pages(self):
        with patch.object(REMOTE, 'command', return_value='[[{"id":1}],[{"id":2}]]') as command:
            self.assertEqual(REMOTE.GitHub('owner/demo').list('releases'), [{'id': 1}, {'id': 2}])
            argv = command.call_args.args[0]
            self.assertIn('--paginate', argv)
            self.assertIn('--slurp', argv)
            self.assertEqual(argv[-1], 'repos/owner/demo/releases?per_page=100')
        pages = '[{"artifacts":[{"id":3}]},{"artifacts":[{"id":4}]}]'
        with patch.object(REMOTE, 'command', return_value=pages):
            self.assertEqual(REMOTE.GitHub('owner/demo').list('actions/artifacts', 'artifacts'),
                             [{'id': 3}, {'id': 4}])

    def test_default_branch_reset_uses_empty_root_and_exact_lease(self):
        api = FakeGitHub()
        plan = REMOTE.inventory(api)
        def remote_read(route):
            if route == 'git/commits/new':
                return {'parents': [], 'tree': {'sha': 'empty'}}
            if route == 'git/trees/empty':
                raise REMOTE.ApiError(404, 'Not Found')
            raise AssertionError(route)
        with patch.object(api, 'request', side_effect=remote_read), \
                patch.object(REMOTE, 'command', side_effect=lambda argv, **_: ('empty' if argv[-1]=='HEAD^{tree}' else 'new') if 'rev-parse' in argv else '') as run:
            self.assertEqual(REMOTE.empty_default(api, plan), 'new')
        argv = [c.args[0] for c in run.call_args_list]
        push = next(c for c in argv if 'push' in c)
        self.assertEqual(push[-3:], ['--force-with-lease=refs/heads/main:old',
                                    'origin', 'HEAD:refs/heads/main'])
        self.assertTrue(any('--allow-empty' in c for c in argv))
        self.assertFalse(any('--force' in c for c in argv))
        self.assertTrue(any('core.hooksPath=/dev/null' in c for c in argv))

    def test_remote_commit_must_reference_the_verified_empty_tree(self):
        api=FakeGitHub();plan=REMOTE.inventory(api)
        with patch.object(api,'request',return_value={'parents':[],'tree':{'sha':'unexpected'}}), \
                patch.object(REMOTE,'command',side_effect=lambda a,**_: ('empty' if a[-1]=='HEAD^{tree}' else 'new') if 'rev-parse' in a else ''):
            with self.assertRaisesRegex(RuntimeError,'verified empty tree'):
                REMOTE.empty_default(api,plan)

    def test_local_nonempty_tree_blocks_before_push(self):
        api=FakeGitHub();plan=REMOTE.inventory(api)
        def local(a,**_):
            if 'ls-tree' in a:return 'unexpected.txt'
            if 'rev-parse' in a:return 'empty' if a[-1]=='HEAD^{tree}' else 'new'
            return ''
        with patch.object(REMOTE,'command',side_effect=local) as run:
            with self.assertRaisesRegex(RuntimeError,'not an empty tree'):
                REMOTE.empty_default(api,plan)
        self.assertFalse(any('push' in c.args[0] for c in run.call_args_list))

    def test_protections_rulesets_and_active_workflows_block_before_writes(self):
        for kind in ('protected', 'active', 'rules'):
            with self.subTest(kind=kind):
                api = FakeGitHub()
                setattr(api, kind, [{'enforcement': 'active'}] if kind == 'rules' else True)
                plan = REMOTE.inventory(api)
                self.assertTrue(plan['blockers'])
                with patch.object(REMOTE, 'empty_default') as reset:
                    with self.assertRaisesRegex(RuntimeError, 'blocked'):
                        REMOTE.apply(api, plan, reset=reset)
                    reset.assert_not_called()
                self.assertFalse(any(c[0] in ('DELETE', 'POST', 'PATCH') for c in api.calls))

    def test_inventory_change_blocks_before_reset(self):
        api = FakeGitHub()
        plan = REMOTE.inventory(api)
        api.repo_id = 99
        with patch.object(REMOTE, 'empty_default') as reset:
            with self.assertRaisesRegex(RuntimeError, 'inventory changed'):
                REMOTE.apply(api, plan, reset=reset)
            reset.assert_not_called()
        self.assertFalse(any(c[0] in ('DELETE', 'POST', 'PATCH') for c in api.calls))

    def test_local_repository_binding_rejects_other_origin(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw).resolve()
            (root / '.dbtools').mkdir()
            (root / '.dbtools/project.config.json').write_text('{"project":"Demo"}')
            (root / '.apexcicd-project.json').write_text(json.dumps({'project': 'Demo', 'directory': str(root)}))
            with patch.object(REMOTE, 'command', return_value='https://github.com/owner/other.git'):
                with self.assertRaisesRegex(ValueError, 'origin differs'):
                    REMOTE.verify_local(root, 'Demo', 'owner/demo', 'https://github.com/owner/demo.git')
            with patch.object(REMOTE, 'command', return_value='git@github.com:owner/demo.git'):
                self.assertEqual(REMOTE.verify_local(root, 'Demo', 'owner/demo',
                                                    'https://github.com/owner/demo.git'), str(root))

    def test_rulesets_unavailable_plan_error_is_narrowly_reported(self):
        api = FakeGitHub()
        original = api.list
        def unavailable(route, key=None):
            if route.startswith('rulesets'):
                raise REMOTE.ApiError(403, REMOTE.UNAVAILABLE_RULESETS)
            return original(route, key)
        with patch.object(api, 'list', side_effect=unavailable):
            plan = REMOTE.inventory(api)
        self.assertEqual(plan['rulesets'], [])
        self.assertEqual(plan['rulesets_unavailable'], REMOTE.UNAVAILABLE_RULESETS)
        self.assertFalse(plan['blockers'])

    def test_generic_rulesets_permission_error_is_not_ignored(self):
        api = FakeGitHub()
        original = api.list
        def forbidden(route, key=None):
            if route.startswith('rulesets'):
                raise REMOTE.ApiError(403, 'Resource not accessible by integration')
            return original(route, key)
        with patch.object(api, 'list', side_effect=forbidden):
            with self.assertRaises(REMOTE.ApiError):
                REMOTE.inventory(api)

    def test_upgrade_error_on_organization_is_not_ignored(self):
        api = FakeGitHub()
        original_list, original_request = api.list, api.request
        def organization(route='', **kwargs):
            value = original_request(route, **kwargs)
            if not route:
                value['owner']['type'] = 'Organization'
            return value
        def unavailable(route, key=None):
            if route.startswith('rulesets'):
                raise REMOTE.ApiError(403, REMOTE.UNAVAILABLE_RULESETS)
            return original_list(route, key)
        with patch.object(api, 'list', side_effect=unavailable), patch.object(api, 'request', side_effect=organization):
            with self.assertRaises(REMOTE.ApiError):
                REMOTE.inventory(api)

    def test_api_error_extracts_only_explicit_http_message(self):
        message = 'Command failed: gh api: gh: ' + REMOTE.UNAVAILABLE_RULESETS + ' (HTTP 403)'
        with patch.object(REMOTE, 'command', side_effect=RuntimeError(message)):
            with self.assertRaises(REMOTE.ApiError) as captured:
                REMOTE.GitHub('owner/demo').request('rulesets')
        self.assertEqual(captured.exception.status, 403)
        self.assertEqual(captured.exception.message, REMOTE.UNAVAILABLE_RULESETS)

    def test_failed_final_inventory_is_not_reported_as_complete(self):
        api = FakeGitHub()
        plan = REMOTE.inventory(api)
        with self.assertRaisesRegex(RuntimeError, 'incomplete'):
            REMOTE.apply(api, plan, reset=lambda *_: 'new')


if __name__ == '__main__':
    unittest.main()
