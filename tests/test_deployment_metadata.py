"""Offline integration checks for release mapping and target ownership guards."""
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class DeploymentMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name).resolve()
        self.project = self.home / 'TrainingHub'
        (self.project / '.dbtools').mkdir(parents=True)
        (self.project / '.dbtools/project.config.json').write_text(json.dumps(
            {'project': 'TrainingHub', 'schemas': ['DEMO']}))
        tables = self.project / 'src/database/demo/tables'
        tables.mkdir(parents=True)
        (tables / 'demo_trn_employees.sql').write_text('create table demo.demo_trn_employees(id number);')
        # Real SQLcl ref-constraint filenames contain dots and are not objects.
        refs = tables.parent / 'ref_constraints'
        refs.mkdir()
        (refs / 'demo_trn_enrollments.demo.demo_trn_employees.sql').write_text('-- FK')
        self.inventory = self.home / 'before.json'
        self.setup = self.home / 'setup.json'
        self.manifest = self.home / 'deployment.json'
        self.defaults = self.home / 'target.properties'
        self.before = dict(database='PRODB', service='prod_low', schema='DEMO_PRO',
                           workspace='PRO_WORKSPACE', app_id=210,
                           application_exists=False,
                           objects=[], changelog=[])
        self.write_inventory()
        self.setup.write_text(json.dumps({key: self.before[key] for key in
                                         ('database', 'service', 'schema', 'workspace')}))
        self.artifact = self.home / 'TrainingHub-1.0.zip'
        # Native SQLcl 26.3 APEXlang controller/payload layout. Parameter
        # prefixes use the application alias, not its numeric application ID.
        self.controller_path = 'releases/apex/training-hub/training-hub.xml'
        self.payload_path = 'releases/apex/training-hub/training-hub'
        self.payload_id = 110
        self.include_payload = True
        self.include_controller = True
        self.extra_entries = {}
        self.controller = """<databaseChangeLog><changeSet><runApexScript>
<![CDATA[
declare
l_app_id varchar2(255) := q'[110]';
l_override_schema := q'[${apex.training-hub.schema}]';
l_override_workspace := q'[${apex.training-hub.workspace}]';
l_override_app_id := q'[${apex.training-hub.appId}]';
begin null; end;
/
apex import -input training-hub
]]></runApexScript></changeSet></databaseChangeLog>"""
        self.write_artifact()
        self.env = dict(os.environ, APEX_APP_ID='110', APEX_APP_ID_PRO='210',
                        SCHEMA_NAME='DEMO', SCHEMA_NAME_PRO='DEMO_PRO',
                        APEX_WORKSPACE_PRO='PRO_WORKSPACE')

    def write_inventory(self):
        self.inventory.write_text(json.dumps(self.before))

    def write_artifact(self):
        with zipfile.ZipFile(self.artifact, 'w') as archive:
            archive.writestr('env/default.properties', 'parameter.demo=demo\n')
            if self.include_controller:
                archive.writestr(self.controller_path, self.controller)
            if self.include_payload:
                archive.writestr(self.payload_path + '/application.apx', 'application training-hub {}\n')
                archive.writestr(self.payload_path + '/deployments/default.json',
                                 json.dumps({'app': {'id': self.payload_id}}))
            for name, value in self.extra_entries.items():
                archive.writestr(name, value)

    def run_helper(self, helper, *args):
        return subprocess.run([sys.executable, str(ROOT / 'run' / 'aux' / helper),
                               *map(str, args)], env=self.env, text=True,
                              capture_output=True, timeout=10)

    def prepare(self):
        return self.run_helper('prepare_deploy_defaults.py', self.artifact,
                               self.inventory, self.defaults)

    def preflight(self):
        return self.run_helper('deployment_preflight.py', self.project,
                               self.inventory, self.setup, self.manifest)

    def ownership(self, **overrides):
        value = {key: self.before[key] for key in
                 ('database', 'service', 'schema', 'workspace', 'app_id')}
        value.update(project='TrainingHub', project_dir=str(self.project),
                     application_owned=True,
                     objects=[{'name': 'DEMO_TRN_EMPLOYEES', 'type': 'TABLE'}])
        value.update(overrides)
        self.manifest.write_text(json.dumps(value))

    def test_native_controller_alias_mappings_and_private_defaults(self):
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        content = self.defaults.read_text()
        for line in ('parameter.demo=DEMO_PRO',
                     'parameter.apex.training-hub.schema=DEMO_PRO',
                     'parameter.apex.training-hub.workspace=PRO_WORKSPACE',
                     'parameter.apex.training-hub.appId=210'):
            self.assertIn(line, content)
        self.assertNotIn('parameter.apex.110.', content)
        self.assertNotIn('.offset=', content)
        self.assertFalse((self.home / 'target-offset.json').exists())
        self.assertEqual(stat.S_IMODE(self.defaults.stat().st_mode), 0o600)

    def test_inventory_mismatch_rejected_before_defaults_creation(self):
        for key, value in [('schema', 'WRONG'), ('workspace', 'WRONG'), ('app_id', 999)]:
            with self.subTest(key=key):
                original = self.before[key]
                self.before[key] = value
                self.write_inventory()
                result = self.prepare()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('differs from configured', result.stderr)
                self.assertFalse(self.defaults.exists())
                self.before[key] = original

    def test_incremental_application_needs_no_persisted_synthetic_offset(self):
        self.before['application_exists'] = True
        self.write_inventory()
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('parameter.apex.training-hub.appId=210', self.defaults.read_text())
        self.assertNotIn('offset', self.defaults.read_text().lower())
        self.assertFalse(list(self.home.glob('*offset*')))

    def test_missing_native_controller_rejected(self):
        self.include_controller = False
        self.write_artifact()
        result = self.prepare()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('controller is missing or ambiguous', result.stderr)
        self.assertFalse(self.defaults.exists())

    def test_ambiguous_native_controllers_rejected(self):
        prefix = 'another-release/apex/training-hub/'
        self.extra_entries = {
            prefix + 'training-hub.xml': self.controller,
            prefix + 'training-hub/application.apx': 'application training-hub {}',
            prefix + 'training-hub/deployments/default.json': json.dumps({'app': {'id': 110}}),
        }
        self.write_artifact()
        result = self.prepare()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('controller is missing or ambiguous', result.stderr)
        self.assertFalse(self.defaults.exists())

    def test_payload_application_id_mismatch_rejected(self):
        self.payload_id = 999
        self.write_artifact()
        result = self.prepare()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('payload application ID differs', result.stderr)
        self.assertFalse(self.defaults.exists())

    def test_missing_apexlang_payload_rejected(self):
        self.include_payload = False
        self.write_artifact()
        result = self.prepare()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('application source is missing', result.stderr)
        self.assertFalse(self.defaults.exists())

    def test_unknown_controller_override_parameter_rejected(self):
        self.controller = self.controller.replace('${apex.training-hub.workspace}', '${apex.training-hub.unknown}')
        self.write_artifact()
        result = self.prepare()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unverified APEX override parameter: workspace', result.stderr)
        self.assertFalse(self.defaults.exists())

    def test_ambiguous_controller_parameter_prefixes_rejected(self):
        self.controller = self.controller.replace('begin null;', '${apex.other.schema}\nbegin null;')
        self.write_artifact()
        result = self.prepare()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('controller parameters are missing or ambiguous', result.stderr)
        self.assertFalse(self.defaults.exists())

    def test_import_path_must_match_native_controller_alias(self):
        self.controller = self.controller.replace('apex import -input training-hub', 'apex import -input other')
        self.write_artifact()
        result = self.prepare()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unexpected native APEXlang import path', result.stderr)
        self.assertFalse(self.defaults.exists())

    def test_cumulative_release_ignores_another_application_controller(self):
        prefix = 'releases/apex/another/'
        controller = self.controller.replace("q'[110]'", "q'[999]'").replace('training-hub', 'another')
        self.extra_entries = {
            prefix + 'another.xml': controller,
            prefix + 'another/application.apx': 'application another {}',
            prefix + 'another/deployments/default.json': json.dumps({'app': {'id': 999}}),
        }
        self.write_artifact()
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('parameter.apex.training-hub.appId=210', self.defaults.read_text())
        self.assertNotIn('parameter.apex.another.', self.defaults.read_text())

    def test_clean_target_and_unrelated_recycle_bin_objects_pass(self):
        self.before['objects'] = [{'name': 'BIN$abc/xyz==', 'type': 'TABLE'},
                                  {'name': 'An unrelated quoted name', 'type': 'TABLE'}]
        self.write_inventory()
        result = self.preflight()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_initial_source_object_collision_rejected(self):
        self.before['objects'] = [{'name': 'DEMO_TRN_EMPLOYEES', 'type': 'TABLE'}]
        self.write_inventory()
        result = self.preflight()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('predate demo ownership', result.stderr)

    def test_initial_application_collision_rejected(self):
        self.before['application_exists'] = True
        self.write_inventory()
        result = self.preflight()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('without demo ownership', result.stderr)

    def test_previous_owned_incremental_target_passes(self):
        self.before.update(application_exists=True,
                           objects=[{'name': 'DEMO_TRN_EMPLOYEES', 'type': 'TABLE'}])
        self.write_inventory()
        self.ownership()
        result = self.preflight()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_manifest_project_directory_mismatch_rejected(self):
        self.ownership(project_dir=str(self.home / 'OtherProject'))
        result = self.preflight()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('another project directory', result.stderr)

    def test_preexisting_migration_metadata_rejected(self):
        self.before['objects'] = [{'name': 'DATABASECHANGELOG', 'type': 'TABLE'}]
        self.write_inventory()
        result = self.preflight()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('DATABASECHANGELOG', result.stderr)


if __name__ == '__main__':
    unittest.main()
