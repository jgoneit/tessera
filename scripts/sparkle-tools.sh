#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# SwiftPM authenticates this binary artifact using Sparkle's pinned checksum.
# Never fetch a separate, unpinned copy of the release-signing tools.
python3 - <<'PY'
import json
from pathlib import Path
resolved = json.loads(Path('Package.resolved').read_text())
pin = next((pin for pin in resolved['pins'] if pin['identity'] == 'sparkle'), None)
if pin is None or pin['state']['version'] != '2.10.0':
    raise SystemExit('Resolve the exact Sparkle 2.10.0 dependency before packaging.')
manifest = Path('.build/checkouts/Sparkle/Package.swift')
if not manifest.exists():
    manifest = Path('.build/checkouts/sparkle/Package.swift')
checksum = '17e28312b8e18ab7cdbbe09a6fb28cc55a5479ec6c371dbc07cdecd2a14fd959'
if not manifest.exists() or checksum not in manifest.read_text():
    raise SystemExit('The resolved Sparkle binary checksum does not match the release tools.')
PY
tool_dir="$PWD/.build/artifacts/sparkle/Sparkle/bin"
for tool in generate_keys generate_appcast sign_update; do
    [[ -x "$tool_dir/$tool" ]] || { printf 'Missing Sparkle tool: %s. Run swift package resolve.\n' "$tool" >&2; exit 1; }
done
printf '%s\n' "$tool_dir"
