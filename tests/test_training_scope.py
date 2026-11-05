"""Exercise real project bootstrap/configuration with mocked external boundaries."""
import json
import os
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]


def like_regex(pattern):
    """Evaluate the emitted SQL LIKE pattern's documented escape semantics."""
    result=[];escaped=False
    for char in pattern:
        if escaped:result.append(re.escape(char));escaped=False
        elif char=='\\':escaped=True
        elif char=='%':result.append('.*')
        elif char=='_':result.append('.')
        else:result.append(re.escape(char))
    if escaped:raise ValueError('Dangling SQL LIKE escape')
    return re.compile(''.join(result))


class TrainingScopeTests(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory();self.addCleanup(self.temporary.cleanup)
        self.home=Path(self.temporary.name).resolve()
        run=self.home/'run';aux=run/'aux';aux.mkdir(parents=True)
        shutil.copy2(ROOT/'run/create_project.sh',run/'create_project.sh')
        for name in ('common.sh','setup_env.sh','sqlcl_runner.py'):
            shutil.copy2(ROOT/'run/aux'/name,aux/name)
        config=self.home/'config';config.mkdir()
        shutil.copy2(ROOT/'config/project-readme.md',config/'project-readme.md')
        (aux/'check_environment.sh').write_text('''#!/usr/bin/env bash
python3 - <<'PY'
import json,os
from pathlib import Path
Path(os.environ['TEST_HOME'],'precheck.json').write_text(json.dumps({k:os.environ[k] for k in ['APEX_APP_ID','SCHEMA_NAME','APEX_WORKSPACE_DEV']}))
PY
''');(aux/'check_environment.sh').chmod(0o755)
        self.bin=self.home/'mock-bin';self.bin.mkdir()
        self.actions=self.home/'actions.jsonl'
        self.fake(self.bin/'gh','gh','')
        self.fake(self.bin/'git','git', '''
if args and args[0]=='clone':
    directory=Path(args[-1]);directory.mkdir(parents=True)
    (directory/'README.md').write_text('Remote seed README')
''')
        sql=self.home/'tools/sqlcl-26.3/bin/sql';sql.parent.mkdir(parents=True)
        self.fake(sql,'sqlcl', '''
if args==['-version']:
    print('SQLcl: Release 26.3.0.0 Production Build: fixture');raise SystemExit(0)
body=sys.stdin.read()
line=next(line for line in body.splitlines() if line.startswith('project init '))
parts=shlex.split(line)
def option(name):return parts[parts.index(name)+1]
root=Path(option('-directory'));db=root/'.dbtools';(db/'filters').mkdir(parents=True)
cfg=dict(project=option('-name'),schemas=option('-schemas').split(','),
    sqlcl=dict(version='fixture',connectionName=option('-connection-name')),
    apex=dict(apexlang=False),dml=True,
    export=dict(setTransform=dict(emitSchema=False),apex=dict(exptype=['APPLICATION_SOURCE'],expSupportingObjects='Y',skipExportDate=False)),
    stage=dict(substituteSchemas=False),git=dict(defaultBranch='develop'))
(db/'project.config.json').write_text(json.dumps(cfg))
(db/'filters/ddl.filters').write_text("object_name not like 'BIN$%',\\n")
(root/'.gitignore').write_text('# initial SQLcl ignore\\n')
(root/'README.md').write_text('SQLcl generated README')
print('APEXCICD_STAGE_COMPLETE')
''')
        # Clear host/task configuration so this exercises actual framework defaults.
        self.env=dict(os.environ)
        for key in ('PROJECTS_HOME','PROJECT_NAME','PROJECT_DIR','SQLCL_BIN','DB_CONNECT_DEV',
                    'DB_CONNECT_ADMIN','DB_CONNECT_PRO','SCHEMA_NAME','SCHEMA_NAME_PRO',
                    'APEX_WORKSPACE_DEV','APEX_WORKSPACE_PRO','APEX_APP_ID','APEX_APP_ID_PRO',
                    'APEX_APP_ID_PRO_PREFERRED','GITHUB_REPO','GITHUB_URL','PROJECT_BRANCH',
                    'RELEASE_TAG_PREFIX','SQLCL_TIMEOUT'):
            self.env.pop(key,None)
        self.env.update(TEST_HOME=str(self.home),TEST_ACTION_LOG=str(self.actions),
                        GITHUB_REPO='example/training-hub-delivery',
                        PATH=str(self.bin)+os.pathsep+os.environ['PATH'])

    def fake(self,path,label,body):
        path.write_text('#!'+sys.executable+'\nimport json,os,sys,shlex\nfrom pathlib import Path\nargs=sys.argv[1:]\n'
            +"with open(os.environ['TEST_ACTION_LOG'],'a') as stream:stream.write(json.dumps(["+repr(label)+",args])+'\\n')\n"+body)
        path.chmod(0o755)

    def create(self,*args,extra_env=None):
        env=dict(self.env);env.update(extra_env or {})
        result=subprocess.run(['bash',str(self.home/'run/create_project.sh'),*args],env=env,
                              text=True,capture_output=True,timeout=15)
        self.assertEqual(result.returncode,0,result.stderr)
        return result

    def test_missing_delivery_repository_stops_before_external_operations(self):
        env=dict(self.env);env.pop('GITHUB_REPO',None)
        result=subprocess.run(['bash',str(self.home/'run/create_project.sh')],env=env,
                              text=True,capture_output=True,timeout=15)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('Set GITHUB_REPO',result.stderr)
        self.assertFalse(self.actions.exists())
        self.assertFalse((self.home/'precheck.json').exists())
        self.assertFalse((self.home/'.state/project.env').exists())

    def test_default_training_app_and_native_structures_only_flags(self):
        self.create()
        project=self.home/'projects/TrainingHubCICD'
        cfg=json.loads((project/'.dbtools/project.config.json').read_text())
        self.assertEqual(cfg['project'],'TrainingHubCICD')
        self.assertEqual(cfg['schemas'],['DEMO'])
        self.assertTrue(cfg['apex']['apexlang'])
        self.assertFalse(cfg['dml'])
        self.assertEqual(cfg['export']['apex']['exptype'],['APEXLANG'])
        self.assertEqual(cfg['export']['apex']['expSupportingObjects'],'N')
        self.assertTrue(cfg['export']['apex']['skipExportDate'])
        self.assertTrue(cfg['export']['setTransform']['emitSchema'])
        self.assertTrue(cfg['stage']['substituteSchemas'])
        self.assertEqual(cfg['sqlcl']['version'],'26.3.0.0')
        self.assertEqual(json.loads((self.home/'precheck.json').read_text())['APEX_APP_ID'],'110')
        self.assertIn('application_id = 110,',(project/'.dbtools/filters/ddl.filters').read_text())
        state=(self.home/'.state/project.env').read_text()
        self.assertIn('APEX_APP_ID=110\n',state)
        self.assertIn('GITHUB_REPO=example/training-hub-delivery\n',state)
        self.assertIn('GITHUB_URL=https://github.com/example/training-hub-delivery.git\n',state)
        self.assertIn('APEX_APP_ID_PRO_PREFERRED=110\n',state)
        self.assertEqual(stat.S_IMODE((self.home/'.state/project.env').stat().st_mode),0o600)

    def test_project_name_argument_and_configured_root_are_used_consistently(self):
        projects=self.home/'workspace with spaces'
        self.create('LearningDemo2026',extra_env={'PROJECTS_HOME':str(projects),'PROJECT_NAME':'IgnoredDefault'})
        project=projects/'LearningDemo2026'
        cfg=json.loads((project/'.dbtools/project.config.json').read_text())
        marker=json.loads((project/'.apexcicd-project.json').read_text())
        self.assertEqual(cfg['project'],'LearningDemo2026')
        self.assertEqual(marker,dict(project='LearningDemo2026',directory=str(project)))
        self.assertIn('# LearningDemo2026',(project/'README.md').read_text())
        state=(self.home/'.state/project.env').read_text()
        values=dict(line.split('=',1) for line in state.splitlines())
        self.assertEqual(shlex.split(values['PROJECT_DIR']),[str(project)])
        self.assertEqual(shlex.split(values['PROJECT_NAME']),['LearningDemo2026'])
        calls=[json.loads(line) for line in self.actions.read_text().splitlines()]
        self.assertTrue(any(tool=='git' and args[:1]==['clone'] and args[-1]==str(project) for tool,args in calls))
        self.assertFalse((projects/'IgnoredDefault').exists())

    def test_emitted_filter_includes_training_model_and_excludes_near_prefixes(self):
        self.create('ScopeProof')
        text=(self.home/'projects/ScopeProof/.dbtools/filters/ddl.filters').read_text()
        match=re.search(r"object_name like '([^']+)' escape '\\'",text)
        self.assertIsNotNone(match,text)
        self.assertEqual(match[1],r'DEMO\_TRN\_%')
        pattern=like_regex(match[1])
        model=json.loads((ROOT/'scripts/training/model.json').read_text())
        names=[table['name'] for table in model['tables']]+[table['sequence'] for table in model['tables']]
        names += [index['name'] for index in model['indexes']]
        self.assertEqual(len(model['tables']),10)
        for name in names:
            with self.subTest(name=name):self.assertIsNotNone(pattern.fullmatch(name))
        for name in ('DEMOXTRN_EMPLOYEES','DEMO_TRNXEMPLOYEES','DEMOXTRNXEMPLOYEES',
                     'DEMO_TRN','EBA_CUST_CUSTOMERS','OTHER_DEMO_TRN_EMPLOYEES'):
            with self.subTest(excluded=name):self.assertIsNone(pattern.fullmatch(name))
        self.assertIn("object_name not like 'BIN$%',",text)
        self.assertNotIn('EBA_CUST',text)


if __name__=='__main__':unittest.main()
