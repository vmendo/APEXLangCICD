"""Exercise DEV cleanup selection without opening a database connection."""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1]


class DevelopmentCleanupTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name).resolve()
        (self.home / 'run/clean/aux').mkdir(parents=True)
        shutil.copy2(SOURCE / 'run/clean/cleanup_dev.sh', self.home / 'run/clean/cleanup_dev.sh')
        (self.home / 'run/aux').mkdir()
        (self.home / 'run/aux/common.sh').write_text('''
DEMO_HOME="$TEST_HOME"
PROJECT_NAME=TrainingHubCICD
DB_CONNECT_DEV=ADB_LOCAL_DEMO
SCHEMA_NAME=DEMO
APEX_WORKSPACE_DEV=DEMO
APEX_APP_ID=110
die() { echo "ERROR: $*" >&2; exit 1; }
require_tools() { :; }
validate_identifier() { [[ "$1" =~ ^[A-Z][A-Z0-9_]*$ ]] || die invalid; }
validate_name() { [[ "$1" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] || die invalid; }
load_project() { die "No active project should be required by this fixture."; }
run_sql() { printf 'LABEL:%s\\n' "$2" >> "$TEST_CAPTURE"; cat >> "$TEST_CAPTURE"; }
''')
        (self.home / 'run/clean/aux/apex_cleanup_inventory.sh').write_text('''#!/usr/bin/env bash
set -euo pipefail
python3 - "$3" <<'PY_INVENTORY'
import os, sys
from pathlib import Path
fd = os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as stream:
    stream.write(Path(os.environ['TEST_INVENTORY']).read_text())
PY_INVENTORY
''')
        # Selection itself is tested separately. Here a deterministic stand-in
        # lets us test that the shell script independently guards its writes.
        (self.home / 'run/clean/aux/cleanup_selection.py').write_text('''import os
print(os.environ.get('TEST_SELECTION', 'SKIP'))
''')
        self.inventory = {'schema': 'DEMO', 'workspace': 'DEMO', 'database': 'MYATP',
                          'service': 'myatp_high.adb.oraclecloud.com', 'app_id': 110,
                          'apps': [{'id': 110, 'name': 'Training Hub'}],
                          'pages': [{'id': 500, 'name': 'Certifications'},
                                    {'id': 501, 'name': 'Edit Certification'},
                                    {'id': 59, 'name': 'Training Hub'}]}
        self.capture = self.home / 'sql-capture.txt'

    def run_cleanup(self, *args, selection='SKIP'):
        inventory_path = self.home / 'inventory.json'
        inventory_path.write_text(json.dumps(self.inventory))
        env = dict(os.environ, TEST_HOME=str(self.home), TEST_CAPTURE=str(self.capture),
                   TEST_INVENTORY=str(inventory_path), TEST_SELECTION=selection)
        return subprocess.run(['bash', str(self.home / 'run/clean/cleanup_dev.sh'), *args],
                              env=env, text=True, capture_output=True, timeout=10)

    def captured_sql(self):
        return self.capture.read_text() if self.capture.exists() else ''

    def test_unattended_requires_an_explicit_page_decision(self):
        result = self.run_cleanup('--yes')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.capture.exists())

    def test_skip_keeps_application_and_still_reverts_database_changes(self):
        result = self.run_cleanup('--yes', '--skip-page')
        self.assertEqual(result.returncode, 0, result.stderr)
        sql = self.captured_sql().lower()
        self.assertIn('drop table demo_trn_certifications', sql)
        self.assertIn('drop sequence demo_trn_certifications_seq', sql)
        self.assertIn('drop constraint demo_trn_courses_cert_req_ck', sql)
        self.assertIn('drop column certification_required', sql)
        self.assertLess(sql.index('drop constraint demo_trn_courses_cert_req_ck'),
                        sql.index('drop column certification_required'))
        self.assertNotIn('drop table demo_trn_courses', sql)
        self.assertNotIn('drop table demo_trn_employees', sql)
        self.assertNotIn('eba_cust', sql)
        for column in ('employee_id','course_id','certificate_code','issued_on','status'):
            self.assertIn(f"'demo_trn_certifications_{column}_nn'", sql)
        self.assertIn("'demo_trn_courses_cert_req_nn'", sql)
        self.assertNotIn('remove_page', sql)
        self.assertNotIn('remove_application', sql)
        self.assertNotIn('apex_application_install', sql)
        self.assertNotIn('@"', sql)

    def test_two_selected_pages_are_targeted_without_restoring_the_app(self):
        result = self.run_cleanup('--yes', '--page-id', '500', '--page-id', '501', selection='500,501')
        self.assertEqual(result.returncode, 0, result.stderr)
        sql = self.captured_sql()
        self.assertIn('500', sql)
        self.assertIn('501', sql)
        self.assertNotIn('BASELINE_EXPORT', sql)
        self.assertNotIn('remove_application', sql.lower())
        self.assertNotIn('apex_application_install', sql.lower())
        self.assertIn('Certifications', result.stdout + result.stderr)
        self.assertIn('Edit Certification', result.stdout + result.stderr)

    def test_page_zero_is_rejected_before_database_work(self):
        result = self.run_cleanup('--yes', '--page-id', '0', selection='0')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.capture.exists())

    def test_selection_outside_inventory_is_rejected(self):
        result = self.run_cleanup('--yes', '--page-id', '999', selection='999')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('LABEL:cleanup-dev-', self.captured_sql())

    def test_wrong_inventory_schema_is_rejected(self):
        self.inventory['schema'] = 'OTHER'
        result = self.run_cleanup('--yes', '--skip-page')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.capture.exists())

    def test_page_skip_and_selection_are_mutually_exclusive(self):
        result = self.run_cleanup('--yes', '--skip-page', '--page-id', '500', selection='500')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.capture.exists())

    def test_inventory_helper_receives_a_new_output_file(self):
        result = self.run_cleanup('--yes', '--skip-page')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(list((self.home / '.state').glob('cleanup-dev.*')), [])

    def test_saved_identity_works_after_generated_project_was_deleted(self):
        (self.home / '.state').mkdir()
        (self.home / '.state/project.env').write_text(
            'PROJECT_NAME=TrainingHubCICD\nPROJECT_DIR=/missing/deleted/project\n')
        result = self.run_cleanup('--yes', '--skip-page')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('drop table DEMO_TRN_CERTIFICATIONS', self.captured_sql())


if __name__ == '__main__':
    unittest.main()
