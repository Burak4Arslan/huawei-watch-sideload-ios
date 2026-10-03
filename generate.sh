#!/bin/bash
# Generates the Xcode project. First: cp Config/local.env.example Config/local.env and fill it in.
set -euo pipefail
cd "$(dirname "$0")"
command -v xcodegen >/dev/null || { echo "XcodeGen is required: brew install xcodegen"; exit 1; }
if [ -f Config/local.env ]; then
  # shellcheck disable=SC1091
  source Config/local.env
else
  echo "No Config/local.env: using the default bundle ID (pick your team in Xcode > Signing & Capabilities)"
fi
export HUASIDELOAD_TEAM_ID="${HUASIDELOAD_TEAM_ID:-}"
export HUASIDELOAD_BUNDLE_ID="${HUASIDELOAD_BUNDLE_ID:-com.example.huasideload}"
mkdir -p WatchApps
xcodegen generate
echo "Done: HuaSideload.xcodeproj (bundle ID $HUASIDELOAD_BUNDLE_ID)"
