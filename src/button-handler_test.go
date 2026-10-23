package main

import "testing"

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
