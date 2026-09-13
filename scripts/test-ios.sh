#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/xcode-env.sh
if [[ -z "${SIMULATOR_UDID:-}" ]]; then
  echo "Set SIMULATOR_UDID to a dedicated available iPhone simulator ID." >&2
  exit 1
fi
scripts/generate-project.sh
mkdir -p .work/test-results
result_path=".work/test-results/$(date +%Y%m%d-%H%M%S).xcresult"
xcodebuild -project ScrollCapture.xcodeproj -scheme ScrollCapture \
  -configuration Debug -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath .work/DerivedData CODE_SIGNING_ALLOWED=NO build-for-testing "$@"
# This suite checks the authorized save path. Denied-permission/device gates are separate evidence.
xcrun simctl install "$SIMULATOR_UDID" .work/DerivedData/Build/Products/Debug-iphonesimulator/ScrollCapture.app
xcrun simctl privacy "$SIMULATOR_UDID" grant photos-add dev.lzbaclz.longscreenshot
xcodebuild -project ScrollCapture.xcodeproj -scheme ScrollCapture \
  -configuration Debug -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath .work/DerivedData -resultBundlePath "$result_path" \
  CODE_SIGNING_ALLOWED=NO test-without-building "$@"
