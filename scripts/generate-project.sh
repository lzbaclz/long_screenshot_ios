#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/xcode-env.sh
command -v xcodegen >/dev/null || { echo "Install XcodeGen, then rerun this script." >&2; exit 1; }
xcodegen generate --spec project.yml
