//go:build linux

package main

import (
	"fmt"
	"os/exec"
)

func extract(packagePath, destDir string) error {
	terminals := []string{
		"gnome-terminal", // GNOME
		"konsole",        // KDE
		"xfce4-terminal", // XFCE
		"xterm",          // X11
	}

	// Command with auto-close after completion
	command := fmt.Sprintf(`sudo dpkg -i "%s"`, packagePath)

	for _, term := range terminals {
		if _, err := exec.LookPath(term); err == nil {
			var cmd *exec.Cmd
			switch term {
			case "gnome-terminal", "xfce4-terminal":
				cmd = exec.Command(term, "--", "bash", "-c", command)
			case "konsole":
				cmd = exec.Command(term, "-e", "bash", "-c", command)
			case "xterm":
				cmd = exec.Command(term, "-e", command)
			}

			if err := cmd.Start(); err == nil {
				return nil
			}
		}
	}

	return fmt.Errorf("no suitable terminal emulator found. Please install gnome-terminal, konsole, xfce4-terminal or xterm")
}
