package model

import (
	stdjson "encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestNormalizeZabbixWebURL(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{" https://zabbix.example/zabbix/ ", "https://zabbix.example/zabbix"},
		{"https://zabbix.example/zabbix/api_jsonrpc.php", "https://zabbix.example/zabbix"},
		{"http://127.0.0.1:8080", "http://127.0.0.1:8080"},
		{"zabbix.example", ""},
		{"ftp://zabbix.example", ""},
		{"https://user:pass@zabbix.example", ""},
		{"https://zabbix.example/zabbix?view=1", ""},
	}
	for _, test := range tests {
		if got := normalizeZabbixWebURL(test.input); got != test.want {
			t.Errorf("normalizeZabbixWebURL(%q) = %q, want %q", test.input, got, test.want)
		}
	}
}

func TestTestZabbixInstanceConfigUsesJSONRPCWithoutGETProbe(t *testing.T) {
	var methods []string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Errorf("request method = %s, want POST", r.Method)
		}
		if r.URL.Path != "/zabbix/api_jsonrpc.php" {
			http.NotFound(w, r)
			return
		}
		var request struct {
			Method string `json:"method"`
		}
		if err := stdjson.NewDecoder(r.Body).Decode(&request); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		methods = append(methods, request.Method)
		w.Header().Set("Content-Type", "application/json")
		switch request.Method {
		case "APIInfo.version":
			_, _ = w.Write([]byte(`{"jsonrpc":"2.0","result":"7.4.0","id":1}`))
		case "user.login":
			_, _ = w.Write([]byte(`{"jsonrpc":"2.0","result":"api-token","id":1}`))
		case "host.get":
			_, _ = w.Write([]byte(`{"jsonrpc":"2.0","result":[],"id":1}`))
		default:
			http.Error(w, "unexpected method", http.StatusBadRequest)
		}
	}))
	defer server.Close()

	version, err := TestZabbixInstanceConfig(server.URL+"/zabbix/api_jsonrpc.php", "Admin", "secret", "")
	if err != nil {
		t.Fatalf("TestZabbixInstanceConfig() error = %v", err)
	}
	if version != "7.4.0" {
		t.Fatalf("version = %q, want 7.4.0", version)
	}
	if len(methods) != 3 || methods[0] != "APIInfo.version" || methods[1] != "user.login" || methods[2] != "host.get" {
		t.Fatalf("JSON-RPC methods = %v, want APIInfo.version, user.login, host.get", methods)
	}
}

func TestTestZabbixInstanceConfigValidatesTokenPermissions(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var request struct {
			Method string `json:"method"`
		}
		if err := stdjson.NewDecoder(r.Body).Decode(&request); err != nil {
			t.Errorf("decode JSON-RPC request: %v", err)
		}
		w.Header().Set("Content-Type", "application/json")
		switch request.Method {
		case "APIInfo.version":
			_, _ = w.Write([]byte(`{"jsonrpc":"2.0","result":"7.4.0","id":1}`))
		case "host.get":
			_, _ = w.Write([]byte(`{"jsonrpc":"2.0","error":{"code":-32602,"message":"Invalid params.","data":"Not authorized."},"id":2}`))
		default:
			t.Errorf("unexpected JSON-RPC method: %s", request.Method)
		}
	}))
	defer server.Close()

	_, err := TestZabbixInstanceConfig(server.URL, "", "", "invalid-token")
	if err == nil || !strings.Contains(err.Error(), "Not authorized") {
		t.Fatalf("error = %v, want unauthorized-token error", err)
	}
}

func TestTestZabbixInstanceConfigReturnsActionableAuthenticationError(t *testing.T) {
	_, err := TestZabbixInstanceConfig("https://zabbix.example", "", "", "")
	if err == nil || !strings.Contains(err.Error(), "username and password") {
		t.Fatalf("error = %v, want missing-credentials guidance", err)
	}
}
