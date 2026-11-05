"""Exercise manual-merge waiting and automatic publication with offline boundaries."""
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class ManualReleaseGateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name).resolve()
        self.run = self.home/'run'; aux=self.run/'aux'; aux.mkdir(parents=True)
        self.project = self.home/'project'; self.project.mkdir()
        config=self.project/'.dbtools'; config.mkdir()
        (config/'project.config.json').write_text(json.dumps({'schemas':['DEMO'],'apex':{'apexlang':True}}))
        specs=self.project/'src/database/demo/package_specs'; specs.mkdir(parents=True)
        (specs/'eba_cust_fw.sql').write_text('create or replace package demo.eba_cust_fw as end; /')
        native=self.project/'src/database/demo/apex_apps/customers'
        (native/'deployments').mkdir(parents=True)
        (native/'deployments/default.json').write_text(json.dumps({'app':{'id':103}}))
        (native/'application.apx').write_text('application CUSTOMERS ()')
        self.bin=self.home/'bin';self.bin.mkdir()
        self.actions=self.home/'actions.jsonl';self.sql=self.home/'sql.log'
        shutil.copy2(ROOT/'run/create_release.sh',self.run/'create_release.sh')
        for name in ('publish_release.sh','normalize_staged_sql.py'):
            shutil.copy2(ROOT/'run/aux'/name,aux/name)
        (aux/'common.sh').write_text('''DEMO_HOME="$TEST_HOME"
PROJECT_DIR="$TEST_HOME/project"
PROJECT_NAME=Customers
PROJECT_BRANCH=main
GITHUB_REPO=owner/demo
RELEASE_TAG_PREFIX=v
DB_CONNECT_DEV=FAKE_DEV
APEX_APP_ID=103
die() { echo "ERROR: $*" >&2; exit 1; }
require_tools() { :; }
validate_name() { :; }
validate_version() { :; }
load_project() { :; }
run_sql() {
  local sql
  sql="$(cat)"
  printf '%s\\n' "$sql" >> "$TEST_SQL_LOG"
  case "$sql" in
    *"project export"*) mkdir -p "$PROJECT_DIR/src" ;;
    *"project stage add-custom"*)
      local custom_name="${sql##* }"
      mkdir -p "$PROJECT_DIR/dist/releases/next/changes/_custom"
      printf '%s\\n' '-- liquibase formatted sql' '-- changeset DEMO:custom' > "$PROJECT_DIR/dist/releases/next/changes/_custom/$custom_name" ;;
    *"project stage"*) mkdir -p "$PROJECT_DIR/dist/releases/next" ;;
    *"project release"*) mkdir -p "$PROJECT_DIR/dist/releases/${sql##* }" ;;
    *"project verify"*) : ;;
    *"project gen-artifact"*)
      local version="${sql#* -version }"
      version="${version%% *}"
      mkdir -p "$PROJECT_DIR/artifact"
      printf 'offline artifact' > "$PROJECT_DIR/artifact/Customers-$version.zip" ;;
    *) echo 'Unexpected SQLcl invocation' >&2; return 99 ;;
  esac
}
''')
        (aux/'check_environment.sh').write_text('#!/usr/bin/env bash\nprintf checked > "$TEST_HOME/environment-checked"\n')
        (aux/'check_environment.sh').chmod(0o755)
        self.fake('git', '''
if args[:2] == ['show-ref', '--verify'] or args[:3] == ['diff','--cached','--quiet']:
    raise SystemExit(1)
''')
        self.fake('gh', '''
from pathlib import Path
if args[:2] == ['release','view']:
    raise SystemExit(1)
if args[:2] == ['pr','create']:
    print('https://github.com/owner/demo/pull/1')
elif args[:2] == ['pr','view']:
    counter=Path(os.environ['TEST_HOME'])/'poll-count'
    count=int(counter.read_text()) if counter.exists() else 0
    counter.write_text(str(count+1))
    sequence=json.loads(os.environ['TEST_PR_SEQUENCE'])
    value=sequence[min(count,len(sequence)-1)]
    if value=='HTTP_FAILURE':
        print('gh: API unavailable (HTTP 503)',file=sys.stderr);raise SystemExit(1)
    if isinstance(value,str):
        value=dict(state=value,baseRefName='main',headRefName=os.environ['TEST_HEAD'],
                   mergeCommit={'oid':'fake-merged-sha'} if value=='MERGED' else None)
    print(json.dumps(value))
elif args[:2] == ['release','create']:
    print('https://github.com/owner/demo/releases/tag/v1.0')
else:
    raise SystemExit('Unexpected GitHub operation')
''')
        self.fake('sleep', '''
if os.environ.get('TEST_BLOCK_SLEEP')=='1':
    from pathlib import Path
    import time
    (Path(os.environ['TEST_HOME'])/'sleep-ready').write_text('ready')
    time.sleep(60)
''')
        self.env=dict(os.environ,TEST_HOME=str(self.home),TEST_SQL_LOG=str(self.sql),
                      TEST_ACTION_LOG=str(self.actions),PATH=str(self.bin)+os.pathsep+os.environ['PATH'],
                      TEST_PR_SEQUENCE=json.dumps(['OPEN','MERGED']),
                      TEST_HEAD='baseline-1.0',PR_POLL_SECONDS='1')
        self.proposal_state()

    def fake(self,name,body):
        path=self.bin/name
        path.write_text('#!'+sys.executable+'\nimport json,os,sys\nargs=sys.argv[1:]\n'
            +"with open(os.environ['TEST_ACTION_LOG'],'a') as f: f.write(json.dumps(["+repr(name)+",args])+'\\n')\n"+body)
        path.chmod(0o755)

    def proposal_state(self):
        folder=self.home/'.state/releases';folder.mkdir(parents=True)
        values=dict(RELEASE_PROJECT='Customers',RELEASE_REPO='owner/demo',RELEASE_DIR=str(self.project),
                    RELEASE_VERSION='1.0',RELEASE_BRANCH='baseline-1.0',
                    RELEASE_BASE='main',RELEASE_TAG='v1.0',RELEASE_PR='https://github.com/owner/demo/pull/1')
        (folder/'1.0.env').write_text(''.join(f"{k}='{v}'\n" for k,v in values.items()))

    def calls(self):
        return [json.loads(line) for line in self.actions.read_text().splitlines()] if self.actions.exists() else []

    def github_calls(self):return [args for tool,args in self.calls() if tool=='gh']

    def run_stage(self,*args,sequence=None,head=None):
        env=dict(self.env)
        if sequence is not None:env['TEST_PR_SEQUENCE']=json.dumps(sequence)
        if head is not None:env['TEST_HEAD']=head
        return subprocess.run(['bash',str(self.run/'create_release.sh'),*args],env=env,
                              text=True,capture_output=True,timeout=15)

    def publish(self,state='OPEN',base='main',head='baseline-1.0'):
        value=dict(state=state,baseRefName=base,headRefName=head,
                   mergeCommit={'oid':'fake-merged-sha'} if state=='MERGED' else None)
        env=dict(self.env,TEST_PR_SEQUENCE=json.dumps([value]))
        return subprocess.run(['bash',str(self.run/'aux/publish_release.sh'),'1.0'],env=env,
                              text=True,capture_output=True,timeout=10)

    def assert_no_publication(self):
        text=self.sql.read_text() if self.sql.exists() else ''
        self.assertNotIn('project gen-artifact',text)
        self.assertFalse(any(a[:2] in (['release','create'],['release','upload']) for a in self.github_calls()))

    def assert_no_automatic_approval(self):
        self.assertFalse(any(a[:2] in (['pr','merge'],['pr','review']) for a in self.github_calls()))

    def assert_nonwait_stops_before_git_changes(self):
        self.assert_no_publication()
        self.assertFalse(self.sql.exists())
        self.assertFalse(any(tool=='git' and args[0] in ('fetch','checkout','push') for tool,args in self.calls()))

    def test_open_pr_nonwait_blocks_before_generation_upload_and_git_changes(self):
        result=self.publish('OPEN');self.assertNotEqual(result.returncode,0)
        self.assertIn('must be merged',result.stderr);self.assert_nonwait_stops_before_git_changes()

    def test_closed_pr_nonwait_blocks_before_generation_upload(self):
        result=self.publish('CLOSED');self.assertNotEqual(result.returncode,0)
        self.assertIn('closed without merging',result.stderr);self.assert_nonwait_stops_before_git_changes()

    def test_wrong_base_pr_never_approves_publication(self):
        result=self.publish('MERGED',base='other-project');self.assertNotEqual(result.returncode,0)
        self.assert_nonwait_stops_before_git_changes()

    def test_wrong_head_pr_never_approves_publication(self):
        result=self.publish('MERGED',head='unrelated');self.assertNotEqual(result.returncode,0)
        self.assert_nonwait_stops_before_git_changes()

    def test_create_waits_open_then_publishes_once_after_manual_merge(self):
        result=self.run_stage('baseline','1.0')
        self.assertEqual(result.returncode,0,result.stderr)
        calls=self.github_calls()
        self.assertEqual(sum(a[:2]==['pr','create'] for a in calls),1)
        self.assertEqual(sum(a[:2]==['pr','view'] for a in calls),2)
        self.assertEqual(sum(a[:2]==['release','create'] for a in calls),1)
        self.assertEqual(self.sql.read_text().count('project gen-artifact'),1)
        self.assertEqual(sum(tool=='sleep' for tool,_ in self.calls()),1)
        self.assert_no_automatic_approval()
        self.assertIn('Review and merge the PR manually',result.stdout)
        self.assertIn('Next: ./run/deploy_project.sh PRO 1.0',result.stdout)
        release=next(a for a in calls if a[:2]==['release','create'])
        self.assertIn('fake-merged-sha',release)

    def test_open_then_closed_cancels_without_artifact(self):
        result=self.run_stage('baseline','1.0',sequence=['OPEN','CLOSED'])
        self.assertNotEqual(result.returncode,0)
        self.assertIn('closed without merging',result.stderr)
        self.assert_no_publication();self.assert_no_automatic_approval()

    def test_identity_mismatch_during_wait_fails_closed(self):
        wrong=dict(state='MERGED',baseRefName='other',headRefName=self.env['TEST_HEAD'],mergeCommit={'oid':'fake-merged-sha'})
        result=self.run_stage('baseline','1.0',sequence=['OPEN',wrong])
        self.assertNotEqual(result.returncode,0)
        self.assertIn('PR identity differs',result.stderr)
        self.assert_no_publication()

    def test_http_failure_during_wait_fails_closed(self):
        result=self.run_stage('baseline','1.0',sequence=['OPEN','HTTP_FAILURE'])
        self.assertNotEqual(result.returncode,0)
        self.assertIn('HTTP 503',result.stderr)
        self.assert_no_publication();self.assert_no_automatic_approval()

    def test_resume_skips_export_and_pr_creation_then_publishes(self):
        (self.project/'dist/releases/1.0').mkdir(parents=True)
        result=self.run_stage('--resume','1.0')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertNotIn('project export',self.sql.read_text())
        self.assertNotIn('project stage',self.sql.read_text())
        self.assertFalse((self.home/'environment-checked').exists())
        self.assertFalse(any(a[:2]==['pr','create'] for a in self.github_calls()))
        self.assertEqual(sum(a[:2]==['release','create'] for a in self.github_calls()),1)
        self.assert_no_automatic_approval()

    def test_custom_repair_waits_for_merge_and_publishes_without_mutating_input(self):
        repair=self.home/'repair_email.sql'
        body='create or replace package body eba_cust_email as\n x varchar2(20) := ${eba_cust_fw}.get_preference_value();\nend;\n/\n'
        repair.write_text(body)
        result=self.run_stage('repair','1.0.1','--custom',str(repair),head='repair-1.0.1')
        self.assertEqual(result.returncode,0,result.stderr)
        staged=self.project/'dist/releases/next/changes/_custom/repair_email.sql'
        content=staged.read_text()
        self.assertTrue(content.startswith('-- liquibase formatted sql\n-- changeset DEMO:custom\n'))
        self.assertIn('eba_cust_fw.get_preference_value()',content)
        self.assertEqual(repair.read_text(),body)
        self.assertEqual(sum(a[:2]==['release','create'] for a in self.github_calls()),1)
        self.assert_no_automatic_approval()

    def test_unknown_custom_placeholder_stops_before_pr_or_push(self):
        repair=self.home/'repair_unknown.sql';repair.write_text('begin ${unknown_package}.run; end; /')
        result=self.run_stage('repair','1.0.1','--custom',str(repair),head='repair-1.0.1')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('Unknown simple staged SQL placeholder',result.stderr)
        self.assertFalse(any(a[:2]==['pr','create'] for a in self.github_calls()))
        self.assertFalse(any(tool=='git' and a[0]=='push' for tool,a in self.calls()))
        self.assert_no_publication()

    @unittest.skipUnless(hasattr(os,'killpg'),'Requires POSIX process-group signals')
    def test_ctrl_c_during_wait_cancels_without_publication(self):
        (self.project/'dist/releases/1.0').mkdir(parents=True)
        env=dict(self.env,TEST_PR_SEQUENCE=json.dumps(['OPEN']),TEST_BLOCK_SLEEP='1')
        process=subprocess.Popen(['bash',str(self.run/'create_release.sh'),'--resume','1.0'],env=env,
                                 text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
        try:
            deadline=time.monotonic()+5
            while not (self.home/'sleep-ready').exists() and process.poll() is None and time.monotonic()<deadline:
                time.sleep(0.01)
            self.assertTrue((self.home/'sleep-ready').exists(),'Wait never reached the fake sleep boundary')
            os.killpg(process.pid,signal.SIGINT)
            stdout,stderr=process.communicate(timeout=5)
            self.assertNotEqual(process.returncode,0)
            self.assertIn('cancelled',stderr)
            self.assert_no_publication();self.assert_no_automatic_approval()
        finally:
            if process.poll() is None:
                os.killpg(process.pid,signal.SIGTERM)
                process.communicate(timeout=5)


if __name__=='__main__':unittest.main()
