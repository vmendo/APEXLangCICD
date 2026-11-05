"""Exercise SQLcl stage supervision without a database or a SQLcl installation."""
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest
import runpy
import io
from unittest.mock import patch, MagicMock


RUNNER = Path(__file__).resolve().parents[1] / 'run' / 'aux' / 'sqlcl_runner.py'
COMPLETE = 'APEXCICD_STAGE_COMPLETE'


class SQLclRunnerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.binary = self.root / 'fake-sqlcl'
        self.log = self.root / 'stage.log'

    def run_fake(self, body, timeout=5):
        self.binary.write_text(f'#!{sys.executable}\n' + body)
        self.binary.chmod(0o700)
        return subprocess.run(
            [sys.executable, str(RUNNER), str(self.binary), 'TEST_DEV',
             str(self.log), str(timeout)],
            input='select 1 from dual;\n', text=True, capture_output=True,
            timeout=15,
        )

    def test_success_passes_script_and_keeps_private_plain_text_log(self):
        result = self.run_fake(
            "import sys\n"
            "assert sys.argv[1:] == ['-S', '-name', 'TEST_DEV']\n"
            "script = sys.stdin.read()\n"
            "assert 'whenever sqlerror exit failure rollback' in script\n"
            "assert 'select 1 from dual;' in script\n"
            f"assert 'prompt {COMPLETE}' in script\n"
            "assert script.endswith('exit success\\n')\n"
            "print('\\x1b[32mDone\\x1b[0m')\n"
            f"print('{COMPLETE}')\n"
        )
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(self.log.read_text(), f'Done\n{COMPLETE}\n')
        self.assertEqual(stat.S_IMODE(self.log.stat().st_mode), 0o600)
        self.assertIn(str(self.log), result.stdout)

    def test_zero_exit_code_does_not_hide_sqlcl_errors(self):
        outputs = (
            'ORA-00942: table or view does not exist',
            'SP2-0734: unknown command beginning',
            'PLS-00103: encountered a symbol',
            'TNS-12514: listener does not know service',
            'Error starting at line : 1',
            'Connection failed',
            'Unknown Command',
            'Invalid command',
            'Errors: 1',
            '  Errors: 12',
        )
        for index, output in enumerate(outputs):
            with self.subTest(output=output):
                self.log = self.root / f'error-{index}.log'
                result = self.run_fake(f'print({output!r})\nprint({COMPLETE!r})\n')
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn(output, self.log.read_text())

    def test_zero_errors_summary_is_accepted(self):
        result = self.run_fake(f"print('Errors: 0')\nprint({COMPLETE!r})\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_missing_completion_sentinel_is_failure(self):
        result = self.run_fake("print('SQLcl exited without completing the stage')\n")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertNotIn(COMPLETE, self.log.read_text())

    def test_nonzero_sqlcl_exit_code_is_preserved(self):
        result = self.run_fake(f'import sys\nprint({COMPLETE!r})\nsys.exit(7)\n')
        self.assertEqual(result.returncode, 7, result.stdout + result.stderr)

    def test_deployment_wait_path_preserves_input_and_completion(self):
        self.log = self.root / 'deploy-1.0-test.log'
        result = self.run_fake("import sys\nscript=sys.stdin.read()\nassert 'select 1 from dual;' in script\nprint('APEXCICD_STAGE_COMPLETE')\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(COMPLETE, self.log.read_text())

    def test_heartbeat_does_not_resend_script_after_poll_timeout(self):
        log = self.root / 'deploy-heartbeat.log'
        process = MagicMock(returncode=0)
        process.communicate.side_effect = [subprocess.TimeoutExpired(['fake'],15), (COMPLETE+'\n',None)]
        with patch('sys.argv',[str(RUNNER),'fake','TEST_DEV',str(log),'180']), \
             patch('sys.stdin',io.StringIO('select 1 from dual;')), \
             patch('sys.stdout',io.StringIO()) as output, \
             patch('subprocess.Popen',return_value=process), \
             patch('time.monotonic',side_effect=[0,0,15,15,15]):
            runpy.run_path(str(RUNNER),run_name='__main__')
        self.assertIn('15s elapsed',output.getvalue())
        self.assertIn('select 1 from dual;',process.communicate.call_args_list[0].args[0])
        self.assertIsNone(process.communicate.call_args_list[1].args[0])
        self.assertIn(COMPLETE,log.read_text())

    def test_deployment_timeout_remains_bounded(self):
        self.log = self.root / 'deploy-1.0-test.log'
        result = self.run_fake("import time\nprint('Migration started',flush=True)\ntime.sleep(60)\n",timeout=1)
        self.assertEqual(result.returncode, 124, result.stderr)
        self.assertIn('Migration started', self.log.read_text())
        self.assertIn('timed out', self.log.read_text())

    def test_timeout_kills_child_process_group(self):
        marker = self.root / 'child.pid'
        child_code = (
            'import os, signal, time\n'
            'from pathlib import Path\n'
            'signal.signal(signal.SIGTERM, signal.SIG_IGN)\n'
            f'Path({str(marker)!r}).write_text(str(os.getpid()))\n'
            'time.sleep(60)\n'
        )
        body = (
            'import signal, subprocess, sys, time\n'
            'signal.signal(signal.SIGTERM, signal.SIG_IGN)\n'
            f'subprocess.Popen([sys.executable, "-c", {child_code!r}])\n'
            'print("Child started", flush=True)\n'
            'time.sleep(60)\n'
        )
        result = self.run_fake(body, timeout=1)
        self.assertTrue(marker.is_file(), result.stdout + result.stderr)
        pid = int(marker.read_text())
        try:
            deadline = time.monotonic() + 2
            while self.process_is_running(pid) and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertFalse(self.process_is_running(pid), f'Timed-out child {pid} is still running')
            self.assertEqual(result.returncode, 124, result.stdout + result.stderr)
            self.assertIn('SQLcl stage timed out', self.log.read_text())
        finally:
            if self.process_is_running(pid):
                os.kill(pid, signal.SIGKILL)

    @staticmethod
    def process_is_running(pid):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return False
        # Linux reapers can leave a killed orphan visible as a zombie briefly.
        proc_stat = Path(f'/proc/{pid}/stat')
        try:
            if proc_stat.is_file() and proc_stat.read_text().rsplit(')', 1)[1].split()[0] == 'Z':
                return False
        except FileNotFoundError:
            return False
        return True


if __name__ == '__main__':
    unittest.main()
