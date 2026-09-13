#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/xcode-env.sh
if [[ ! -f Config/Signing.local.xcconfig && -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "Set a signing team in Config/Signing.local.xcconfig before archiving." >&2
  exit 1
fi
scripts/generate-project.sh
archive_dir="${LONGLET_ARCHIVE_DIR:-.work/archives/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$archive_dir"
xcodebuild -project ScrollCapture.xcodeproj -scheme ScrollCapture \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$archive_dir/Longlet.xcarchive" -allowProvisioningUpdates archive
echo "Archive: $archive_dir/Longlet.xcarchive"
echo "This script does not upload or publish the app."
