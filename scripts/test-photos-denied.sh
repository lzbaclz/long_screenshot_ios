#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/xcode-env.sh
if [[ -z "${SIMULATOR_UDID:-}" ]]; then
  echo "Set SIMULATOR_UDID to a dedicated simulator; this test resets Longlet's add-photos permission." >&2
  exit 1
fi
permission_device_state="$(xcrun simctl list devices available --json | python3 -c '
import json,sys,os
devices=json.load(sys.stdin)["devices"]
matches=[item for group in devices.values() for item in group if item["udid"]==os.environ["SIMULATOR_UDID"]]
if len(matches)!=1: raise SystemExit("SIMULATOR_UDID must identify an available simulator, never a physical device.")
print(matches[0]["state"])
')"
if [[ "$permission_device_state" != "Booted" ]]; then
  xcrun simctl boot "$SIMULATOR_UDID"
fi
xcrun simctl bootstatus "$SIMULATOR_UDID" -b
scripts/generate-project.sh
permission_derived_data=.work/PermissionUITestDerivedData
permission_result_dir=".work/permission-test-results/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$permission_result_dir"
xcodebuild build-for-testing -project ScrollCapture.xcodeproj -scheme ScrollCapturePermissions \
  -configuration Debug -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath "$permission_derived_data" CODE_SIGNING_ALLOWED=NO
xcrun simctl install "$SIMULATOR_UDID" "$permission_derived_data/Build/Products/Debug-iphonesimulator/ScrollCapture.app"
# Delete only this app's add-only authorization so its next save presents the real OS request.
xcrun simctl privacy "$SIMULATOR_UDID" reset photos-add dev.lzbaclz.longscreenshot
xcodebuild test-without-building -project ScrollCapture.xcodeproj -scheme ScrollCapturePermissions \
  -configuration Debug -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath "$permission_derived_data" -resultBundlePath "$permission_result_dir/tests.xcresult" \
  -only-testing:ScrollCapturePermissionsTests/PhotosPermissionUITests/testDeniedPhotoAddPreservesPreviewAndSystemSharing \
  CODE_SIGNING_ALLOWED=NO
# Independently verify actual simulator TCC persisted denial, rather than trusting an app flag.
permission_tcc_path="$HOME/Library/Developer/CoreSimulator/Devices/$SIMULATOR_UDID/data/Library/TCC/TCC.db"
permission_app_container="$(xcrun simctl get_app_container "$SIMULATOR_UDID" dev.lzbaclz.longscreenshot data)"
python3 - "$permission_tcc_path" "$permission_app_container" "$permission_result_dir/evidence.json" <<'PY'
import json,plistlib,sqlite3,sys
from pathlib import Path
db=sqlite3.connect(f'file:{sys.argv[1]}?mode=ro',uri=True)
rows=db.execute('SELECT service,auth_value FROM access WHERE client=? AND service=?',
                ('dev.lzbaclz.longscreenshot','kTCCServicePhotosAdd')).fetchall()
assert rows == [('kTCCServicePhotosAdd',0)], f'Expected actual TCC denial, got {rows!r}'
preferences=Path(sys.argv[2])/'Library/Preferences/dev.lzbaclz.longscreenshot.plist'
defaults=plistlib.loads(preferences.read_bytes()) if preferences.exists() else {}
exported=defaults.get('successfulCaptureExports.v1',{})
assert not exported, 'Denied saves and cancelled sharing must not consume successful-export quota.'
evidence={'permissionSource':'iOS Simulator TCC database (read-only verification)',
          'photosAddAuthorization':'denied','tccAuthValue':0,
          'successfulExportRecords':len(exported),
          'test':'real system prompt -> Don’t Allow -> error -> preview -> share -> cancel'}
Path(sys.argv[3]).write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(evidence,ensure_ascii=False))
PY
xcrun xcresulttool export attachments --path "$permission_result_dir/tests.xcresult" \
  --output-path "$permission_result_dir/attachments"
echo "Photos-denied evidence: $permission_result_dir"
