#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
for f in scripts/*.sh scripts/lib/*.sh; do bash -n "$f"; done
python3 - <<'PY2'
from pathlib import Path
import yaml
for p in list(Path('hub').rglob('*.yaml'))+list(Path('bootstrap').rglob('*.yaml'))+list(Path('prerequisites').rglob('*.yaml')):
 list(yaml.safe_load_all(p.read_text()))
print('YAML parsed successfully')
PY2
if grep -RInE 'cluster1-sno|cluster2-sno|eu-west-[0-9]|h8x0rd|github.com/.+openshift-portability-demo' README.md CHANGELOG.md bootstrap charts docs hub prerequisites scripts --exclude=validate.sh; then echo 'Environment-specific values remain' >&2; exit 1; fi
echo 'Validation passed'
