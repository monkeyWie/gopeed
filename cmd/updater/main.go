package main

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"syscall"
	"time"

	"github.com/pkg/browser"
	"github.com/pkg/errors"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Println("Usage: updater <pid> <asset> [log]")
		os.Exit(1)
	}

	if len(os.Args) > 3 {
		logFile, err := os.OpenFile(os.Args[3], os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0666)
		if err == nil {
			defer logFile.Close()
			log.SetOutput(logFile)
		}
	}

	pid, err := strconv.Atoi(os.Args[1])
	if err != nil {
		log.Printf("Invalid PID: %v\n", err)
		os.Exit(1)
	}

	packagePath := os.Args[2]
	if err := update(pid, packagePath); err != nil {
		log.Printf("Update failed: %v\n", err)
		os.Exit(1)
	}

	// Restart the application
	browser.OpenURL("gopeed:///")

	os.Exit(0)
}

func update(pid int, packagePath string) error {
	if err := killProcess(pid); err != nil {
		return errors.Wrap(err, "failed to kill process")
	}

	if err := waitForProcessExit(pid); err != nil {
		return errors.Wrap(err, "failed to wait for process exit")
	}

	appDir := filepath.Dir(os.Args[0])

	if err := extract(packagePath, appDir); err != nil {
		return errors.Wrap(err, "failed to extract package")
	}

	return nil
}

func waitForProcessExit(pid int) error {
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		process, err := os.FindProcess(pid)
		if err != nil {
			// On some systems, error is returned if process doesn't exist
			return nil
		}

		// Send null signal to test if process exists
		err = process.Signal(syscall.Signal(0))
		if err != nil {
			// If error occurs, the process no longer exists
			return nil
		}

		time.Sleep(100 * time.Millisecond)
	}
	return fmt.Errorf("process %d still running after timeout", pid)
}

func killProcess(pid int) error {
	process, err := os.FindProcess(pid)
	if err != nil {
		return err
	}

	return process.Kill()
}
