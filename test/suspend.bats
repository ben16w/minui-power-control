#!/usr/bin/env bats

setup() {
  load test_helper
  setup_power_control
  gate_sleep

  # the sleep timer powers off through this
  stub shutdown
  mv "$STUB_DIR/shutdown" "$BIN_DIR/shutdown"
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
  [[ "$output" == *"App PID file not found."* ]]
}

@test "suspend refuses a pid that is no longer running" {
  start_app
  kill "$APP_PID"
  wait "$APP_PID" || true
  write_app_pid

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 1 ]
  [[ "$output" == *"App process $APP_PID not found."* ]]
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

@test "suspend on h700 turns the screen off around the system suspend script" {
  export PLATFORM=h700
  blank="$POWERCONTROL_SYS_DIR/class/graphics/fb0/blank"
  start_app
  write_app_pid
  cat >"$SYSTEM_PATH/bin/suspend" <<EOF
#!/bin/sh
echo "system-suspend blank=\$(cat "$blank")" >>"\$STUB_LOG"
EOF
  chmod +x "$SYSTEM_PATH/bin/suspend"

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  [ "$(cat "$blank")" = "0" ]
  [ "$(sed -n 1p "$STUB_LOG")" = "set-brightness 0" ]
  [ "$(sed -n 2p "$STUB_LOG")" = "system-suspend blank=1" ]
  [ "$(sed -n 3p "$STUB_LOG")" = "syncsettings.elf " ]
}

@test "suspend leaves the screen alone on platforms whose suspend script handles it" {
  start_app
  write_app_pid
  install_system_suspend

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  [ ! -f "$POWERCONTROL_SYS_DIR/class/graphics/fb0/blank" ]
  ! grep -q "^set-brightness 0" "$STUB_LOG"
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

@test "suspend pauses the NextUI game time tracker while asleep" {
  stub gametimectl.elf
  start_app
  write_app_pid
  install_system_suspend

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  [ "$(line_of "gametimectl.elf stop_all")" -lt "$(line_of "system-suspend")" ]
  [ "$(tail -n 1 "$STUB_LOG")" = "gametimectl.elf resume" ]
}

@test "suspend without a system script pauses the game time tracker until the next press" {
  stub gametimectl.elf
  start_app
  write_app_pid

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  grep -q "^gametimectl.elf stop_all" "$STUB_LOG"
  ! grep -q "^gametimectl.elf resume" "$STUB_LOG"

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  [ "$(tail -n 1 "$STUB_LOG")" = "gametimectl.elf resume" ]
}

@test "suspend works without a game time tracker" {
  start_app
  write_app_pid
  install_system_suspend

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  ! grep -q "gametimectl.elf" "$STUB_LOG"
}

# NextUI's suspend scripts run under set -u and restore Wi-Fi from a background
# job after waking, which only works if SYSTEM_PATH reaches them and that job is
# not killed when the script returns
@test "suspend lets the system suspend script restore Wi-Fi in the background" {
  start_app
  write_app_pid
  cat >"$SYSTEM_PATH/bin/suspend" <<EOF
#!/bin/sh
set -u
echo "system-suspend \$SYSTEM_PATH" >>"\$STUB_LOG"
(/bin/sleep 0.2; echo "wifi-restored" >>"\$STUB_LOG") 3>&- &
EOF
  chmod +x "$SYSTEM_PATH/bin/suspend"

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  grep -q "^system-suspend $SYSTEM_PATH$" "$STUB_LOG"
  ! grep -q "^wifi-restored" "$STUB_LOG"

  for _ in $(seq 1 40); do
    grep -q "^wifi-restored" "$STUB_LOG" && break
    /bin/sleep 0.05
  done
  grep -q "^wifi-restored" "$STUB_LOG"
}

# check_fallback_screen PLATFORM FILE OFF ON: the fallback writes OFF to FILE under /sys while
# asleep and ON once woken
check_fallback_screen() {
  export PLATFORM="$1"
  start_app
  write_app_pid
  mkdir -p "$(dirname "$POWERCONTROL_SYS_DIR/$2")"

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  [ "$(cat "$POWERCONTROL_SYS_DIR/$2")" = "$3" ]

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  [ "$(cat "$POWERCONTROL_SYS_DIR/$2")" = "$4" ]
}

@test "suspend without a system script blanks the rg35xxplus screen" {
  check_fallback_screen rg35xxplus class/graphics/fb0/blank 4 0
}

@test "suspend without a system script turns the my355 backlight off" {
  check_fallback_screen my355 class/backlight/backlight/bl_power 4 0
}

@test "suspend without a system script turns the miyoomini backlight off" {
  check_fallback_screen miyoomini class/gpio/gpio4/value 0 1
  [ "$(cat "$POWERCONTROL_SYS_DIR/class/gpio/export")" = "4" ]
  [ "$(cat "$POWERCONTROL_SYS_DIR/class/gpio/gpio4/direction")" = "out" ]
}

@test "suspend without a system script turns the h700 screen off and restores its brightness" {
  check_fallback_screen h700 class/graphics/fb0/blank 1 0
  grep -q "^set-brightness 0" "$STUB_LOG"
  grep -q "^syncsettings.elf" "$STUB_LOG"
}

@test "suspend without a system script pauses keymon while asleep" {
  start_app
  write_app_pid

  run sh "$BIN_DIR/suspend"
  grep -q "^killall -STOP keymon.elf" "$STUB_LOG"
  ! grep -q "^killall -CONT keymon.elf" "$STUB_LOG"

  run sh "$BIN_DIR/suspend"
  grep -q "^killall -CONT keymon.elf" "$STUB_LOG"
}

@test "suspend without a system script powers off a device left asleep" {
  start_app
  write_app_pid

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  ! grep -q "^shutdown" "$STUB_LOG"

  open_gate
  wait_for_log shutdown
}

@test "suspend without a system script does not power off a device that woke" {
  start_app
  write_app_pid

  run sh "$BIN_DIR/suspend"
  run sh "$BIN_DIR/suspend"
  open_gate

  /bin/sleep 0.3
  ! grep -q "^shutdown" "$STUB_LOG"
}

@test "suspend without a system script powers off once for the latest sleep only" {
  start_app
  write_app_pid

  run sh "$BIN_DIR/suspend"
  run sh "$BIN_DIR/suspend"
  run sh "$BIN_DIR/suspend"
  open_gate

  wait_for_log shutdown
  /bin/sleep 0.3
  [ "$(grep -c "^shutdown" "$STUB_LOG")" -eq 1 ]
}

@test "suspend without a system script stays asleep while the device charges" {
  mkdir -p "$POWERCONTROL_SYS_DIR/class/power_supply/battery"
  echo Charging >"$POWERCONTROL_SYS_DIR/class/power_supply/battery/status"
  start_app
  write_app_pid

  run sh "$BIN_DIR/suspend"
  open_gate
  /bin/sleep 0.3
  ! grep -q "^shutdown" "$STUB_LOG"

  echo Discharging >"$POWERCONTROL_SYS_DIR/class/power_supply/battery/status"
  wait_for_log shutdown
}

@test "suspend without a system script resumes the rom if the device powers off asleep" {
  start_app
  write_app_pid
  echo "$SDCARD_PATH/Roms/Game (TAG)/game.rom" >"$POWERCONTROL_TMP_DIR/powercontrol-rom-path"
  auto_resume="$SHARED_USERDATA_PATH/.minui/auto_resume.txt"

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  [ "$(cat "$auto_resume")" = "/Roms/Game (TAG)/game.rom" ]
  # minarch writes no trailing newline, so the last byte is the rom's own
  [ "$(tail -c 1 "$auto_resume")" = "m" ]

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  [ ! -f "$auto_resume" ]
}

@test "suspend without a system script keeps the resume file once the device powers off" {
  start_app
  write_app_pid
  echo "$SDCARD_PATH/Roms/Game (TAG)/game.rom" >"$POWERCONTROL_TMP_DIR/powercontrol-rom-path"

  run sh "$BIN_DIR/suspend"
  open_gate
  wait_for_log shutdown
  [ -f "$SHARED_USERDATA_PATH/.minui/auto_resume.txt" ]
}

@test "suspend without a rom path writes no resume file" {
  start_app
  write_app_pid

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  [ ! -f "$SHARED_USERDATA_PATH/.minui/auto_resume.txt" ]
}

@test "suspend cannot resume a rom that is not on the SD card" {
  start_app
  write_app_pid
  echo "/elsewhere/game.rom" >"$POWERCONTROL_TMP_DIR/powercontrol-rom-path"

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  [[ "$output" == *"is not on the SD card"* ]]
  [ ! -f "$SHARED_USERDATA_PATH/.minui/auto_resume.txt" ]
}

@test "suspend with a system script leaves resuming to the system" {
  start_app
  write_app_pid
  install_system_suspend
  echo "$SDCARD_PATH/Roms/Game (TAG)/game.rom" >"$POWERCONTROL_TMP_DIR/powercontrol-rom-path"

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  [ ! -f "$SHARED_USERDATA_PATH/.minui/auto_resume.txt" ]
}

# an emit-key that records whether the app could still act on the keys
stub_emit_key() {
  stub emit-key "echo \"emit-key-state \$(ps -o stat= -p $APP_PID | tr -d ' ')\" >>\"\$STUB_LOG\"; exit ${1:-0}"
}

@test "suspend sends the save keys while the app is still running" {
  export POWERCONTROL_SAVE_KEYS="f5" POWERCONTROL_SAVE_DELAY=0
  start_app
  write_app_pid
  stub_emit_key
  install_system_suspend

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  grep -q "^emit-key -k f5$" "$STUB_LOG"
  [[ "$(grep "^emit-key-state" "$STUB_LOG")" != "emit-key-state T"* ]]
  [ "$(line_of "emit-key -k f5")" -lt "$(line_of "system-suspend")" ]
}

@test "suspend waits for the app to save before pausing it" {
  export POWERCONTROL_SAVE_KEYS="f5"
  start_app
  write_app_pid
  stub_emit_key
  stub sleep
  install_system_suspend

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  [ "$(line_of "sleep 2")" -lt "$(line_of "system-suspend")" ]
}

@test "suspend sends no keys unless the pak names them" {
  start_app
  write_app_pid
  stub_emit_key
  install_system_suspend

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  ! grep -q "^emit-key" "$STUB_LOG"
}

@test "suspend still sleeps when the save keys cannot be sent" {
  export POWERCONTROL_SAVE_KEYS="f5" POWERCONTROL_SAVE_DELAY=0
  start_app
  write_app_pid
  stub_emit_key 1
  install_system_suspend

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  [[ "$output" == *"emit-key could not send the save keys."* ]]
  grep -q "^system-suspend" "$STUB_LOG"
}

@test "suspend without a system script sends the save keys only when going to sleep" {
  export POWERCONTROL_SAVE_KEYS="f5" POWERCONTROL_SAVE_DELAY=0
  start_app
  write_app_pid
  stub_emit_key

  run sh "$BIN_DIR/suspend"
  [ "$(grep -c "^emit-key -k" "$STUB_LOG")" -eq 1 ]

  run sh "$BIN_DIR/suspend"
  [ "$(grep -c "^emit-key -k" "$STUB_LOG")" -eq 1 ]
}

# a pgrep that reports the system as still resuming for its first N calls,
# recording whether the app was still paused each time
stub_resume_in_progress() {
  stub pgrep "
calls=\$(grep -c '^pgrep [a-z]' \"\$STUB_LOG\")
echo \"pgrep-state \$(ps -o stat= -p $APP_PID | tr -d ' ')\" >>\"\$STUB_LOG\"
[ \"\$calls\" -le $1 ]"
}

@test "suspend keeps the app paused until the system has finished resuming" {
  start_app
  write_app_pid
  install_system_suspend
  stub_resume_in_progress 2

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  [ "$(grep -c "^sleep 1" "$STUB_LOG")" -eq 3 ]
  ! grep -q "^pgrep-state [^T]" "$STUB_LOG"
  [[ "$(process_state "$APP_PID")" != T* ]]
}

@test "suspend resumes the app after five seconds even if the system is still resuming" {
  start_app
  write_app_pid
  install_system_suspend
  stub_resume_in_progress 100

  run sh "$BIN_DIR/suspend"
  [ "$status" -eq 0 ]
  [ "$(grep -c "^sleep 1" "$STUB_LOG")" -eq 5 ]
  [[ "$(process_state "$APP_PID")" != T* ]]
}

@test "suspend waits for the system to resume even when the suspend script fails" {
  start_app
  write_app_pid
  install_system_suspend 1
  stub pgrep "exit 1"

  run sh "$BIN_DIR/suspend"
  [ "$(grep -c "^sleep 1" "$STUB_LOG")" -eq 1 ]
  [ "$(line_of "system-suspend")" -lt "$(line_of "sleep 1")" ]
}
