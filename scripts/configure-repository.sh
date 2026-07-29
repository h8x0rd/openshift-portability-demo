#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
repo="${1:-$(git remote get-url origin 2>/dev/null || true)}"
revision="${2:-$(git branch --show-current 2>/dev/null || true)}"
[[ -n "$repo" ]] || { echo "Usage: $0 [git-repository-url] [target-revision]" >&2; exit 1; }
[[ -n "$revision" ]] || revision=main
python3 - "$repo" "$revision" <<'PY2'
from pathlib import Path
import sys
repo, rev=sys.argv[1:]
files=[Path('hub/40-application-set.yaml'),Path('bootstrap/portability-demo-hub.yaml'),Path('charts/portability-demo/values.yaml')]
for p in files:
 t=p.read_text()
 import re
 t=re.sub(r'(repoURL: ).*',r'\1'+repo,t)
 t=re.sub(r'(gitRepository:\s*).*',r'\1'+repo,t)
 t=t.replace('GIT_REPOSITORY_URL',repo).replace('GIT_TARGET_REVISION',rev)
 t=re.sub(r'(targetRevision: ).*',r'\1'+rev,t)
 t=re.sub(r'(value: )GIT_TARGET_REVISION',r'\1'+rev,t)
 p.write_text(t); print(f'Configured {p}')
PY2
printf '
Repository: %s
Revision:   %s
' "$repo" "$revision"
echo "Commit and push these generated settings before bootstrapping Argo CD."
