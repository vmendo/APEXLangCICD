"""Verify full cleanup removes old logs but retains the current cleanup evidence."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class CleanupLogResetTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name) / 'demo'
        (self.home/'run/clean/aux').mkdir(parents=True)
        (self.home/'run/aux').mkdir()
        (self.home/'.state').mkdir()
        shutil.copy(ROOT/'run/clean_demo.sh', self.home/'run/clean_demo.sh')
        shutil.copy(ROOT/'run/clean/aux/reset_logs.py', self.home/'run/clean/aux/reset_logs.py')
        (self.home/'run/aux/common.sh').write_text('export DEMO_HOME="$TEST_HOME"\ndie() { echo "$*" >&2; exit 1; }\n')
        for stage in ('cleanup_dev','cleanup_pro','cleanup_remote','delete_project'):
            (self.home/f'run/clean/{stage}.sh').write_text(
                '[[ ! -e "$DEMO_HOME/logs/old.log" ]] || exit 21\n'
                f'echo "{stage}" > "$DEMO_HOME/logs/{stage}.log"\n')

    def run_cleanup(self, *args):
        return subprocess.run(['/bin/bash',str(self.home/'run/clean_demo.sh'),*args],
                              env=dict(os.environ,TEST_HOME=str(self.home)),capture_output=True,text=True,timeout=10)

    def test_previous_cycle_removed_before_stages_current_logs_retained(self):
        (self.home/'logs/remote-cleanup').mkdir(parents=True)
        (self.home/'logs/old.log').write_text('previous deployment')
        (self.home/'logs/remote-cleanup/old.json').write_text('{}')
        (self.home/'logs/.hidden').write_text('previous diagnostic')
        (self.home/'.state/project.env').touch()
        result = self.run_cleanup('--yes','--skip-page','--skip-app')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual({p.name for p in (self.home/'logs').iterdir()},
                         {'cleanup_dev.log','cleanup_pro.log','cleanup_remote.log','delete_project.log'})

    def test_incomplete_attempt_keeps_diagnostics_and_runs_no_stages(self):
        (self.home/'logs').mkdir()
        (self.home/'logs/old.log').write_text('needed to inspect failure')
        (self.home/'.state/deployment-attempt.json').write_text('{}')
        result = self.run_cleanup('--skip-page','--skip-app')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual((self.home/'logs/old.log').read_text(),'needed to inspect failure')
        self.assertEqual(len(list((self.home/'logs').iterdir())),1)

    def test_logs_root_symlink_does_not_delete_external_files(self):
        outside = self.home.parent/'external'
        outside.mkdir()
        (outside/'keep.log').write_text('keep')
        (self.home/'logs').symlink_to(outside,target_is_directory=True)
        result = self.run_cleanup('--skip-page','--skip-app')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('symlinked',result.stderr)
        self.assertEqual((outside/'keep.log').read_text(),'keep')

    def test_child_symlink_removed_without_following_it(self):
        outside = self.home.parent/'external'
        outside.mkdir()
        (outside/'keep.log').write_text('keep')
        (self.home/'logs').mkdir()
        (self.home/'logs/linked').symlink_to(outside,target_is_directory=True)
        result = self.run_cleanup('--skip-page','--skip-app')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertFalse((self.home/'logs/linked').exists())
        self.assertEqual((outside/'keep.log').read_text(),'keep')
