#!/usr/bin/env bash
# CI guard: FAIL if the zbus "tokio" feature is enabled anywhere in the workspace
#
# zbus async-io backend is runtime-agnostic, so leave "tokio" OFF and keep tokio for our
# own timers/select! only.
set -uo pipefail
cd "$(dirname "$0")" || exit 1

if cargo tree --locked --offline -e features 2>/dev/null | grep -qE 'zbus feature "tokio"'; then
  echo "FAIL: zbus 'tokio' feature is enabled in the dependency graph."
  echo "      slint's winit backend shares this zbus build and queries the XDG portal on"
  echo "      the main thread; tokio-only zbus panics there ('no reactor running')."
  echo "      Offending feature edges:"
  cargo tree --locked --offline -e features | grep -E 'zbus feature' | sort -u
  exit 1
fi
echo "OK: zbus 'tokio' feature absent (zbus uses its self-driving async-io backend)."
exit 0
