#!/usr/bin/env bash
set -euo pipefail
interval="${1:-3}"; while true; do clear; "$(dirname "$0")/status.sh" || true; sleep "$interval"; done
