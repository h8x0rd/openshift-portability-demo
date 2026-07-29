#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/configure-repository.sh [repository-url] [target-revision]
  ./scripts/configure-repository.sh --preserve-ssh [repository-url] [target-revision]

By default, GitHub-style SSH remotes such as:
  git@github.com:owner/repository.git
are converted to the equivalent HTTPS URL for Argo CD:
  https://github.com/owner/repository.git

This does not change the local Git remote. It only configures the manifests.
Use --preserve-ssh only after configuring matching SSH repository credentials
inside Argo CD.
USAGE
}

preserve_ssh=false
if [[ "${1:-}" == "--preserve-ssh" ]]; then
  preserve_ssh=true
  shift
fi
[[ "${1:-}" != "-h" && "${1:-}" != "--help" ]] || { usage; exit 0; }

local_repo="${1:-$(git remote get-url origin 2>/dev/null || true)}"
revision="${2:-$(git branch --show-current 2>/dev/null || true)}"
[[ -n "$local_repo" ]] || { usage >&2; exit 1; }
[[ -n "$revision" ]] || revision=main

argocd_repo="$local_repo"
if ! $preserve_ssh; then
  case "$argocd_repo" in
    git@github.com:*.git)
      path="${argocd_repo#git@github.com:}"
      argocd_repo="https://github.com/${path}"
      ;;
    ssh://git@github.com/*.git)
      path="${argocd_repo#ssh://git@github.com/}"
      argocd_repo="https://github.com/${path}"
      ;;
    git@gitlab.com:*.git)
      path="${argocd_repo#git@gitlab.com:}"
      argocd_repo="https://gitlab.com/${path}"
      ;;
    ssh://git@gitlab.com/*.git)
      path="${argocd_repo#ssh://git@gitlab.com/}"
      argocd_repo="https://gitlab.com/${path}"
      ;;
  esac
fi

python3 - "$argocd_repo" "$revision" <<'PY'
from pathlib import Path
import re
import sys

repo, revision = sys.argv[1:]
files = [
    Path("hub/40-application-set.yaml"),
    Path("bootstrap/portability-demo-hub.yaml"),
    Path("charts/portability-demo/values.yaml"),
]
for path in files:
    text = path.read_text()
    text = text.replace("GIT_REPOSITORY_URL", repo)
    text = text.replace("GIT_TARGET_REVISION", revision)
    text = re.sub(r"(?m)^(\s*repoURL:\s*).*$", lambda m: m.group(1) + repo, text)
    text = re.sub(r"(?m)^(\s*gitRepository:\s*).*$", lambda m: m.group(1) + repo, text)
    text = re.sub(r"(?m)^(\s*targetRevision:\s*).*$", lambda m: m.group(1) + revision, text)
    path.write_text(text)
    print(f"Configured {path}")
PY

printf '\nLocal Git remote: %s\n' "$local_repo"
printf 'Argo CD source:  %s\n' "$argocd_repo"
printf 'Target revision: %s\n' "$revision"

if [[ "$local_repo" != "$argocd_repo" ]]; then
  cat <<'NOTE'

The local SSH remote was intentionally converted to HTTPS for Argo CD.
Your local `origin` remains unchanged and you can continue pushing over SSH.
For a public repository, no Argo CD repository credential is required.
NOTE
elif [[ "$argocd_repo" == git@* || "$argocd_repo" == ssh://* ]]; then
  cat <<'NOTE'

SSH was preserved. Before applying the root Application, configure this repository
and its private key in the OpenShift GitOps Argo CD instance. A workstation SSH
agent is not available inside the Argo CD repo-server pod.
NOTE
fi

echo
echo "Commit and push these generated settings before applying the root Application."
