"""Offline partial-deployment ownership recovery and exact changeset matching."""
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]


class DeploymentResumeTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.home=Path(self.temp.name).resolve();self.project=self.home/'project'
        (self.project/'.dbtools').mkdir(parents=True)
        (self.project/'.dbtools/project.config.json').write_text(json.dumps({'project':'TrainingHub','schemas':['DEMO']}))
        tables=self.project/'src/database/demo/tables';tables.mkdir(parents=True)
        (tables/'demo_trn_employees.sql').write_text('create table demo.demo_trn_employees(id number);')
        self.snapshot=self.home/'.state/deployments/attempt';self.snapshot.mkdir(parents=True)
        self.attempt=self.home/'.state/deployment-attempt.json'
        self.attempt.write_text(json.dumps(dict(project_dir=str(self.project),version='1.0',snapshot_dir=str(self.snapshot))))
        self.before=dict(database='PRODB',service='pro_low',schema='DEMO',workspace='DEMO',app_id=111,
                         application_exists=False,objects=[],changelog=[])
        self.current=dict(self.before,objects=[dict(name='DEMO_TRN_EMPLOYEES',type='TABLE'),
                          dict(name='DEMO_TRN_EMPLOYEES_PK',type='INDEX'),dict(name='DATABASECHANGELOG',type='TABLE')],
                          changelog=[dict(id='1793874437819',author='DEMO',filename='release/demo/tables/demo_trn_employees.sql')])
        self.inventory=self.home/'current.json';self.output=self.home/'resume-summary.json'
        self.artifact=self.home/'TrainingHub-1.0.zip'
        self.sql='''-- liquibase formatted sql
-- changeset DEMO:1793874437819 stripComments:false logicalFilePath:release/demo/tables/demo_trn_employees.sql
create table ${demo}.demo_trn_employees(id number);
'''
        self.xml='''<databaseChangeLog xmlns="http://www.liquibase.org/xml/ns/dbchangelog">
<changeSet id="INSTALL_training-hub" author="SQLCL-Generated" logicalFilePath="releases/apex/training-hub/training-hub.xml"><sql>select 1 from dual;</sql></changeSet>
</databaseChangeLog>'''
        self.write_artifact();self.write_snapshots()

    def write_artifact(self):
        with zipfile.ZipFile(self.artifact,'w') as archive:
            archive.writestr('releases/1.0/changes/table.sql',self.sql)
            archive.writestr('releases/apex/training-hub/training-hub.xml',self.xml)

    def write_snapshots(self):
        (self.snapshot/'before.json').write_text(json.dumps(self.before))
        self.inventory.write_text(json.dumps(self.current))

    def run_helper(self,version='1.0'):
        self.write_snapshots()
        return subprocess.run([sys.executable,str(ROOT/'run/aux/deployment_resume.py'),
            '--project-dir',str(self.project),'--attempt',str(self.attempt),'--inventory',str(self.inventory),
            '--artifact',str(self.artifact),'--output',str(self.output),'--version',version],
            text=True,capture_output=True,timeout=10)

    def test_partial_release_with_generated_index_is_recoverable(self):
        original=self.attempt.read_bytes();result=self.run_helper()
        self.assertEqual(result.returncode,0,result.stderr)
        summary=json.loads(self.output.read_text())
        self.assertTrue(summary['recoverable']);self.assertEqual(summary['snapshot_dir'],str(self.snapshot))
        self.assertEqual(summary['artifact_changesets'],2)
        self.assertEqual(summary['applied_release_changesets'],1)
        self.assertEqual(summary['generated_indexes'],[dict(name='DEMO_TRN_EMPLOYEES_PK',type='INDEX')])
        self.assertEqual(stat.S_IMODE(self.output.stat().st_mode),0o600)
        self.assertEqual(self.attempt.read_bytes(),original)
        self.assertFalse((self.home/'.state/deployment.json').exists())

    def test_attempt_wrong_version_or_project_is_rejected_without_summary(self):
        result=self.run_helper(version='1.1');self.assertNotEqual(result.returncode,0)
        self.assertFalse(self.output.exists())
        attempt=json.loads(self.attempt.read_text());attempt['project_dir']=str(self.home/'other')
        self.attempt.write_text(json.dumps(attempt));result=self.run_helper()
        self.assertNotEqual(result.returncode,0);self.assertFalse(self.output.exists())

    def test_every_target_identity_field_must_match_original_before(self):
        for key in ('database','service','schema','workspace','app_id'):
            with self.subTest(key=key):
                previous=self.current[key];self.current[key]=999 if key=='app_id' else 'OTHER'
                result=self.run_helper();self.assertNotEqual(result.returncode,0)
                self.assertIn('identity mismatch: '+key,result.stderr);self.assertFalse(self.output.exists())
                self.current[key]=previous

    def test_application_may_be_absent_or_created_at_same_recorded_id(self):
        self.current['application_exists']=True
        self.current['changelog'].append(dict(id='INSTALL_training-hub',author='SQLCL-Generated',filename='releases/apex/training-hub/training-hub.xml'))
        result=self.run_helper();self.assertEqual(result.returncode,0,result.stderr)
        self.assertTrue(json.loads(self.output.read_text())['application_exists_current'])

    def test_foreign_changelog_id_author_or_logical_path_is_rejected(self):
        for key in ('id','author','filename'):
            with self.subTest(key=key):
                previous=self.current['changelog'][0][key];self.current['changelog'][0][key]='FOREIGN'
                result=self.run_helper();self.assertNotEqual(result.returncode,0)
                self.assertIn('outside the original inventory and release artifact',result.stderr)
                self.assertFalse(self.output.exists());self.current['changelog'][0][key]=previous

    def test_preexisting_history_and_objects_remain_allowed(self):
        row=dict(id='old',author='Existing',filename='old/release.sql')
        obj=dict(name='EBA_CUST_PREEXISTING',type='TABLE')
        self.before['objects']=[obj];self.current['objects'].append(obj)
        self.before['changelog']=[row];self.current['changelog'].append(row)
        result=self.run_helper();self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(json.loads(self.output.read_text())['original_changesets'],1)

    def test_disappearing_preexisting_history_is_rejected(self):
        self.before['changelog']=[dict(id='old',author='Existing',filename='old/release.sql')]
        result=self.run_helper();self.assertNotEqual(result.returncode,0)
        self.assertIn('migration history disappeared',result.stderr);self.assertFalse(self.output.exists())

    def test_unexpected_demo_table_is_not_adopted(self):
        self.current['objects'].append(dict(name='DEMO_TRN_FOREIGN',type='TABLE'))
        result=self.run_helper();self.assertNotEqual(result.returncode,0)
        self.assertIn('Unexpected demo-scope objects',result.stderr);self.assertFalse(self.output.exists())

    def test_unrelated_and_recycle_bin_objects_are_outside_demo_scope(self):
        self.current['objects'] += [dict(name='BIN$abc/def==',type='TABLE'),dict(name='UNRELATED_TABLE',type='TABLE')]
        result=self.run_helper();self.assertEqual(result.returncode,0,result.stderr)

    def test_sql_multiple_changesets_and_global_logical_path_match_exactly(self):
        self.sql='''-- liquibase formatted sql
-- logicalFilePath: global/custom.sql
-- changeset DEMO:first
select 1 from dual;
-- changeset DEMO:second logicalFilePath:override/custom.sql
select 2 from dual;
'''
        self.write_artifact()
        self.current['changelog']=[dict(id='first',author='DEMO',filename='global/custom.sql'),
                                   dict(id='second',author='DEMO',filename='override/custom.sql')]
        result=self.run_helper();self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(json.loads(self.output.read_text())['applied_release_changesets'],2)

    def test_xml_inherits_root_logical_path_or_physical_member_path(self):
        self.xml='''<databaseChangeLog logicalFilePath="logical/native.xml"><changeSet id="A" author="SQLCL"/></databaseChangeLog>'''
        self.write_artifact();self.current['changelog']=[dict(id='A',author='SQLCL',filename='logical/native.xml')]
        result=self.run_helper();self.assertEqual(result.returncode,0,result.stderr)

    def test_output_does_not_replace_prior_recovery_evidence(self):
        self.output.write_text('prior evidence')
        result=self.run_helper();self.assertNotEqual(result.returncode,0)
        self.assertEqual(self.output.read_text(),'prior evidence')


if __name__=='__main__':unittest.main()
