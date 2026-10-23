#!/usr/bin/env bats

setup() {
  load test_helper
  setup_power_control
  install_release_stubs
}

@test "launch refuses a platform it does not support" {
  PLATFORM=notaplatform run sh "$BIN_DIR/launch"
  [ "$status" -eq 1 ]
  [[ "$output" == *"notaplatform is not a supported platform."* ]]
}

@test "launch refuses to start without minui-presenter" {
  rm -f "$STUB_DIR/minui-presenter" "$BIN_DIR/$PLATFORM/minui-presenter"

  run sh "$BIN_DIR/launch"
  [ "$status" -eq 1 ]
  [[ "$output" == *"minui-presenter binary not found."* ]]
}

@test "launch gives up when the app never starts" {
  stub pgrep

  run sh "$BIN_DIR/launch" missing-app
  [ "$status" -eq 1 ]
  [[ "$output" == *"Emulator process missing-app not found."* ]]
  ! grep -q "button-handler" "$STUB_LOG"
}

@test "launch watches the power button until the app exits" {
  start_app 1
  stub pgrep "echo $APP_PID"

  run sh "$BIN_DIR/launch" sleep
  [ "$status" -eq 0 ]
  [[ "$output" == *"Emulator PID: $APP_PID"* ]]
  grep -q "^button-handler" "$STUB_LOG"
  [ ! -f "$POWERCONTROL_TMP_DIR/powercontrol-emulator-pid" ]
}

@test "launch without an app runs until the dummy pid file is removed" {
  sh "$BIN_DIR/launch" >"$BATS_TEST_TMPDIR/launch.out" 3>&- &
  launch_pid=$!

  for _ in $(seq 1 100); do
    [ -f "$POWERCONTROL_TMP_DIR/powercontrol-dummy-pid" ] && break
    /bin/sleep 0.05
  done
  [ -f "$POWERCONTROL_TMP_DIR/powercontrol-dummy-pid" ]

  rm -f "$POWERCONTROL_TMP_DIR/powercontrol-dummy-pid"
  wait "$launch_pid"
  grep -q "Creating a dummy PID file" "$BATS_TEST_TMPDIR/launch.out"
}
