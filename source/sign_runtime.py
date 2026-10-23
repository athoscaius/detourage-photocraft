#!/usr/bin/env python3
"""Ad-hoc sign bundled Mach-O code after copying to a private staging directory."""
from pathlib import Path
import subprocess
import sys
seen = set()
for path in sorted(Path(sys.argv[1]).rglob('*')):
    if not path.is_file() or path.is_symlink():
        continue
    resolved = path.resolve()
    if resolved in seen:
        continue
    seen.add(resolved)
    with path.open('rb') as stream:
        magic = stream.read(4)
    if magic in (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        subprocess.run(['/usr/bin/codesign','--force','--sign','-','--timestamp=none',str(path)], check=True, capture_output=True)
