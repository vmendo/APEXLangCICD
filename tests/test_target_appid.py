"""Offline selection and persistence tests; no database access."""
import argparse
import contextlib
import importlib.util
import io
import json
import stat
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('target_appid', ROOT / 'run/aux/target_appid.py')
HELPER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HELPER)


class TargetApplicationIdTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.project = self.root / 'Customers'
        self.project.mkdir()
        self.args = argparse.Namespace(inventory=self.root/'inventory', state=self.root/'selection.json',
            project_env=self.root/'project.env', project_dir=self.project,
            deployment=self.root/'deployment.json', attempt=self.root/'attempt.json',
            setup=self.root/'setup.json', project_name='Customers', schema='DEMO',
            workspace='DEMO', preferred=103)
        self.content = f'# retained comment\nPROJECT_NAME=Customers\nPROJECT_DIR={self.project}\nAPEX_APP_ID_PRO=103\nOTHER_SETTING=unchanged\n'
        self.args.project_env.write_text(self.content)
        self.inventory()

    def inventory(self, occupied=(), database='PRODB'):
        self.args.inventory.write_text('banner\nAPEXCICD_IDENTITY|ADMIN|' + database + '|pro_low\n' +
            ''.join(f'APEXCICD_APPID|{n}\n' for n in occupied))

    def select(self):
        with contextlib.redirect_stdout(io.StringIO()):
            return HELPER.select(self.args)

    def manifest(self, app_id=103, **changes):
        record = dict(project='Customers', project_dir=str(self.project), database='PRODB',
            service='pro_low', schema='DEMO', workspace='DEMO', app_id=app_id,
            application_owned=True)
        record.update(changes)
        self.args.deployment.write_text(json.dumps(record))

    def test_default_103_is_selected_when_free(self):
        self.assertEqual(self.select(), 103)

    def test_occupied_103_selects_104_without_adoption(self):
        self.inventory([103])
        self.assertEqual(self.select(), 104)

    def test_first_free_id_after_consecutive_collisions(self):
        self.inventory([103,104,105])
        self.assertEqual(self.select(), 106)

    def test_fractional_internal_application_ids_do_not_block_selection(self):
        self.inventory(['103.0', '8842.242', '8842.261', '8842.9999'])
        self.assertEqual(self.select(), 104)

    def test_fractional_metadata_uses_decimal_without_float_rounding(self):
        self.inventory(['103.0000000000000000000000000001'])
        self.assertEqual(self.select(), 103)

    def test_invalid_inventory_tokens_fail_before_state_write(self):
        for token in ('invalid', 'NaN', 'Infinity', '-1', '0', '1e3'):
            with self.subTest(token=token):
                self.inventory([token])
                with self.assertRaisesRegex(ValueError, 'invalid application ID'):
                    self.select()
                self.assertFalse(self.args.state.exists())

    def test_retained_selection_is_stable_even_if_preferred_becomes_free(self):
        self.inventory([103]); self.assertEqual(self.select(), 104)
        self.inventory(); self.assertEqual(self.select(), 104)

    def test_undeployed_selection_taken_elsewhere_selects_another_free_id(self):
        self.assertEqual(self.select(), 103)
        self.inventory([103,104]); self.assertEqual(self.select(), 105)

    def test_deployed_id_never_changes_when_occupied(self):
        self.assertEqual(self.select(), 103)
        self.manifest(); self.inventory([103,104])
        self.assertEqual(self.select(), 103)

    def test_deployed_id_without_selection_state_is_pinned(self):
        self.manifest(app_id=110); self.inventory([103,110])
        self.assertEqual(self.select(), 110)

    def test_deployed_record_mismatch_fails_without_writes(self):
        self.assertEqual(self.select(), 103)
        original = self.args.project_env.read_bytes()
        self.manifest(app_id=104)
        with self.assertRaisesRegex(ValueError, 'pinned selection'):
            self.select()
        self.assertEqual(self.args.project_env.read_bytes(), original)
        self.assertEqual(json.loads(self.args.state.read_text())['app_id'], 103)

    def test_partial_attempt_blocks_without_writes(self):
        self.args.attempt.write_text('{}')
        with self.assertRaisesRegex(ValueError, 'incomplete deployment'):
            self.select()
        self.assertFalse(self.args.state.exists())
        self.assertEqual(self.args.project_env.read_text(), self.content)

    def test_identity_mismatch_does_not_change_environment_or_selection(self):
        self.assertEqual(self.select(), 103)
        state = self.args.state.read_bytes(); env = self.args.project_env.read_bytes()
        self.inventory(database='ANOTHERDB')
        with self.assertRaisesRegex(ValueError, 'identity mismatch'):
            self.select()
        self.assertEqual(self.args.state.read_bytes(), state)
        self.assertEqual(self.args.project_env.read_bytes(), env)

    def test_setup_mismatch_does_not_write_state(self):
        self.args.setup.write_text(json.dumps(dict(database='WRONG', service='pro_low', schema='DEMO', workspace='DEMO')))
        with self.assertRaisesRegex(ValueError, 'Production setup identity mismatch'):
            self.select()
        self.assertFalse(self.args.state.exists())
        self.assertEqual(self.args.project_env.read_text(), self.content)

    def test_permissions_and_other_environment_lines_preserved(self):
        self.inventory([103]); self.select()
        self.assertEqual(stat.S_IMODE(self.args.state.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.args.project_env.stat().st_mode), 0o600)
        self.assertEqual(self.args.project_env.read_text(), self.content.replace('APEX_APP_ID_PRO=103','APEX_APP_ID_PRO=104') + 'APEX_APP_ID_PRO_PREFERRED=103\n')

    def test_existing_preferred_environment_setting_is_updated_without_duplicate(self):
        self.args.project_env.write_text(self.content + 'APEX_APP_ID_PRO_PREFERRED=999\n')
        self.select()
        content = self.args.project_env.read_text()
        self.assertEqual(content.count('APEX_APP_ID_PRO_PREFERRED='), 1)
        self.assertIn('APEX_APP_ID_PRO_PREFERRED=103\n', content)

    def test_other_project_environment_is_rejected_without_state_write(self):
        self.args.project_env.write_text(self.content.replace('PROJECT_NAME=Customers','PROJECT_NAME=Other'))
        with self.assertRaisesRegex(ValueError, 'another active project'):
            self.select()
        self.assertFalse(self.args.state.exists())


if __name__ == '__main__':
    unittest.main()
