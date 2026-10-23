#!/usr/bin/env bats

setup() {
  load test_helper
  setup_power_control

  # shutdown waits forever for the power to go, so the first wait ends the test
  printf '#!/bin/sh\nkill -TERM "$PPID"\n' >"$STUB_DIR/sleep"
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
