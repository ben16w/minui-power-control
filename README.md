# MinUI Power Control

A [MinUI](https://github.com/shauninman/MinUI) and [NextUI](https://github.com/LoveRetro/NextUI) app which provides deep sleep and shutdown functionality via the power button for emulators lacking native support.

## Description

MinUI Power Control is an app that enables devices to use deep sleep and shutdown with the power button. It is intended for third-party emulator paks lacking native power button support, providing functionality similar to that found in MinUI and NextUI emulators. The app monitors power button events and performs the actions on behalf of the emulator. It's designed to be lightweight and easy to use, and comes as a single binary with minimal configuration required. It also runs in the background so that it does not interfere with the emulator or the game being played.

The app is especially aimed at developers creating emulator paks, making it easy to add deep sleep and shutdown into their paks without needing to implement it from scratch.

## Requirements

This app is designed and tested on the following MinUI platforms and devices:

- `tg5040`: Trimui Brick (formerly `tg3040`), Trimui Smart Pro
- `miyoomini`: Miyoo Mini Plus (_not_ the Miyoo Mini)
- `rg35xxplus`: RG-35XX Plus, RG-34XX, RG-35XX H, RG-35XX SP

Deep sleep is currently only supported on the Trimui Brick and Trimui Smart Pro.

## Features

Currently, the app supports the following features:

- **Deep Sleep**: Deep sleep is supported on NextUI, as well a MinUI devices which have it enabled. Clicking the power button will immediately put the device into deep sleep. Clicking the power button again will wake the device up and resume the game.

- **Shutdown**: Shut down the device by pressing and holding the power button for 2 seconds. **Warning**: Currently, this will **NOT** save the game, and any progress made since the last save will be lost. Also, the game will not resume when the device is turned back on.

### Known Issues

- When resuming from deep sleep, the Wi-Fi may not reconnect.
- When resuming from deep sleep, if the brightness is set to 0, the screen will not turn on. This can be fixed by changing the brightness.

## Usage

```bash
minui-power-control <emulator> &
```

Before starting `minui-power-control`, make sure the emulator is already running. Replace `<emulator>` with the actual name of the emulator’s binary. The app will run in the background, watching for power button events and carrying out the actions. Once the emulator closes, the app will automatically exit as well. To make things more convenient and reliable, it’s best to start the app in the emulator’s `launch.sh` script, placing it before the emulator command. This makes sure it launches alongside the emulator, removing the need to start it manually.

## Building

The latest version of the app can be downloaded from the [Releases](https://github.com/ben16w/minui-power-control/releases) page. To build the app manually, install Go from the [official website](https://golang.org/dl/). After installing Go, fetch dependencies and build the app with:

```bash
make build
```

To create a release build, use the command below. This generates a single release-ready binary in the `dist` directory, suitable for running on a device. The release is packaged using the [makeself](https://makeself.io/) tool.

```bash
make release
```

## Thanks

- [Shaun Inman](https://github.com/shauninman) for developing [MinUI](https://github.com/shauninman/MinUI).
- [ro8inmorgan](https://github.com/ro8inmorgan), [frysee](https://github.com/frysee) and the rest of the NextUI contributors for developing [NextUI](https://github.com/LoveRetro/NextUI).

## License

This project is released under the [MIT License](https://opensource.org/licenses/MIT). See the [LICENSE](LICENSE) file for details.
