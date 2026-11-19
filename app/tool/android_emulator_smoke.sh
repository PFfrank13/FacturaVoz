#!/usr/bin/env bash
# Android emulator smoke test; CI fixtures only, never connects to production.
set -Eeuo pipefail

adb logcat -c || true
set +e
(
  cd app
  flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/bodega_emulator_smoke_test.dart \
    -d emulator-5554 \
    --no-dds \
    --dart-define=SUPABASE_URL=https://example.supabase.co \
    --dart-define=SUPABASE_ANON_KEY=ci \
    --dart-define=API_BASE_URL=https://example.vercel.app
)
status=$?
set -e
if [ "$status" -ne 0 ]; then
  echo 'ANDROID SMOKE FAILED: collecting crash and VM-service diagnostics'
  adb shell pidof dev.solvexsoftware.facturavoz || true
  adb shell dumpsys activity activities | tail -n 75 || true
  echo '--- Android crash buffer ---'
  adb logcat -d -b crash -v brief -t 800 | tail -n 220 || true
  echo '--- Flutter / AndroidRuntime / process events ---'
  adb logcat -d -v brief -t 3000 |
    grep -Ei 'AndroidRuntime|FATAL EXCEPTION|flutter|crash|OutOfMemoryError|am_crash|am_kill|Killed process|signal 11|signal 6|vmservice|VM Service|SIGSEGV|SIGABRT' |
    tail -n 260 || true
  exit "$status"
fi
echo 'ANDROID SMOKE PASSED: integration tests executed on the emulator'
