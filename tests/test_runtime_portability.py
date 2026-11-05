"""Run the real SQLcl wrapper with a minimal PATH containing no ripgrep."""
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class RuntimePortabilityTests(unittest.TestCase):
    def execute(self, version):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            binary = home / 'fake-sqlcl'
            binary.write_text('#!' + sys.executable + '\nimport sys\n'
                              + f'if "-version" in sys.argv: print({version!r})\n'
                              + 'else:\n sys.stdin.read()\n print("APEXCICD_STAGE_COMPLETE")\n')
            binary.chmod(0o700)
            path = home / 'bin'
            path.mkdir()
            for tool in ('python3', 'grep', 'mkdir', 'date'):
                (path / tool).symlink_to(sys.executable if tool == 'python3' else shutil.which(tool))
            commands = '\n'.join([
                'set -euo pipefail',
                'source ' + shlex.quote(str(ROOT / 'run/aux/common.sh')),
                'DEMO_HOME=' + shlex.quote(str(home)),
                # Use the actual runner without copying the rest of the project.
                'mkdir -p "$DEMO_HOME/run/aux"',
                'ln -s ' + shlex.quote(str(ROOT / 'run/aux/sqlcl_runner.py')) + ' "$DEMO_HOME/run/aux/sqlcl_runner.py"',
                'SQLCL_BIN=' + shlex.quote(str(binary)),
                'PATH=' + shlex.quote(str(path)),
                '! command -v rg',
                'run_sql TEST_DEV portability <<< "select 1 from dual;"',
            ])
            result = subprocess.run(['/bin/bash', '-c', commands], env=dict(os.environ),
                                    capture_output=True, text=True, timeout=10)
            logs = list((home / 'logs').glob('*.log')) if (home / 'logs').exists() else []
            return result, len(logs)

    def test_runtime_without_ripgrep(self):
        result, logs = self.execute('SQLcl: Release 26.3.0.0 Production')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('APEXCICD_STAGE_COMPLETE', result.stdout)
        self.assertEqual(logs, 1)

    def test_runtime_still_rejects_other_versions(self):
        for version in ('SQLcl: Release 26.2.0.0 Production', 'SQLcl: Release 26.3.0.01 Production'):
            with self.subTest(version=version):
                result, logs = self.execute(version)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('SQLcl must be exactly 26.3.0.0.', result.stderr)
                self.assertEqual(logs, 0)
