package main

import (
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
	coolDownTime    = 1 * time.Second
)

var (
	binPath, _     = os.Executable()
	rootPath, _    = filepath.Abs(filepath.Dir(filepath.Dir(binPath)))
	suspendScript  = filepath.Join(rootPath, "suspend")
	shutdownScript = filepath.Join(rootPath, "shutdown")
)

func openPowerDevice() (*evdev.InputDevice, error) {
	switch os.Getenv("PLATFORM") {
	case "tg5050", "my355":
		return evdev.Open("/dev/input/event2")
	default:
		return evdev.Open("/dev/input/event1")
	}
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
				cooldownUntil = time.Now().Add(coolDownTime)
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
