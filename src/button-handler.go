package main

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/holoplot/go-evdev"
)

const (
	powerKeyCode    = 116 // KEY_POWER
	powerKeyCodeAlt = 102 // some MY355 stacks expose power as 102
	shortPressMax   = 2 * time.Second
	// long enough for the drivers to finish waking before a press can start
	// another suspend
	coolDownTime = 3 * time.Second
)

var (
	binPath, _     = os.Executable()
	rootPath, _    = filepath.Abs(filepath.Dir(filepath.Dir(binPath)))
	suspendScript  = filepath.Join(rootPath, "suspend")
	shutdownScript = filepath.Join(rootPath, "shutdown")
	// present while the fallback suspend has the app paused
	suspendActiveFile = "/tmp/powercontrol-suspend-active"
)

// cooldownAfterSuspend returns when presses are listened to again. Deep sleep
// returns only once the device has woken, and a press soon after can catch the
// drivers still waking. The fallback suspend returns straight away, and the
// next press is the one that wakes the device, so it must not be ignored.
func cooldownAfterSuspend(now time.Time, pausedWithoutSleep bool) time.Time {
	if pausedWithoutSleep {
		return now
	}
	return now.Add(coolDownTime)
}

// defaultPowerDevice is where each platform's power key is usually found.
func defaultPowerDevice(platform string) string {
	switch platform {
	case "h700":
		// axp2202-pek; event1 is the ANBERNIC-keys gamepad
		return "/dev/input/event0"
	case "tg5050", "my355":
		return "/dev/input/event2"
	default:
		return "/dev/input/event1"
	}
}

// findPowerDevice keeps the platform's usual device when it reports a power
// key, and otherwise takes the first candidate that does, so a device whose
// input nodes are numbered differently still finds its power button.
func findPowerDevice(preferred string, candidates []string, hasPowerKey func(string) bool) (string, error) {
	if hasPowerKey(preferred) {
		return preferred, nil
	}

	for _, path := range candidates {
		if path != preferred && hasPowerKey(path) {
			return path, nil
		}
	}

	return "", fmt.Errorf("no input device reports a power key")
}

func deviceHasPowerKey(path string) bool {
	dev, err := evdev.Open(path)
	if err != nil {
		return false
	}
	defer dev.Close()

	for _, code := range dev.CapableEvents(evdev.EV_KEY) {
		if isPowerKey(code) {
			return true
		}
	}
	return false
}

func openPowerDevice() (*evdev.InputDevice, error) {
	candidates, _ := filepath.Glob("/dev/input/event*")
	path, err := findPowerDevice(defaultPowerDevice(os.Getenv("PLATFORM")), candidates, deviceHasPowerKey)
	if err != nil {
		return nil, err
	}
	return evdev.Open(path)
}

func isPowerKey(code evdev.EvCode) bool {
	return code == powerKeyCode || code == powerKeyCodeAlt
}

func main() {
	dev, err := openPowerDevice()
	if err != nil {
		log.Fatalf("Failed to open input device: %v", err)
	}
	log.Printf("Listening on device: %s\n", dev.Path())

	var pressTime time.Time
	var holdTimer *time.Timer
	var cooldownUntil time.Time

	for {
		event, err := dev.ReadOne()
		if err != nil {
			log.Printf("Failed to read input: %v", err)
			continue
		}

		if time.Now().Before(cooldownUntil) {
			continue
		}

		if event.Type != evdev.EV_KEY || !isPowerKey(event.Code) {
			continue
		}

		switch event.Value {
		case 1:
			// Key pressed — arm a timer for the long-hold action.
			// Some power-key drivers (e.g. my355's rk805 pwrkey) never emit
			// the autorepeat (value=2) events, so hold detection can't rely on them.
			pressTime = time.Now()
			if holdTimer != nil {
				holdTimer.Stop()
			}
			holdTimer = time.AfterFunc(shortPressMax, func() {
				log.Println("Button held for 2 seconds, shutting down...")
				runScript(shutdownScript)
			})
		case 0:
			// Key released. If timer hadn't fired yet, this is a short press.
			if pressTime.IsZero() {
				continue
			}
			pressTime = time.Time{}
			stopped := false
			if holdTimer != nil {
				stopped = holdTimer.Stop()
				holdTimer = nil
			}
			if stopped {
				log.Println("Short press detected, suspending...")
				runScript(suspendScript)
				_, err := os.Stat(suspendActiveFile)
				cooldownUntil = cooldownAfterSuspend(time.Now(), err == nil)
			}
		}
	}
}

func runScript(scriptPath string) {
	cmd := exec.Command(scriptPath)
	if err := cmd.Run(); err != nil {
		log.Printf("Failed to run %s script: %v", scriptPath, err)
	}
}
