# MinUI Power Control

A [MinUI](https://github.com/shauninman/MinUI) and [NextUI](https://github.com/LoveRetro/NextUI) app which provides deep sleep and shutdown functionality via the power button for emulators, ports and other apps lacking native support.

## Description

MinUI Power Control is an app that enables devices to use deep sleep and shutdown with the power button. It is intended for third-party paks lacking native power button support, whether they run an emulator, a port or any other app, providing functionality similar to that found in MinUI and NextUI emulators. The app monitors power button events and performs the actions on behalf of the app the pak runs. It's designed to be lightweight and easy to use, and comes as a single binary with minimal configuration required. It also runs in the background so that it does not interfere with the app or the game being played.

The app is especially aimed at developers creating paks, making it easy to add deep sleep and shutdown into their paks without needing to implement it from scratch.

## Requirements

This app is designed and tested on the following MinUI platforms and devices:

- `tg5040`: Trimui Brick (formerly `tg3040`), Trimui Smart Pro
- `tg5050`: Trimui Smart Pro S (NextUI only)
- `my355`: Miyoo Flip
- `miyoomini`: Miyoo Mini Plus (_not_ the Miyoo Mini)
- `rg35xxplus`: RG-35XX Plus, RG-34XX, RG-35XX H, RG-35XX SP
- `h700`: Anbernic RG28XX, RG34XX, RG34XX SP, RG35XX (Plus and 2024), RG35XX H, RG35XX Pro, RG35XX SP, RG40XX H, RG40XX V, RG CubeXX and RGSP (NextUI only)

Deep sleep is supported on Trimui Brick, Trimui Smart Pro, Trimui Smart Pro S, Miyoo Flip, and the Anbernic H700 devices running NextUI.

The power button is read from the input device each platform usually exposes it on. If that device reports no power key, every other input device is checked and the first one that reports one is used.

## Features

Currently, the app supports the following features:

- **Deep Sleep**: Deep sleep is supported on NextUI, as well a MinUI devices which have it enabled. Clicking the power button will immediately put the device into deep sleep. Clicking the power button again will wake the device up and resume the game. On NextUI, the game time tracker is paused while the device sleeps, so time asleep is not counted as play time.

- **Sleep**: On devices without deep sleep, which includes every device running MinUI, clicking the power button pauses the game and turns the screen off, the way MinUI's own sleep does. Clicking the power button again turns the screen back on and resumes the game. A device left asleep for two minutes shuts down, unless it is charging.

- **Shutdown**: Shut down the device by pressing and holding the power button for 2 seconds. The app is asked to quit first, and the device waits up to `POWERCONTROL_EXIT_TIMEOUT` seconds, 5 by default, for it to exit, so an app that saves when asked to quit, such as DraStic, can finish. **Warning**: An app that does not save when asked to quit, and has no save keys set as described under [Usage](#usage), will lose any progress made since the last save. Also, the game will not resume when the device is turned back on, unless it was shut down while asleep on a device without deep sleep and its rom path was given, as described under [Usage](#usage).

Deep sleep runs the system's own suspend script, at `$SYSTEM_PATH/bin/suspend`, which also stops Wi-Fi and Bluetooth before sleeping and restores them on waking. NextUI releases before [LoveRetro/NextUI#314](https://github.com/LoveRetro/NextUI/pull/314) could skip that restore, so if Wi-Fi does not reconnect after waking, update NextUI. After waking, the game stays paused for at least a second, and up to five, while the system finishes restoring audio and the screen settings, and presses of the power button are ignored for three seconds.

### Known Issues

- When resuming from deep sleep, if the brightness is set to 0, the screen will not turn on. This can be fixed by changing the brightness.

## Usage

```bash
minui-power-control <app-binary> &
```

Before starting `minui-power-control`, make sure the app is already running. Replace `<app-binary>` with the actual name of the app’s binary, such as an emulator. `minui-power-control` will run in the background, watching for power button events and carrying out the actions. Once the app it watches closes, `minui-power-control` will automatically exit as well. To make things more convenient and reliable, it’s best to start it in the pak’s `launch.sh` script, placing it before the command that starts the app. This makes sure it launches alongside the app, removing the need to start it manually.

The path of the rom the app is playing can be passed as a second argument:

```bash
minui-power-control <app-binary> "$ROM_PATH" &
```

On a device without deep sleep, a device left asleep long enough powers off, and with the rom path the rom is resumed when the device next starts, the same way MinUI and NextUI resume their own games. The rom is started again from the beginning unless the app saves and restores its own state. On NextUI, the rom the pak was launched for is used when no path is passed.

### Saving before sleeping or shutting down

`minui-power-control` cannot save on behalf of the app, but it can ask the app to save by pressing the keys the app saves on. Set `POWERCONTROL_SAVE_KEYS` to those keys before starting it, in the format [emit-key](https://github.com/josegonzalez/emit-key) takes, such as `f5` or `f1,f5:500000`:

```bash
POWERCONTROL_SAVE_KEYS="f5" minui-power-control <app-binary> &
```

The keys are pressed before the device goes to sleep or shuts down, while the app is still running, and the device waits `POWERCONTROL_SAVE_DELAY` seconds, 2 by default, for the save to finish. emit-key only presses keyboard keys, from `F1` to `F12`, `a` to `z`, `0` to `9` and `Esc`, so the app has to have one of them bound to saving. When `POWERCONTROL_SAVE_KEYS` is not set, no keys are pressed.

Alternatively, it is possible to run `minui-power-control` without specifying an app binary:

```bash
minui-power-control &
```

In this mode, the app creates a file at `/tmp/powercontrol-dummy-pid` and will continue running until that file is deleted. This is useful for testing or for scenarios where the name of the app binary is not known in advance.

## Building

The latest version of the app can be downloaded from the [Releases](https://github.com/ben16w/minui-power-control/releases) page. To build the app manually, install Go from the [official website](https://golang.org/dl/). After installing Go, fetch dependencies and build the app with:

```bash
make build
```

To create a release build, use the command below. This generates a single release-ready binary in the `dist` directory, suitable for running on a device. The release is packaged using the [makeself](https://makeself.io/) tool.

```bash
make release
```

## Testing

The scripts in `bin` are tested with [bats](https://github.com/bats-core/bats-core), and the button handler with `go test`:

```bash
make test
```

The tests run the scripts against stubbed device commands. `POWERCONTROL_TMP_DIR`, `POWERCONTROL_PROC_DIR` and `POWERCONTROL_SYS_DIR` exist for the test suite only, and override the `/tmp`, `/proc` and `/sys` folders the scripts read and write.

## Thanks

- [Shaun Inman](https://github.com/shauninman) for developing [MinUI](https://github.com/shauninman/MinUI).
- [ro8inmorgan](https://github.com/ro8inmorgan), [frysee](https://github.com/frysee) and the rest of the NextUI contributors for developing [NextUI](https://github.com/LoveRetro/NextUI).

## License

This project is released under the [MIT License](https://opensource.org/licenses/MIT). See the [LICENSE](LICENSE) file for details.
