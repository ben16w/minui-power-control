#!/usr/bin/env bats

setup() {
  load test_helper
  setup_power_control
}

# a system suspend script that records whether the app was stopped while it ran
install_system_suspend() {
  state=""
  if [ -n "${APP_PID:-}" ]; then
    state="\$(ps -o stat= -p $APP_PID | tr -d ' ')"
  fi

  cat >"$SYSTEM_PATH/bin/suspend" <<EOF
#!/bin/sh
echo "system-suspend $state" >>"\$STUB_LOG"
exit ${1:-0}
EOF
  chmod +x "$SYSTEM_PATH/bin/suspend"
}

@test "suspend needs a pid file" {
  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Emulator PID file not found."* ]]
}

@test "suspend refuses a pid that is no longer running" {
  start_app
  kill "$APP_PID"
  wait "$APP_PID" || true
  write_app_pid

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Emulator process $APP_PID not found."* ]]
}

@test "suspend stops the app while the system suspend script runs" {
  start_app
  write_app_pid
  install_system_suspend

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  grep -q "^system-suspend T" "$STUB_LOG"
  [[ "$(process_state "$APP_PID")" != T* ]]
}

@test "suspend restores the tg5040 brightness after waking" {
  start_app
  write_app_pid
  install_system_suspend

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  grep -q "^set-brightness 2" "$STUB_LOG"
  grep -q "^syncsettings.elf" "$STUB_LOG"
}

@test "suspend without an app still runs the system suspend script" {
  install_system_suspend
  touch "$POWERCONTROL_TMP_DIR/powercontrol-dummy-pid"

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  grep -q "^system-suspend" "$STUB_LOG"
}

@test "suspend without a system script pauses the app and resumes it on the next press" {
  start_app
  write_app_pid

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  [[ "$(process_state "$APP_PID")" == T* ]]
  [ -f "$POWERCONTROL_TMP_DIR/powercontrol-suspend-active" ]
  grep -q "^set-brightness 0" "$STUB_LOG"

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  [[ "$(process_state "$APP_PID")" != T* ]]
  [ ! -f "$POWERCONTROL_TMP_DIR/powercontrol-suspend-active" ]
  grep -q "^syncsettings.elf" "$STUB_LOG"
}

@test "suspend without a system script or an app does nothing" {
  touch "$POWERCONTROL_TMP_DIR/powercontrol-dummy-pid"

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No PID provided for fallback suspend."* ]]
}
