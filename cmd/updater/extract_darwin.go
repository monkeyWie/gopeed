//go:build darwin

package main

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
)

func extract(packagePath, destDir string) error {
	output, err := exec.Command("hdiutil", "attach", packagePath, "-nobrowse", "-quiet").Output()
	if err != nil {
		return err
	}

	mountPoint := ""
	for _, line := range strings.Split(string(output), "\n") {
		if strings.Contains(line, "/Volumes/") {
			fields := strings.Fields(line)
			if len(fields) > 2 {
				mountPoint = fields[len(fields)-1]
				break
			}
		}
	}

	if mountPoint == "" {
		return fmt.Errorf("failed to get mount point")
	}

	matches, err := filepath.Glob(filepath.Join(mountPoint, "*.app"))
	if err != nil {
		return err
	}
	if len(matches) == 0 {
		return fmt.Errorf("no .app found in dmg")
	}

	if err := exec.Command("cp", "-Rf", matches[0], destDir).Run(); err != nil {
		return err
	}

	return exec.Command("hdiutil", "detach", mountPoint, "-quiet").Run()
}
