#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/xcode-env.sh
swift test
scripts/generate-project.sh
mkdir -p .work/implementation
xcodebuild -project ScrollCapture.xcodeproj -scheme ScrollCapture \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .work/DerivedData CODE_SIGNING_ALLOWED=NO build
git diff --check
