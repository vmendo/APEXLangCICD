"""Offline guards for SQLcl stage-only package qualifier normalization."""
import contextlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('normalize_staged_sql',ROOT/'run/aux/normalize_staged_sql.py')
HELPER = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(HELPER)


class StagedSQLTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.project = Path(self.tmp.name).resolve()/'Project'; self.project.mkdir()
        config = self.project/'.dbtools'; config.mkdir()
        (config/'project.config.json').write_text(json.dumps({'schemas':['DEMO']}))
        package = self.project/'src/database/demo/package_specs'; package.mkdir(parents=True)
        (package/'eba_cust_fw.sql').write_text('create or replace package demo.eba_cust_fw as\n function get_preference_value return varchar2;\nend;\n/\n')
        self.stage = self.project/'dist/releases/next/changes/demo/package_bodies'; self.stage.mkdir(parents=True)
        self.sql = self.stage/'eba_cust_email.sql'
        self.original = 'create or replace package body ${demo}.eba_cust_email as\n x varchar2(50) := ${eba_cust_fw}.get_preference_value();\nend;\n/\n'
        self.sql.write_text(self.original)

    def normalize(self):
        with contextlib.redirect_stdout(io.StringIO()):
            return HELPER.normalize(self.project)

    def test_external_qualifier_requires_corresponding_source_proof(self):
        source = self.project / 'src/database/demo/package_bodies/eba_cust_email.sql'
        source.parent.mkdir(parents=True)
        source.write_text('begin apex_escape.html(hello); end; /')
        self.sql.write_text('begin ${apex_escape}.html(hello); end; /')
        self.assertEqual(self.normalize(), 1)
        self.assertIn('apex_escape.html', self.sql.read_text())
        self.assertEqual(source.read_text(), 'begin apex_escape.html(hello); end; /')

    def native_layout(self):
        (self.project/'.dbtools/project.config.json').write_text(json.dumps({'schemas':['DEMO'],'apex':{'apexlang':True}}))
        root = self.project / 'src/database/demo/apex_apps/customers'
        (root / 'deployments').mkdir(parents=True)
        (root / 'deployments/default.json').write_text(json.dumps({'app':{'id':103}}))
        (root / 'application.apx').write_text('application CUSTOMERS ()')
        layout = root / 'shared-components/report-layouts'
        layout.mkdir(parents=True)
        (layout/'report-layouts.apx').write_text('templates {\n    pageFile: CUSTOMER-REPORT.rtf\n}\n')
        (layout/'customer-report.rtf').write_bytes(b'rtf-content')
        return layout

    def test_native_report_layout_case_fix_is_idempotent(self):
        layout = self.native_layout()
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(HELPER.normalize_source_files(self.project,103),1)
            self.assertEqual(HELPER.normalize_source_files(self.project,103),0)
        self.assertIn('pageFile: customer-report.rtf', (layout/'report-layouts.apx').read_text())
        self.assertEqual((layout/'customer-report.rtf').read_bytes(),b'rtf-content')

    def test_missing_report_layout_fails(self):
        layout = self.native_layout()
        (layout/'customer-report.rtf').unlink()
        with self.assertRaisesRegex(ValueError,'Missing or ambiguous'):
            HELPER.normalize_source_files(self.project,103)

    def test_wrong_native_source_app_rejected(self):
        self.native_layout()
        with self.assertRaisesRegex(ValueError,'missing or ambiguous'):
            HELPER.normalize_source_files(self.project,104)

    def test_preserves_schema_mapping_and_restores_known_package_qualifier(self):
        self.assertEqual(self.normalize(),1)
        text=self.sql.read_text()
        self.assertIn('${demo}.eba_cust_email',text)
        self.assertIn('eba_cust_fw.get_preference_value()',text)
        self.assertNotIn('${eba_cust_fw}',text)
        self.assertEqual(self.normalize(),0)

    def test_unknown_placeholder_aborts_without_any_partial_normalization(self):
        unknown=self.stage/'z_unknown.sql'; unknown.write_text('begin ${unknown_package}.run; end; /')
        with self.assertRaisesRegex(ValueError,'Unknown simple staged SQL placeholder'):
            self.normalize()
        self.assertEqual(self.sql.read_text(),self.original)
        self.assertEqual(unknown.read_text(),'begin ${unknown_package}.run; end; /')
        self.assertFalse(list(self.project.rglob('.normalize-*')))

    def test_released_migrations_and_source_are_never_modified(self):
        released=self.project/'dist/releases/1.0/package.sql';released.parent.mkdir(parents=True)
        content='begin ${unknown_package}.run; ${eba_cust_fw}.run; end; /'
        released.write_text(content)
        source=self.project/'src/database/demo/package_specs/eba_cust_fw.sql'; before=source.read_bytes()
        self.normalize()
        self.assertEqual(released.read_text(),content)
        self.assertEqual(source.read_bytes(),before)

    def test_symlinked_staged_file_is_rejected_without_changes(self):
        outside=Path(self.tmp.name)/'outside.sql';outside.write_text(self.original)
        (self.stage/'link.sql').symlink_to(outside)
        with self.assertRaisesRegex(ValueError,'Symlinked'):
            self.normalize()
        self.assertEqual(self.sql.read_text(),self.original)
        self.assertEqual(outside.read_text(),self.original)

    def test_symlinked_stage_directory_cannot_escape_project(self):
        other=Path(self.tmp.name)/'outside';other.mkdir()
        (self.project/'dist/releases/next/escape').symlink_to(other,target_is_directory=True)
        with self.assertRaisesRegex(ValueError,'Symlinked'):
            self.normalize()
        self.assertEqual(self.sql.read_text(),self.original)

    def test_source_package_declaration_must_match_name(self):
        path=self.project/'src/database/demo/package_specs/eba_cust_fw.sql'
        path.write_text('create or replace package demo.other_package as end; /')
        with self.assertRaisesRegex(ValueError,'filename/declaration mismatch'):
            self.normalize()
        self.assertEqual(self.sql.read_text(),self.original)

    def test_dotted_liquibase_properties_remain_unchanged(self):
        self.sql.write_text(self.original+'-- ${apex.103.workspace}\n')
        self.normalize()
        self.assertIn('${apex.103.workspace}',self.sql.read_text())

    def test_case_insensitive_schema_and_package_tokens(self):
        self.sql.write_text(self.original.replace('${demo}','${DEMO}').replace('${eba_cust_fw}','${EBA_CUST_FW}'))
        self.normalize()
        self.assertIn('${DEMO}.eba_cust_email',self.sql.read_text())
        self.assertIn('eba_cust_fw.get_preference_value()',self.sql.read_text())


if __name__ == '__main__':unittest.main()
