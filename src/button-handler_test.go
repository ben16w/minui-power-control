package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestDefaultPowerDevice(t *testing.T) {
	tests := map[string]string{
		"h700":       "/dev/input/event0",
		"tg5050":     "/dev/input/event2",
		"my355":      "/dev/input/event2",
		"tg5040":     "/dev/input/event1",
		"rg35xxplus": "/dev/input/event1",
		"miyoomini":  "/dev/input/event1",
	}

	for platform, want := range tests {
		if got := defaultPowerDevice(platform); got != want {
			t.Errorf("defaultPowerDevice(%q) = %q, want %q", platform, got, want)
		}
	}
}

func TestFindPowerDevice(t *testing.T) {
	candidates := []string{"/dev/input/event0", "/dev/input/event1", "/dev/input/event2"}

	tests := []struct {
		name      string
		preferred string
		powerKeys map[string]bool
		want      string
		wantErr   bool
	}{
		{
			name:      "the platform's usual device reports a power key",
			preferred: "/dev/input/event1",
			powerKeys: map[string]bool{"/dev/input/event0": true, "/dev/input/event1": true},
			want:      "/dev/input/event1",
		},
		{
			// h700 before it had a default of its own: event1 is the gamepad
			name:      "the usual device has no power key",
			preferred: "/dev/input/event1",
			powerKeys: map[string]bool{"/dev/input/event0": true},
			want:      "/dev/input/event0",
		},
		{
			name:      "the usual device does not exist",
			preferred: "/dev/input/event5",
			powerKeys: map[string]bool{"/dev/input/event2": true},
			want:      "/dev/input/event2",
		},
		{
			name:      "no device reports a power key",
			preferred: "/dev/input/event1",
			powerKeys: map[string]bool{},
			wantErr:   true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			hasPowerKey := func(path string) bool { return tt.powerKeys[path] }

			got, err := findPowerDevice(tt.preferred, candidates, hasPowerKey)
			if tt.wantErr {
				if err == nil {
					t.Fatalf("findPowerDevice() = %q, want an error", got)
				}
				return
			}
			if err != nil {
				t.Fatalf("findPowerDevice() returned %v", err)
			}
			if got != tt.want {
				t.Errorf("findPowerDevice() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestIsPowerKey(t *testing.T) {
	if !isPowerKey(116) {
		t.Error("KEY_POWER (116) is not treated as the power key")
	}
	if !isPowerKey(102) {
		t.Error("102, which some stacks report the power key as, is not treated as the power key")
	}
	if isPowerKey(115) {
		t.Error("KEY_VOLUMEUP (115) is treated as the power key")
	}
}

func TestCooldownAfterSuspend(t *testing.T) {
	now := time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)

	if got := cooldownAfterSuspend(now, false); !got.Equal(now.Add(3 * time.Second)) {
		t.Errorf("after deep sleep presses are ignored until %v, want %v", got, now.Add(3*time.Second))
	}
	if got := cooldownAfterSuspend(now, true); !got.Equal(now) {
		t.Errorf("while paused without sleep presses are ignored until %v, want them listened to at once", got)
	}
}

func TestLidAction(t *testing.T) {
	tests := []struct {
		name      string
		wasOpen   bool
		isOpen    bool
		suspended bool
		want      bool
	}{
		{"closing the lid sleeps an awake device", true, false, false, true},
		{"closing the lid leaves a paused device asleep", true, false, true, false},
		{"opening the lid wakes a paused device", false, true, true, true},
		{"opening the lid after deep sleep does nothing", false, true, false, false},
		{"an open lid that stays open does nothing", true, true, false, false},
		{"a closed lid that stays closed does nothing", false, false, false, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := lidAction(tt.wasOpen, tt.isOpen, tt.suspended); got != tt.want {
				t.Errorf("lidAction(%v, %v, %v) = %v, want %v", tt.wasOpen, tt.isOpen, tt.suspended, got, tt.want)
			}
		})
	}
}

func TestReadLidOpen(t *testing.T) {
	dir := t.TempDir()

	if _, ok := readLidOpen(filepath.Join(dir, "missing")); ok {
		t.Error("a device without a lid sensor was read as having one")
	}

	path := filepath.Join(dir, "hallvalue")
	for value, want := range map[string]bool{"1\n": true, "0\n": false, "1": true} {
		if err := os.WriteFile(path, []byte(value), 0o644); err != nil {
			t.Fatal(err)
		}
		open, ok := readLidOpen(path)
		if !ok || open != want {
			t.Errorf("readLidOpen(%q) = %v, %v, want %v, true", value, open, ok, want)
		}
	}
}

func TestWatchLidReturnsWithoutASensor(t *testing.T) {
	s := &sleeper{
		run:       func() { t.Error("suspend ran on a device without a lid sensor") },
		suspended: func() bool { return false },
	}

	done := make(chan struct{})
	go func() {
		watchLid(filepath.Join(t.TempDir(), "missing"), s)
		close(done)
	}()

	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("watchLid kept polling a lid sensor that does not exist")
	}
}

func TestSleeperDropsRequestsWhileRunning(t *testing.T) {
	runs := 0
	release := make(chan struct{})
	started := make(chan struct{})
	s := &sleeper{
		run: func() {
			runs++
			if runs == 1 {
				close(started)
				<-release
			}
		},
		suspended: func() bool { return true },
	}

	go s.suspend()
	<-started

	if s.listening(time.Now()) {
		t.Error("power key events are listened to while the suspend script runs")
	}
	if s.suspend() {
		t.Error("a second suspend ran while the first was still running")
	}

	close(release)
	deadline := time.Now().Add(time.Second)
	for !s.listening(time.Now()) {
		if time.Now().After(deadline) {
			t.Fatal("power key events are still ignored after the suspend script finished")
		}
		time.Sleep(10 * time.Millisecond)
	}
	if runs != 1 {
		t.Errorf("the suspend script ran %d times, want 1", runs)
	}
}

func TestSleeperIgnoresRequestsUntilTheDeviceHasWoken(t *testing.T) {
	runs := 0
	s := &sleeper{
		run:       func() { runs++ },
		suspended: func() bool { return false },
	}

	if !s.suspend() {
		t.Fatal("the first suspend did not run")
	}
	if s.suspend() {
		t.Error("a suspend ran while the device was still waking from deep sleep")
	}
	if s.listening(time.Now()) {
		t.Error("power key events are listened to while the device is still waking")
	}
	if !s.listening(time.Now().Add(coolDownTime)) {
		t.Error("power key events are still ignored once the cooldown is over")
	}
	if runs != 1 {
		t.Errorf("the suspend script ran %d times, want 1", runs)
	}
}
