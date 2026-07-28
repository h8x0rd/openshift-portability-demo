#!/usr/bin/env bash
set -euo pipefail

repo="${1:?Usage: $0 <git-repository-url>}"

python3 - "$repo" <<'PY'
from pathlib import Path
import sys

repo = sys.argv[1]
placeholder = "https://github.com/YOUR_ORG/openshift-portability-demo.git"
files = [
    Path("hub/40-application-set.yaml"),
    Path("bootstrap/portability-demo-hub.yaml"),
]

for path in files:
    text = path.read_text()
    path.write_text(text.replace(placeholder, repo))
    print(f"Configured repository URL in {path}")
PY
