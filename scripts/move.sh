#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in eu-west-3) exec "$(dirname "$0")/scenario.sh" primary;; eu-west-2) exec "$(dirname "$0")/scenario.sh" secondary;; *) echo "Usage: $0 <eu-west-3|eu-west-2>" >&2; exit 1;; esac
