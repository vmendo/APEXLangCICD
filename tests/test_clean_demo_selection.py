"""Check orchestration argument routing without running cleanup stages."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SOURCE=Path(__file__).parents[1]
class OrchestrationTests(unittest.TestCase):
    def exercise(self,args,active=False):
        with tempfile.TemporaryDirectory() as directory:
            home=Path(directory)
            (home/'run/clean/aux').mkdir(parents=True)
            shutil.copy(SOURCE/'run/clean/aux/reset_logs.py',home/'run/clean/aux/reset_logs.py')
            (home/'.state').mkdir()
            if active: (home/'.state/project.env').touch()
            shutil.copy(SOURCE/'run/clean_demo.sh',home/'run/clean_demo.sh')
            (home/'run/aux').mkdir()
            (home/'run/aux/common.sh').write_text('DEMO_HOME="$TEST_HOME"\ndie() { echo "$*" >&2; exit 1; }\n')
            for stage in ('cleanup_dev','cleanup_pro','cleanup_remote','delete_project'):
                (home/f'run/clean/{stage}.sh').write_text(f'printf "%s\\n" "{stage}:$*" >> "$TEST_HOME/calls"\n')
            result=subprocess.run(['bash',str(home/'run/clean_demo.sh'),*args],env=dict(os.environ,TEST_HOME=str(home)),capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            return (home/'calls').read_text().splitlines()
    def test_interactive_with_empty_arrays(self):
        self.assertEqual(self.exercise([]),['cleanup_dev:','cleanup_pro:'])
    def test_route_and_final_stages(self):
        self.assertEqual(self.exercise(['--yes','--page-id','200','--page-id','201','--app-id','111'],True),['cleanup_dev:--yes --page-id 200 --page-id 201','cleanup_pro:--yes --app-id 111','cleanup_remote:--yes','delete_project:--yes'])
    def test_skip_flags(self):
        self.assertEqual(self.exercise(['--skip-page','--skip-app']),['cleanup_dev:--skip-page','cleanup_pro:--skip-app'])
