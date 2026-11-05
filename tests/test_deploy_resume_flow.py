"""Run the deployment shell flow with local stand-ins and no database access."""
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1]


class DeployResumeFlowTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name).resolve()
        self.project = self.home / 'projects/CustomersCICD'
        self.project.mkdir(parents=True)
        self.aux = self.home / 'run/aux'
        self.aux.mkdir(parents=True)
        self.state = self.home / '.state'
        self.state.mkdir()
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        self.events = self.home / 'events.jsonl'
        self.artifact_bytes = b'offline immutable release artifact\n'
        self.artifact_fixture = self.home / 'release.fixture'
        self.artifact_fixture.write_bytes(self.artifact_bytes)
        self.artifact_sha = hashlib.sha256(self.artifact_bytes).hexdigest()
        self.attempt = self.state / 'deployment-attempt.json'
        self.original_snapshot = self.state / 'deployments/original-interrupted-attempt'
        self.original_snapshot.mkdir(parents=True)
        self.original_before = self.original_snapshot / 'before.json'
        self.original_before.write_text(json.dumps(self.inventory(104)))
        self.project_state = self.state / 'project.env'
        self.project_state.write_text(
            f'PROJECT_NAME=CustomersCICD\nPROJECT_DIR={self.project}\n'
            'APEX_APP_ID_PRO=103\n')
        (self.state / 'production-setup.json').write_text(json.dumps(self.inventory(103)))
        shutil.copy2(SOURCE / 'run/deploy_project.sh', self.home / 'run/deploy_project.sh')
        # Keep the actual default timeout/configuration behavior while replacing
        # connection handling and SQL execution below.
        shutil.copy2(SOURCE / 'run/aux/setup_env.sh', self.aux / 'setup_env.sh')
        (self.aux / 'common.sh').write_text(textwrap.dedent('''\
            source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup_env.sh"
            die() { printf 'ERROR: %s\\n' "$*" >&2; exit 1; }
            require_tools() { local tool; for tool in "$@"; do command -v "$tool" >/dev/null || die "Missing $tool"; done; }
            validate_version() { [[ "$1" =~ ^[0-9]+\\.[0-9]+$ ]] || die "Invalid release version"; }
            load_project() { source "$DEMO_HOME/.state/project.env"; export PROJECT_DIR PROJECT_NAME APEX_APP_ID_PRO; }
            run_sql() { python3 "$DEMO_HOME/fake_sql.py" "$1" "$2" "$SQLCL_TIMEOUT"; }
            '''))
        (self.home / 'test_support.py').write_text(textwrap.dedent('''\
            import json, os
            from pathlib import Path
            def emit(kind, **fields):
                event = {'kind': kind, **fields}
                with open(os.environ['TEST_EVENTS'], 'a') as stream:
                    stream.write(json.dumps(event) + '\\n')
            def attempt():
                p = Path(os.environ['TEST_HOME']) / '.state/deployment-attempt.json'
                return json.loads(p.read_text()) if p.exists() else None
            def app_id():
                return int(os.environ['APEX_APP_ID_PRO'])
            '''))
        self.write_executable(self.bin / 'git', '''
            import sys
            from test_support import emit
            args = sys.argv[1:]
            emit('git', args=args)
            if args[:1] == ['symbolic-ref']:
                print('main')
            elif args[:1] == ['rev-parse']:
                print('offline-main-sha')
            ''')
        self.write_executable(self.bin / 'gh', '''
            import hashlib, os, sys
            from pathlib import Path
            from test_support import emit
            args = sys.argv[1:]
            emit('download', args=args)
            directory = Path(args[args.index('--dir') + 1])
            name = args[args.index('--pattern') + 1]
            content = Path(os.environ['TEST_ARTIFACT']).read_bytes()
            (directory / name).write_bytes(content)
            digest = hashlib.sha256(content).hexdigest()
            (directory / (name + '.sha256')).write_text(digest + '  ' + name + '\\n')
            ''')
        self.write_executable(self.home / 'fake_sql.py', '''
            import json, os, sys
            from test_support import app_id, attempt, emit
            connection, label, timeout = sys.argv[1:]
            sql = sys.stdin.read()
            emit('sql', connection=connection, label=label, timeout=int(timeout),
                 script=sql, app_id=app_id(), attempt=attempt())
            if os.environ.get('TEST_FAIL_SQL_LABEL') == label:
                raise SystemExit(1)
            if label.startswith('deploy-') and os.environ.get('TEST_DEPLOY_TIMEOUT') == '1':
                raise SystemExit(124)
            ''')
        self.write_executable(self.aux / 'resolve_target_appid.sh', '''
            import os
            from pathlib import Path
            from test_support import emit
            emit('resolve')
            p = Path(os.environ['TEST_HOME']) / '.state/project.env'
            p.write_text(p.read_text().replace('APEX_APP_ID_PRO=103', 'APEX_APP_ID_PRO=104'))
            ''')
        self.write_executable(self.aux / 'check_environment.sh', '''
            import sys
            from test_support import app_id, emit
            emit('environment', environment=sys.argv[1], app_id=app_id())
            ''')
        self.write_executable(self.aux / 'capture_target_inventory.sh', '''
            import json, sys
            from pathlib import Path
            from test_support import app_id, attempt, emit
            p = Path(sys.argv[1])
            emit('inventory', path=str(p), app_id=app_id(), attempt=attempt())
            p.write_text(json.dumps(dict(schema='DEMO', workspace='DEMO',
                         database='PRODB', service='pro_high.adb.oraclecloud.com',
                         app_id=app_id(), objects=[], apps=[])))
            ''')
        self.write_python_helper('deployment_preflight.py', '''
            import sys
            from test_support import emit
            emit('preflight', args=sys.argv[1:])
            ''')
        self.write_python_helper('deployment_resume.py', '''
            import argparse, json, os
            from pathlib import Path
            from test_support import app_id, attempt, emit
            p = argparse.ArgumentParser()
            for name in ('project-dir','attempt','inventory','artifact','version','output'):
                p.add_argument('--' + name, required=True)
            a = p.parse_args()
            original = attempt()
            before = Path(original['snapshot_dir']) / 'before.json'
            emit('resume-validation', args=vars(a), app_id=app_id(),
                 before=str(before), before_contents=json.loads(before.read_text()))
            if os.environ.get('TEST_FAIL_RESUME') == '1':
                raise SystemExit('Offline resume validation rejected the inventory.')
            Path(a.output).write_text('{}')
            ''')
        self.write_python_helper('prepare_deploy_defaults.py', '''
            import sys
            from pathlib import Path
            from test_support import app_id, emit
            artifact, inventory, output = sys.argv[1:]
            emit('defaults', artifact=artifact, inventory=inventory, output=output, app_id=app_id())
            Path(output).write_text('parameter.apex.103.app_id=' + str(app_id()) + '\\n')
            ''')
        self.write_python_helper('record_deployment.py', '''
            import argparse, os
            from pathlib import Path
            from test_support import app_id, attempt, emit
            p = argparse.ArgumentParser()
            for name in ('project-dir','production-setup','version','before','after','output'):
                p.add_argument('--' + name, required=True)
            a = p.parse_args()
            emit('record', args=vars(a), app_id=app_id(), attempt=attempt())
            if os.environ.get('TEST_FAIL_RECORD') == '1':
                raise SystemExit('Offline record failure.')
            Path(a.output).write_text('{}')
            ''')

    @staticmethod
    def inventory(app_id):
        return dict(schema='DEMO', workspace='DEMO', database='PRODB',
                    service='pro_high.adb.oraclecloud.com', app_id=app_id,
                    objects=[], apps=[])

    def write_executable(self, path, body):
        path.write_text('#!/usr/bin/env python3\n' + textwrap.dedent(body).lstrip())
        path.chmod(0o755)

    def write_python_helper(self, name, body):
        self.write_executable(self.aux / name, body)

    def seed_attempt(self, version='1.0', digest=None):
        self.attempt.write_text(json.dumps(dict(
            project_dir=str(self.project), version=version,
            snapshot_dir=str(self.original_snapshot),
            artifact_sha256=self.artifact_sha if digest is None else digest)))

    def run_deploy(self, *args, **overrides):
        env = dict(os.environ)
        for key in ('SQLCL_TIMEOUT', 'SQLCL_DEPLOY_TIMEOUT', 'DEMO_HOME', 'PROJECT_DIR',
                    'PROJECT_NAME', 'APEX_APP_ID_PRO', 'GITHUB_REPO', 'PROJECTS_HOME'):
            env.pop(key, None)
        env.update(TEST_HOME=str(self.home), TEST_EVENTS=str(self.events),
                   TEST_ARTIFACT=str(self.artifact_fixture),
                   PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                   PYTHONPATH=str(self.home), **overrides)
        return subprocess.run(['bash', str(self.home / 'run/deploy_project.sh'), *args],
                              env=env, capture_output=True, text=True, timeout=20)

    def read_events(self):
        return [json.loads(line) for line in self.events.read_text().splitlines()] if self.events.exists() else []

    def sql_events(self):
        return [e for e in self.read_events() if e['kind'] == 'sql']

    def test_normal_deploy_records_digest_before_sql_and_clears_after_record(self):
        result = self.run_deploy('PRO', '1.0')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        events = self.read_events()
        deploy = next(e for e in events if e.get('label') == 'deploy-1.0')
        self.assertEqual(deploy['timeout'], 1800)
        self.assertEqual(deploy['attempt']['artifact_sha256'], self.artifact_sha)
        self.assertEqual(deploy['attempt']['version'], '1.0')
        before = Path(deploy['attempt']['snapshot_dir']) / 'before.json'
        self.assertTrue(before.is_file())
        after = next(e for e in events if e['kind'] == 'inventory' and Path(e['path']).name.startswith('after-'))
        record = next(e for e in events if e['kind'] == 'record')
        self.assertIsNotNone(after['attempt'])
        self.assertIsNotNone(record['attempt'])
        self.assertEqual(record['args']['before'], str(before))
        self.assertLess(events.index(deploy), events.index(after))
        self.assertLess(events.index(after), events.index(record))
        self.assertFalse(self.attempt.exists())
        self.assertFalse(any('release-locks' in e['script'] for e in self.sql_events()))

    def test_resume_pins_original_app_and_checks_guard_before_recovering_lock(self):
        self.seed_attempt()
        original_contents = self.original_before.read_bytes()
        result = self.run_deploy('PRO', '1.0', '--resume', SQLCL_DEPLOY_TIMEOUT='2400')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        events = self.read_events()
        self.assertFalse(any(e['kind'] == 'resolve' for e in events))
        self.assertTrue(all(e['app_id'] == 104 for e in events if 'app_id' in e))
        validation = next(e for e in events if e['kind'] == 'resume-validation')
        guard = next(e for e in events if e.get('label') == 'resume-deployment-sessions')
        lock = next(e for e in events if e.get('label') == 'resume-deployment-lock')
        deploy = next(e for e in events if e.get('label') == 'deploy-1.0')
        self.assertEqual(guard['connection'], 'ADMIN_ADBFREE')
        self.assertIn("user<>'ADMIN'", guard['script'])
        self.assertIn('v$session', guard['script'])
        self.assertIn("username='DEMO'", guard['script'])
        self.assertIn('if n>0', guard['script'])
        self.assertIn('lb release-locks', lock['script'])
        self.assertEqual(deploy['timeout'], 2400)
        self.assertLess(events.index(validation), events.index(guard))
        self.assertLess(events.index(guard), events.index(lock))
        self.assertLess(events.index(lock), events.index(deploy))
        self.assertEqual(validation['before'], str(self.original_before))
        record = next(e for e in events if e['kind'] == 'record')
        self.assertEqual(record['args']['before'], str(self.original_before))
        self.assertEqual(self.original_before.read_bytes(), original_contents)
        self.assertFalse(self.attempt.exists())

    def test_resume_validation_failure_retains_attempt_and_never_recovers_lock(self):
        self.seed_attempt()
        original_attempt = self.attempt.read_bytes()
        result = self.run_deploy('PRO', '1.0', '--resume', TEST_FAIL_RESUME='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.attempt.read_bytes(), original_attempt)
        self.assertEqual(self.sql_events(), [])

    def test_resume_artifact_change_fails_after_validation_before_admin_or_lock(self):
        self.seed_attempt(digest='0' * 64)
        result = self.run_deploy('PRO', '1.0', '--resume')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('differs from the interrupted deployment', result.stderr)
        self.assertTrue(self.attempt.exists())
        self.assertTrue(any(e['kind'] == 'resume-validation' for e in self.read_events()))
        self.assertEqual(self.sql_events(), [])

    def test_active_target_sessions_prevent_lock_release_and_deployment(self):
        self.seed_attempt()
        original_attempt = self.attempt.read_bytes()
        result = self.run_deploy('PRO', '1.0', '--resume', TEST_FAIL_SQL_LABEL='resume-deployment-sessions')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.attempt.read_bytes(), original_attempt)
        self.assertEqual([e['label'] for e in self.sql_events()], ['resume-deployment-sessions'])
        self.assertFalse(any(e['kind'] == 'record' for e in self.read_events()))

    def test_wrong_resume_version_stops_before_any_target_checks(self):
        self.seed_attempt()
        result = self.run_deploy('PRO', '2.0', '--resume')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('another project/version', result.stderr)
        self.assertEqual(self.read_events(), [])
        self.assertTrue(self.attempt.exists())

    def test_timeout_and_record_failure_both_preserve_attempt_for_inspection(self):
        for failure in ('TEST_DEPLOY_TIMEOUT', 'TEST_FAIL_RECORD'):
            with self.subTest(failure=failure):
                self.events.unlink(missing_ok=True)
                self.attempt.unlink(missing_ok=True)
                result = self.run_deploy('PRO', '1.0', **{failure: '1'})
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(self.attempt.exists())
                attempt = json.loads(self.attempt.read_text())
                self.assertEqual(attempt['artifact_sha256'], self.artifact_sha)
                if failure == 'TEST_DEPLOY_TIMEOUT':
                    self.assertFalse(any(e['kind'] == 'record' for e in self.read_events()))


if __name__ == '__main__':
    unittest.main()
