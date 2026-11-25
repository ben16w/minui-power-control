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
  cp "$REPO_ROOT/bin/launch" "$REPO_ROOT/bin/suspend" "$REPO_ROOT/bin/shutdown" "$BIN_DIR/"

  STUB_DIR="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUB_DIR"
  export STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
  : >"$STUB_LOG"

  export POWERCONTROL_TMP_DIR="$BATS_TEST_TMPDIR/tmp"
  export POWERCONTROL_PROC_DIR="$BATS_TEST_TMPDIR/proc"
  mkdir -p "$POWERCONTROL_TMP_DIR" "$POWERCONTROL_PROC_DIR"

  export PLATFORM=tg5040
  export DEVICE=brick
  export SYSTEM_PATH="$BATS_TEST_TMPDIR/system"
  mkdir -p "$SYSTEM_PATH/bin"
  unset IS_NEXT

  for name in minui-presenter killall poweroff syncsettings.elf set-brightness; do
    stub "$name"
  done

  # the scripts poll once a second, which would make every test take seconds
  printf '#!/bin/sh\nexec /bin/sleep 0.05\n' >"$STUB_DIR/sleep"
  chmod +x "$STUB_DIR/sleep"

  export PATH="$STUB_DIR:$PATH"
}

teardown() {
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
  echo "$APP_PID" >"$POWERCONTROL_TMP_DIR/powercontrol-emulator-pid"
}

# prints the process state, which starts with T while it is stopped
process_state() {
  ps -o stat= -p "$1" | tr -d ' '
}
