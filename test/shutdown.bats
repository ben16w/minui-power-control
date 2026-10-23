#!/usr/bin/env bats

setup() {
  load test_helper
  setup_power_control

  # shutdown waits forever for the power to go, so the first wait once it has
  # asked for the power off ends the test
  cat >"$STUB_DIR/sleep" <<EOF
#!/bin/sh
if grep -q "^poweroff" "\$STUB_LOG" || [ -f "$POWERCONTROL_TMP_DIR/poweroff" ]; then
  kill -TERM "\$PPID"
fi
exec /bin/sleep 0.05
EOF
}

@test "shutdown needs a pid file" {
  run sh "$BIN_DIR/shutdown"
  [ "$status" -eq 1 ]
  [[ "$output" == *"App PID file not found."* ]]
}

@test "shutdown on MinUI ends the app and powers off" {
  start_app
  write_app_pid

  run sh "$BIN_DIR/shutdown"
  grep -q "^minui-presenter --message Powering off --timeout -1" "$STUB_LOG"
  grep -q "^poweroff" "$STUB_LOG"

  run wait "$APP_PID"
  [ "$status" -eq 143 ]
}

@test "shutdown without an app still powers off" {
  touch "$POWERCONTROL_TMP_DIR/powercontrol-dummy-pid"

  run sh "$BIN_DIR/shutdown"
  [[ "$output" == *"No app process to kill."* ]]
  grep -q "^poweroff" "$STUB_LOG"
}

@test "shutdown on NextUI leaves the power off to NextUI and ends the pak" {
  export IS_NEXT=yes
  start_app
  write_app_pid

  /bin/sleep 30 3>&- &
  OTHER_PID=$!
  pak="/mnt/SDCARD/Emus/tg5040/PICO.pak/launch.sh"
  rom="/mnt/SDCARD/Roms/Pico-8 (PICO)/cart.p8"
  printf "'%s' '%s'\n" "$pak" "$rom" >"$POWERCONTROL_TMP_DIR/next"
  mkdir -p "$POWERCONTROL_PROC_DIR/$OTHER_PID"
  printf '/bin/sh\0%s\0%s\0' "$pak" "$rom" >"$POWERCONTROL_PROC_DIR/$OTHER_PID/cmdline"

  run sh "$BIN_DIR/shutdown"
  [ -f "$POWERCONTROL_TMP_DIR/poweroff" ]
  grep -q "^killall -TERM nextui.elf" "$STUB_LOG"
  ! grep -q "^poweroff" "$STUB_LOG"

  run wait "$OTHER_PID"
  [ "$status" -eq 143 ]
}

@test "shutdown closes the NextUI game time session" {
  stub gametimectl.elf
  export IS_NEXT=yes
  start_app
  write_app_pid

  run sh "$BIN_DIR/shutdown"
  grep -q "^gametimectl.elf stop_all" "$STUB_LOG"
}

@test "shutdown resumes a paused app so it can act on the signal" {
  start_app
  write_app_pid
  kill -STOP "$APP_PID"
  touch "$POWERCONTROL_TMP_DIR/powercontrol-suspend-active"

  run sh "$BIN_DIR/shutdown"
  grep -q "^killall -CONT keymon.elf" "$STUB_LOG"
  [ ! -f "$POWERCONTROL_TMP_DIR/powercontrol-suspend-active" ]

  run wait "$APP_PID"
  [ "$status" -eq 143 ]
}

@test "shutdown sends the save keys before ending the app" {
  export POWERCONTROL_SAVE_KEYS="f5" POWERCONTROL_SAVE_DELAY=0
  stub emit-key
  start_detached_app
  write_app_pid

  run sh "$BIN_DIR/shutdown"
  grep -q "^emit-key -k f5$" "$STUB_LOG"
  [ "$(line_of "emit-key")" -lt "$(line_of "poweroff")" ]
}

@test "shutdown waits for the app to exit before powering off" {
  start_detached_app "trap 'echo saved >>\"$STUB_LOG\"; exit 0' TERM; while :; do /bin/sleep 0.05; done"
  write_app_pid

  run sh "$BIN_DIR/shutdown"
  [[ "$output" == *"App process $APP_PID exited."* ]]
  [ "$(line_of "saved")" -lt "$(line_of "poweroff")" ]
}

@test "shutdown powers off when the app does not exit in time" {
  export POWERCONTROL_EXIT_TIMEOUT=2
  start_detached_app "trap '' TERM; while :; do /bin/sleep 0.05; done"
  write_app_pid

  run sh "$BIN_DIR/shutdown"
  [[ "$output" == *"did not exit within 2s, shutting down anyway."* ]]
  grep -q "^poweroff" "$STUB_LOG"
}
