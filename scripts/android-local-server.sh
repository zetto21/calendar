#!/bin/sh
# Forward OAuth localhost callbacks from the development device to this host.
set -eu
cd "$(dirname "$0")/.."
sdk_dir="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [ -z "$sdk_dir" ] && [ -f android/local.properties ]; then
  sdk_dir=$(sed -n 's/^sdk\.dir=//p' android/local.properties | head -n 1)
fi
if [ -n "$sdk_dir" ]; then
  adb_bin="$sdk_dir/platform-tools/adb"
else
  adb_bin=adb
fi
if [ "$#" -gt 0 ]; then
  "$adb_bin" -s "$1" reverse tcp:3001 tcp:3001
else
  "$adb_bin" reverse tcp:3001 tcp:3001
fi
