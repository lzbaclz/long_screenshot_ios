#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/xcode-env.sh
if [[ -n "${DEVICE_UDID:-}" ]]; then
  device_test_udid="$DEVICE_UDID"
elif [[ -f .work/implementation/device-info.json ]]; then
  device_test_udid="$(python3 - <<'PY'
import json
from pathlib import Path
record = json.loads(Path('.work/implementation/device-info.json').read_text())
print(record['result']['hardwareProperties']['udid'])
PY
)"
else
  echo "Set DEVICE_UDID to the unlocked physical iPhone's UDID." >&2
  exit 1
fi
if [[ ! -f Config/Signing.local.xcconfig ]]; then
  echo "Configure local development signing before running the physical-device test." >&2
  exit 1
fi
scripts/generate-project.sh
mkdir -p .work/device-test-results
device_result_path=".work/device-test-results/$(date +%Y%m%d-%H%M%S).xcresult"
xcodebuild test -project ScrollCapture.xcodeproj -scheme ScrollCaptureDevice \
  -configuration Debug -destination "platform=iOS,id=$device_test_udid" \
  -derivedDataPath .work/DeviceUITestDerivedData -resultBundlePath "$device_result_path" \
  -allowProvisioningUpdates "$@"
