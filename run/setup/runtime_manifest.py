#!/usr/bin/env python3
"""Record the controlled runtime build and per-file SHA256 checksums."""
import hashlib
import json
import subprocess
from pathlib import Path
home = Path(__file__).resolve().parents[2]
runtime = home / 'tools/sqlcl-26.3'
version = subprocess.check_output([str(runtime / 'bin/sql'), '-version'], text=True).strip()
if 'Release 26.3.0.0' not in version:
    raise SystemExit('Controlled runtime must be SQLcl 26.3.0.0.')
files = {str(p.relative_to(runtime)): hashlib.sha256(p.read_bytes()).hexdigest()
         for p in sorted(runtime.rglob('*')) if p.is_file()}
(home / 'config/sqlcl-runtime.json').write_text(json.dumps({'version': version, 'files': files}, indent=2) + '\n')
print(f'Recorded {len(files)} runtime file checksums.')
