#!/bin/zsh
# Launches a packaged app and fails if it doesn't keep running, catching crashes at startup
# (such as a missing resource) that unit tests can't see.
# Usage: zsh Scripts/smoke-test-app.zsh ["path/to/Splash Launcher.app"]
set -euo pipefail
cd "${0:A:h:h}"
app="${1:-dist/Splash Launcher.app}"
binary="$app/Contents/MacOS/SplashLauncher"
[[ -x "$binary" ]] || { print -u2 "No app executable at $binary"; exit 1; }

"$binary" &
pid=$!
sleep 8
if kill -0 "$pid" 2>/dev/null; then
  kill "$pid"
  wait "$pid" 2>/dev/null || true
  print "Launch check passed: the app started and kept running."
else
  code=0
  wait "$pid" || code=$?
  print -u2 "Launch check failed: the app exited during startup (status $code)."
  exit 1
fi
