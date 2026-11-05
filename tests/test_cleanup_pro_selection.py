"""Exercise production cleanup selection using fake inventory and SQL boundaries."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]


class CleanupProductionSelectionTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.home=Path(self.temp.name).resolve()
        run=self.home/'run'; (run/'clean/aux').mkdir(parents=True)
        self.script=run/'clean/cleanup_pro.sh'; shutil.copy2(ROOT/'run/clean/cleanup_pro.sh',self.script)
        (self.home/'.state').mkdir()
        self.sql=self.home/'sql.log'
        (run/'aux').mkdir()
        (run/'aux/common.sh').write_text('''DEMO_HOME="$TEST_HOME"
PROJECT_NAME=TrainingHubCICD
PROJECT_DIR="$TEST_HOME/nonexistent-project"
DB_CONNECT_DEV=DEV
DB_CONNECT_PRO=PRO
DB_CONNECT_ADMIN=ADMIN
SCHEMA_NAME_PRO=DEMO
APEX_WORKSPACE_PRO=DEMO
APEX_APP_ID_PRO=110
require_tools() { :; }
validate_identifier() { :; }
die() { echo "$*" >&2; exit 1; }
run_sql() { printf '\\nSTAGE:%s:%s\\n' "$1" "$2" >> "$TEST_SQL"; cat >> "$TEST_SQL"; }
''')
        (run/'clean/aux/apex_cleanup_inventory.sh').write_text('''#!/usr/bin/env bash
[[ "$1" == PRO && "$2" == apps ]] || exit 9
cp "$TEST_INVENTORY" "$3"
'''); (run/'clean/aux/apex_cleanup_inventory.sh').chmod(0o755)
        # Exercise cleanup's contract with the shared selector without any DB.
        (run/'clean/aux/cleanup_selection.py').write_text('''import argparse,json
p=argparse.ArgumentParser()
p.add_argument('--inventory');p.add_argument('--kind');p.add_argument('--selected',type=int)
p.add_argument('--skip',action='store_true');p.add_argument('--yes',action='store_true')
a=p.parse_args(); rows=json.load(open(a.inventory))['apps']
if a.skip: print('SKIP')
elif a.selected is not None:
 if a.selected not in {r['id'] for r in rows}:raise SystemExit('Selected app outside inventory')
 print(a.selected)
else:raise SystemExit('Explicit application selection required; --yes never guesses')
''')
        self.inventory=self.home/'inventory.json'
        self.scope=dict(schema='DEMO',workspace='DEMO',database='PRODB',service='pro_low')
        self.write_inventory([111,112])
        self.env=dict(os.environ,TEST_HOME=str(self.home),TEST_SQL=str(self.sql),TEST_INVENTORY=str(self.inventory))
        self.setup=self.home/'.state/production-setup.json'
        self.manifest=self.home/'.state/deployment.json'
        self.setup.write_text(json.dumps(dict(self.scope,connection='PRO')))

    def write_inventory(self,apps,**changes):
        value=dict(self.scope,apps=[{'id':n,'name':f'App {n}'} for n in apps]); value.update(changes)
        self.inventory.write_text(json.dumps(value))

    def own_objects(self):
        self.manifest.write_text(json.dumps(dict(self.scope,project='TrainingHubCICD',
            project_dir=str(self.home/'nonexistent-project'),app_id=111,application_owned=True,
            objects=[{'name':'DEMO_TRN_COURSES','type':'TABLE'}],changelog=[])))

    def cleanup(self,*args):
        return subprocess.run(['bash',str(self.script),*args],env=self.env,text=True,capture_output=True,timeout=10)

    def sql_text(self):return self.sql.read_text() if self.sql.exists() else ''

    def test_recorded_deployment_id_used_instead_of_default_source_id(self):
        self.own_objects(); result=self.cleanup('--yes')
        self.assertEqual(result.returncode,0,result.stderr)
        sql=self.sql_text()
        self.assertIn('remove_application(p_application_id=>111)',sql)
        self.assertNotIn('p_application_id=>110',sql)
        self.assertIn('DROP TABLE "DEMO_TRN_COURSES" CASCADE CONSTRAINTS',sql)
        self.assertIn("user <> 'ADMIN' or sys_context('USERENV','DB_NAME') <> 'PRODB'",sql)
        self.assertFalse(self.manifest.exists())

    def test_skip_app_with_owned_objects_succeeds_when_app_manually_deleted(self):
        self.own_objects(); self.write_inventory([])
        result=self.cleanup('--skip-app','--yes')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertNotIn('remove_application',self.sql_text())
        self.assertIn('DROP TABLE "DEMO_TRN_COURSES"',self.sql_text())
        self.assertEqual(json.loads(self.setup.read_text())['application_cleanup'],'skipped')

    def test_recorded_missing_app_is_not_replaced_with_another_application(self):
        self.own_objects(); self.write_inventory([112])
        result=self.cleanup('--yes')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('already absent',result.stdout)
        self.assertNotIn('remove_application',self.sql_text())

    def test_skip_without_project_or_manifest_performs_no_database_actions(self):
        self.setup.unlink()
        result=self.cleanup('--skip-app','--yes')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertFalse(self.sql.exists())
        self.assertIn('no database objects were removed',result.stdout)

    def test_unknown_app_yes_alone_does_not_guess_or_run_sql(self):
        result=self.cleanup('--yes')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('never guesses',result.stderr)
        self.assertFalse(self.sql.exists())

    def test_explicit_scoped_app_only_cleanup_without_project_or_manifest(self):
        result=self.cleanup('--app-id','112','--yes')
        self.assertEqual(result.returncode,0,result.stderr)
        sql=self.sql_text()
        self.assertIn('remove_application(p_application_id=>112)',sql)
        self.assertNotIn('DROP TABLE',sql)
        self.assertNotIn('DROP USER',sql)
        self.assertNotIn('cleanup-pro-dependencies',sql)
        self.assertIn('workspace=\'DEMO\' and owner=\'DEMO\'',sql)
        self.assertIn('sys_context(\'USERENV\',\'SERVICE_NAME\') <> \'pro_low\'',sql)

    def test_app_outside_target_scope_rejected_before_sql(self):
        result=self.cleanup('--app-id','110','--yes')
        self.assertNotEqual(result.returncode,0)
        self.assertFalse(self.sql.exists())

    def test_wrong_workspace_inventory_rejected_before_sql(self):
        self.write_inventory([112],workspace='OTHER')
        result=self.cleanup('--app-id','112','--yes')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('inventory/setup mismatch',result.stderr)
        self.assertFalse(self.sql.exists())

    def test_owned_database_cleanup_cannot_select_another_app(self):
        self.own_objects()
        result=self.cleanup('--app-id','112','--yes')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('recorded deployed application ID 111',result.stderr)
        self.assertFalse(self.sql.exists())

    def test_skip_and_explicit_id_are_rejected_as_ambiguous(self):
        result=self.cleanup('--skip-app','--app-id','111','--yes')
        self.assertNotEqual(result.returncode,0)
        self.assertFalse(self.sql.exists())

    def test_legacy_customers_objects_in_manifest_are_not_removed(self):
        self.own_objects()
        manifest=json.loads(self.manifest.read_text())
        manifest['objects']=[{'name':'EBA_CUST_CUSTOMERS','type':'TABLE'}]
        self.manifest.write_text(json.dumps(manifest))
        result=self.cleanup('--yes')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('unsupported object',result.stderr)
        self.assertFalse(self.sql.exists())
        self.assertTrue(self.manifest.exists())

    def test_mixed_unrelated_objects_stop_cleanup_before_any_sql(self):
        self.own_objects()
        manifest=json.loads(self.manifest.read_text())
        manifest['objects'].append({'name':'UNRELATED_TABLE','type':'TABLE'})
        self.manifest.write_text(json.dumps(manifest))
        result=self.cleanup('--yes')
        self.assertNotEqual(result.returncode,0)
        self.assertFalse(self.sql.exists())
        self.assertTrue(self.manifest.exists())

    def test_prefix_lookalike_is_not_owned_training_scope(self):
        self.own_objects()
        manifest=json.loads(self.manifest.read_text())
        manifest['objects']=[{'name':'DEMOXTRNX_COURSES','type':'TABLE'}]
        self.manifest.write_text(json.dumps(manifest))
        result=self.cleanup('--yes')
        self.assertNotEqual(result.returncode,0)
        self.assertFalse(self.sql.exists())

    def test_owned_certification_sequence_is_removed_with_recorded_objects(self):
        self.own_objects()
        manifest=json.loads(self.manifest.read_text())
        manifest['objects'].extend([
            {'name':'DEMO_TRN_CERTIFICATIONS','type':'TABLE'},
            {'name':'DEMO_TRN_CERTIFICATIONS_SEQ','type':'SEQUENCE'}])
        self.manifest.write_text(json.dumps(manifest))
        result=self.cleanup('--yes')
        self.assertEqual(result.returncode,0,result.stderr)
        sql=self.sql_text()
        self.assertIn('DROP SEQUENCE "DEMO_TRN_CERTIFICATIONS_SEQ"',sql)
        self.assertIn('DROP TABLE "DEMO_TRN_CERTIFICATIONS"',sql)
        self.assertNotIn('EBA_CUST',sql)
        self.assertNotIn('p_application_id=>112',sql)


if __name__=='__main__':unittest.main()
