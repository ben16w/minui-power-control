# shellcheck shell=bash

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup_power_control() {
  architecture=arm
  if uname -m | grep -q '64'; then
    architecture=arm64
  fi

  # the scripts put the folders beside themselves first on PATH, so each test
  # runs its own copy with the release binaries stubbed out where they would be
  BIN_DIR="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN_DIR"
  cp "$REPO_ROOT/bin/launch" "$REPO_ROOT/bin/suspend" "$REPO_ROOT/bin/shutdown" "$REPO_ROOT/bin/send-save-keys" "$BIN_DIR/"

  STUB_DIR="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUB_DIR"
  export STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
  : >"$STUB_LOG"

  export POWERCONTROL_TMP_DIR="$BATS_TEST_TMPDIR/tmp"
  export POWERCONTROL_PROC_DIR="$BATS_TEST_TMPDIR/proc"
  export POWERCONTROL_SYS_DIR="$BATS_TEST_TMPDIR/sys"
  mkdir -p "$POWERCONTROL_TMP_DIR" "$POWERCONTROL_PROC_DIR" "$POWERCONTROL_SYS_DIR/class/graphics/fb0"

  export PLATFORM=tg5040
  export DEVICE=brick
  export SYSTEM_PATH="$BATS_TEST_TMPDIR/system"
  mkdir -p "$SYSTEM_PATH/bin"
  export SDCARD_PATH="$BATS_TEST_TMPDIR/sdcard"
  export SHARED_USERDATA_PATH="$SDCARD_PATH/.userdata/shared"
  unset IS_NEXT HOOK_ROM_PATH

  for name in minui-presenter killall poweroff syncsettings.elf set-brightness; do
    stub "$name"
  done

  # the scripts poll once a second, which would make every test take seconds
  printf '#!/bin/sh\nexec /bin/sleep 0.05\n' >"$STUB_DIR/sleep"
  chmod +x "$STUB_DIR/sleep"

  export PATH="$STUB_DIR:$PATH"
}

teardown() {
  # a sleep timer still waiting on the gate sees the device awake and exits
  rm -f "$POWERCONTROL_TMP_DIR/powercontrol-suspend-active"
  touch "$BATS_TEST_TMPDIR/gate"

  # only ever real child pids: a kill of 0 would signal the whole test run
  for pid in ${APP_PID:-} ${OTHER_PID:-}; do
    [ "$pid" -gt 0 ] || continue
    kill -CONT "$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
  done
}

# stub NAME [BODY] puts a NAME on PATH that logs its arguments, then runs BODY
stub() {
  printf '#!/bin/sh\necho "%s $*" >>"$STUB_LOG"\n%s\n' "$1" "${2:-}" >"$STUB_DIR/$1"
  chmod +x "$STUB_DIR/$1"
}

# bin/launch checks for these beside itself, where a release build puts them
install_release_stubs() {
  mkdir -p "$BIN_DIR/$PLATFORM" "$BIN_DIR/$architecture"
  cp "$STUB_DIR/minui-presenter" "$STUB_DIR/set-brightness" "$BIN_DIR/$PLATFORM/"
  stub button-handler 'exec /bin/sleep 30'
  mv "$STUB_DIR/button-handler" "$BIN_DIR/$architecture/button-handler"
}

# a real process for the scripts to signal, closed off from the fd bats reads
start_app() {
  /bin/sleep "${1:-30}" 3>&- &
  APP_PID=$!
}

write_app_pid() {
  echo "$APP_PID" >"$POWERCONTROL_TMP_DIR/powercontrol-app-pid"
}

# prints the process state, which starts with T while it is stopped
process_state() {
  ps -o stat= -p "$1" | tr -d ' '
}

# prints the number of the first stub log line starting with PATTERN, so tests
# can assert the order commands ran in
line_of() {
  grep -n "^$1" "$STUB_LOG" | head -n 1 | cut -d: -f1
}

# makes sleep block until open_gate, so a test decides when the timer that
# powers off a sleeping device runs out
gate_sleep() {
  printf '#!/bin/sh\nwhile [ ! -f "%s" ]; do /bin/sleep 0.02; done\n' "$BATS_TEST_TMPDIR/gate" >"$STUB_DIR/sleep"
  chmod +x "$STUB_DIR/sleep"
}

open_gate() {
  touch "$BATS_TEST_TMPDIR/gate"
}

# waits up to two seconds for a stub log line starting with PATTERN
wait_for_log() {
  for _ in $(seq 1 100); do
    grep -q "^$1" "$STUB_LOG" && return 0
    /bin/sleep 0.02
  done
  return 1
}
