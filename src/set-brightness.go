package main

import (
	"fmt"
	"os"
	"strconv"
	"syscall"
	"unsafe"
)

func setBrightness(value int, isTrimui bool, isRg35xxplus bool, isMiyoomini bool) error {
	// Clamp value
	if value < 0 {
		value = 0
	} else if value > 10 {
		value = 10
	}

	var raw int
	if isTrimui {
		mapTrimui := [11]int{0, 1, 8, 16, 32, 48, 72, 96, 128, 176, 255}
		raw = mapTrimui[value]
		applyBrightnessIoctl(raw)
	} else if isRg35xxplus {
		mapRg35xxplus := [11]int{0, 4, 6, 10, 16, 32, 48, 64, 96, 160, 255}
		raw = mapRg35xxplus[value]
		applyBrightnessIoctl(raw)
	} else if isMiyoomini {
		if value == 0 {
			raw = 6
		} else {
			raw = value * 10
		}
		applyBrightnessFile(raw)
	}

	return nil
}

func applyBrightnessIoctl(val int) error {
	const DISP_LCD_SET_BRIGHTNESS = 0x102
	param := [4]uint64{0, uint64(val), 0, 0}

	fd, err := os.OpenFile("/dev/disp", os.O_RDWR, 0)
	if err != nil {
		fmt.Printf("Error opening /dev/disp: %v\n", err)
		return err
	}
	defer fd.Close()

	_, _, errno := syscall.Syscall(
		syscall.SYS_IOCTL,
		fd.Fd(),
		DISP_LCD_SET_BRIGHTNESS,
		uintptr(unsafe.Pointer(&param[0])),
	)
	if errno != 0 {
		fmt.Printf("Error during ioctl: %v\n", errno)
		return fmt.Errorf("ioctl error: %v", errno)
	}

	return nil
}

func applyBrightnessFile(val int) error {
	file, err := os.OpenFile("/sys/class/pwm/pwmchip0/pwm0/duty_cycle", os.O_WRONLY, 0)
	if err != nil {
		return fmt.Errorf("failed to open duty_cycle: %w", err)
	}
	defer file.Close()

	_, err = fmt.Fprintf(file, "%d", val)
	if err != nil {
		return fmt.Errorf("failed to write brightness: %w", err)
	}
	return nil
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: set-brightness <value 0-10>")
		os.Exit(1)
	}

	val, err := strconv.Atoi(os.Args[1])
	if err != nil || val < 0 || val > 10 {
		fmt.Println("Please provide a brightness value between 0 and 10.")
		os.Exit(1)
	}

	// Set these flags at compile time using -ldflags "-X main.isTrimui=true -X main.isRg35xxplus=false"
	var (
		isTrimui     = false
		isRg35xxplus = false
		isMiyoomini  = false
	)

	if err := setBrightness(val, isTrimui, isRg35xxplus, isMiyoomini); err != nil {
		fmt.Printf("Failed to set brightness: %v\n", err)
		os.Exit(1)
	}
}
