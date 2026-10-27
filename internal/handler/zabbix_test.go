package handler

import (
	"testing"

	"zbxtable/internal/model"
)

func TestParseZabbixInstanceBodyPreservesSettingsAndSelectsAuthMode(t *testing.T) {
	existing := &model.ZabbixInstance{
		Instance:     "production",
		Name:         "Production",
		URL:          "https://zabbix.example",
		User:         "reader",
		Enabled:      true,
		NotifyMethod: "webhook",
	}

	passwordMode := parseZabbixInstanceBody([]byte(`{"auth_type":"password","enabled":true}`), existing)
	if !passwordMode.ClearToken || passwordMode.ClearPass {
		t.Fatalf("password mode should clear only the token: %+v", passwordMode)
	}
	if passwordMode.User != existing.User || passwordMode.NotifyMethod != existing.NotifyMethod || !passwordMode.Enabled {
		t.Fatalf("omitted settings should be preserved: %+v", passwordMode)
	}

	tokenMode := parseZabbixInstanceBody([]byte(`{"auth_type":"token","enabled":false}`), existing)
	if !tokenMode.ClearPass || tokenMode.ClearToken {
		t.Fatalf("token mode should clear only the password: %+v", tokenMode)
	}
	if tokenMode.Enabled {
		t.Fatal("explicit enabled=false must be preserved")
	}
}

func TestParseZabbixInstanceBodyDefaultsEnabledForCreate(t *testing.T) {
	instance := parseZabbixInstanceBody([]byte(`{"instance":"test","name":"test","url":"http://127.0.0.1"}`), nil)
	if !instance.Enabled {
		t.Fatal("new instances should be enabled when enabled is omitted")
	}
}
