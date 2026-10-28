package handler

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"gopkg.in/ini.v1"
)

func TestWriteConfigFilePreservesDatabasePassword(t *testing.T) {
	oldWorkingDirectory, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	tempDirectory := t.TempDir()
	if err := os.Chdir(tempDirectory); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chdir(oldWorkingDirectory) })

	password := "p@ss:/?#%'&=\\!$value"
	if err := writeConfigFile("mysql", "127.0.0.1", "zbx", password, "zbxtable", "3306", "", "prod", "12"); err != nil {
		t.Fatalf("writeConfigFile(): %v", err)
	}
	configPath := filepath.Join(tempDirectory, "config", "app.conf")
	config, err := ini.Load(configPath)
	if err != nil {
		t.Fatalf("ini.Load(): %v", err)
	}
	if got := config.Section("").Key("dbpass").String(); got != password {
		t.Fatalf("configured password = %q, want original password", got)
	}
	if got := config.Section("").Key("dbname").String(); got != "zbxtable" {
		t.Fatalf("configured database = %q, want zbxtable", got)
	}
	if got := config.Section("").Key("httpport").String(); got != "8089" {
		t.Fatalf("configured HTTP port = %q, want 8089", got)
	}
	info, err := os.Stat(configPath)
	if err != nil {
		t.Fatal(err)
	}
	if runtime.GOOS != "windows" && info.Mode().Perm() != 0600 {
		t.Fatalf("config permissions = %04o, want 0600", info.Mode().Perm())
	}
}
