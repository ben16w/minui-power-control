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
	powerKeyCode  = 116 // Power button key code
	devicePath    = "/dev/input/event1"
	shortPressMax = 2 * time.Second
	coolDownTime  = 1 * time.Second
)

var (
	binPath, _     = os.Executable()
	rootPath, _    = filepath.Abs(filepath.Dir(filepath.Dir(binPath)))
	suspendScript  = filepath.Join(rootPath, "suspend")
	shutdownScript = filepath.Join(rootPath, "shutdown")
)

func main() {
	dev, err := evdev.Open(devicePath)
	if err != nil {
		log.Fatalf("Failed to open input device: %v", err)
	}
	log.Printf("Listening on device: %s\n", devicePath)

	var pressTime time.Time
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

		if event.Type == evdev.EV_KEY && event.Code == powerKeyCode {
			if event.Value == 0 && !pressTime.IsZero() {
				// Key released
				duration := time.Since(pressTime)
				pressTime = time.Time{} // Reset

				if duration < shortPressMax {
					log.Println("Short press detected, suspending...")
					runScript(suspendScript)
					cooldownUntil = time.Now().Add(coolDownTime)
				}
			} else if event.Value == 1 {
				// Key pressed
				pressTime = time.Now()
			} else if event.Value == 2 {
				// Key held down
				duration := time.Since(pressTime)
				if duration >= shortPressMax {
					log.Println("Button held down for 2 seconds, shutting down...")
					runScript(shutdownScript)
					cooldownUntil = time.Now().Add(coolDownTime)
				}
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
