package main

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
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
	// NextUI checks the lid once a frame; a quarter second is as quick to the
	// eye and costs next to nothing
	lidPollInterval = 250 * time.Millisecond
)

var (
	binPath, _     = os.Executable()
	rootPath, _    = filepath.Abs(filepath.Dir(filepath.Dir(binPath)))
	suspendScript  = filepath.Join(rootPath, "suspend")
	shutdownScript = filepath.Join(rootPath, "shutdown")
	// present while the fallback suspend has the app paused
	suspendActiveFile = "/tmp/powercontrol-suspend-active"
	// the Miyoo Flip's hall sensor, 1 while the lid is open. MinUI and NextUI
	// both move the system's own lid handler aside, so nothing else acts on it
	// while a pak runs.
	lidStateFile = "/sys/devices/platform/hall-mh248/hallvalue"
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

// sleeper runs the suspend script for both the power key and the lid, one at a
// time. Anything that asks while a run is under way is dropped rather than
// queued, so a press made during a lid sleep cannot put the device straight
// back to sleep once it wakes.
type sleeper struct {
	mu            sync.Mutex
	cooldownUntil time.Time
	run           func()
	suspended     func() bool
}

// listening reports whether a power key event should be acted on now.
func (s *sleeper) listening(now time.Time) bool {
	if !s.mu.TryLock() {
		return false
	}
	defer s.mu.Unlock()
	return !now.Before(s.cooldownUntil)
}

// suspend runs the suspend script unless another run is under way or the
// device is still waking, and reports whether it ran.
func (s *sleeper) suspend() bool {
	if !s.mu.TryLock() {
		return false
	}
	defer s.mu.Unlock()

	if time.Now().Before(s.cooldownUntil) {
		return false
	}

	s.run()
	s.cooldownUntil = cooldownAfterSuspend(time.Now(), s.suspended())
	return true
}

func isSuspendActive() bool {
	_, err := os.Stat(suspendActiveFile)
	return err == nil
}

// lidAction reports whether a change in the lid runs the suspend script.
// Closing it sleeps a device that is awake, and opening it wakes one the
// fallback suspend has paused. Deep sleep needs nothing on opening, as the
// system suspend script only returns once the lid is open.
func lidAction(wasOpen, isOpen, suspended bool) bool {
	if wasOpen && !isOpen {
		return !suspended
	}
	if !wasOpen && isOpen {
		return suspended
	}
	return false
}

// readLidOpen reports whether the lid is open, and false for ok when the
// device has no lid sensor or it could not be read.
func readLidOpen(path string) (open bool, ok bool) {
	data, err := os.ReadFile(path)
	if err != nil {
		return false, false
	}
	return strings.TrimSpace(string(data)) == "1", true
}

// watchLid suspends and resumes on the lid until the process exits. Only
// changes count, so starting with the lid shut does not sleep, and a change
// that could not be acted on is tried again on the next poll.
func watchLid(path string, s *sleeper) {
	wasOpen, ok := readLidOpen(path)
	if !ok {
		return
	}
	log.Printf("Watching the lid at %s\n", path)

	for {
		time.Sleep(lidPollInterval)

		isOpen, ok := readLidOpen(path)
		if !ok || isOpen == wasOpen {
			continue
		}

		if lidAction(wasOpen, isOpen, s.suspended()) {
			if isOpen {
				log.Println("Lid opened, resuming...")
			} else {
				log.Println("Lid closed, suspending...")
			}
			if !s.suspend() {
				continue
			}
		}
		wasOpen = isOpen
	}
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

	s := &sleeper{
		run:       func() { runScript(suspendScript) },
		suspended: isSuspendActive,
	}
	go watchLid(lidStateFile, s)

	var pressTime time.Time
	var holdTimer *time.Timer

	for {
		event, err := dev.ReadOne()
		if err != nil {
			log.Printf("Failed to read input: %v", err)
			continue
		}

		if !s.listening(time.Now()) {
			// a press the lid's sleep cut short must not turn into a hold
			// that shuts the device down once it wakes
			if holdTimer != nil {
				holdTimer.Stop()
				holdTimer = nil
			}
			pressTime = time.Time{}
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
				s.suspend()
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
