#!/bin/bash
# Source this from repository scripts; do not change the global xcode-select setting.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  selected_developer_dir="$(xcode-select -p 2>/dev/null || true)"
  if [[ -x "$selected_developer_dir/usr/bin/xcodebuild" ]]; then
    export DEVELOPER_DIR="$selected_developer_dir"
  elif [[ -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  else
    echo "Full Xcode is required. Set DEVELOPER_DIR to its Contents/Developer directory." >&2
    return 1
  fi
fi
