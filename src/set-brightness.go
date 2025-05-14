package main

import (
	"fmt"
	"os"
	"strconv"
	"syscall"
	"unsafe"
)

// Platform identifier: set to one of "tg5040", "miyoomini", or "rg35xxplus" at compile time
var (
	platformName string
)

func setBrightness(value int, platformName string) error {
	var raw int
	if platformName == "tg5040" {
		mapTrimui := [11]int{0, 1, 8, 16, 32, 48, 72, 96, 128, 176, 255}
		raw = mapTrimui[value]
		applyBrightnessIoctl(raw)
	} else if platformName == "miyoomini" {
		if value == 0 {
			raw = 6
		} else {
			raw = value * 10
		}
		applybrightnessDevice(raw)
	} else if platformName == "rg35xxplus" {
		mapRg35xxplus := [11]int{0, 4, 6, 10, 16, 32, 48, 64, 96, 160, 255}
		raw = mapRg35xxplus[value]
		applyBrightnessIoctl(raw)
	}

	return nil
}

func applyBrightnessIoctl(val int) error {
	const brightnessDevice = "/dev/disp"
	const brightnessHex = 0x102

	fd, err := os.OpenFile(brightnessDevice, os.O_RDWR, 0)
	if err != nil {
		fmt.Printf("Error opening %s: %v\n", brightnessDevice, err)
		return err
	}
	defer fd.Close()

	param := [4]uint64{0, uint64(val), 0, 0}
	_, _, errno := syscall.Syscall(
		syscall.SYS_IOCTL,
		fd.Fd(),
		brightnessHex,
		uintptr(unsafe.Pointer(&param[0])),
	)
	if errno != 0 {
		fmt.Printf("Failed to set ioctl: %v\n", errno)
		return errno
	}

	return nil
}

func applybrightnessDevice(val int) error {
	const brightnessDevice = "/sys/class/pwm/pwmchip0/pwm0/brightnessDevice"

	file, err := os.OpenFile(brightnessDevice, os.O_WRONLY, 0)
	if err != nil {
		fmt.Errorf("Failed to open %s: %w", brightnessDevice, err)
		return err
	}
	defer file.Close()

	_, err = fmt.Fprintf(file, "%d", val)
	if err != nil {
		fmt.Errorf("Failed to set brightness: %w", err)
		return err
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

	if platformName != "tg5040" && platformName != "miyoomini" && platformName != "rg35xxplus" {
		fmt.Println("Please set platformName to one of 'tg5040', 'miyoomini', or 'rg35xxplus'")
		os.Exit(1)
	}

	if err := setBrightness(val, platformName); err != nil {
		fmt.Printf("Failed to set brightness: %v\n", err)
		os.Exit(1)
	}
}
