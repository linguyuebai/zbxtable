package model

import (
	stdjson "encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	zabbix "github.com/canghai908/zabbix-go"
)

func TestGetProblemsFromInstance(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var request struct {
			Method string `json:"method"`
			ID     int    `json:"id"`
		}
		if err := stdjson.NewDecoder(r.Body).Decode(&request); err != nil {
			t.Fatalf("decode JSON-RPC request: %v", err)
		}
		w.Header().Set("Content-Type", "application/json")
		switch request.Method {
		case "APIInfo.version":
			_, _ = w.Write([]byte(`{"jsonrpc":"2.0","result":"7.4.0","id":1}`))
		case "problem.get":
			_, _ = w.Write([]byte(`{"jsonrpc":"2.0","result":[{"eventid":"70001","name":"CPU high","severity":"3","acknowledged":"0","clock":"1700000000","objectid":"50001"}],"id":2}`))
		default:
			t.Errorf("unexpected method = %q", request.Method)
			_, _ = w.Write([]byte(`{"jsonrpc":"2.0","result":[],"id":1}`))
		}
	}))
	defer server.Close()

	instance := &APIInstance{API: zabbix.NewAPI(server.URL)}
	problems, total, err := GetProblemsFromInstance(instance)
	if err != nil {
		t.Fatalf("GetProblemsFromInstance() error = %v", err)
	}
	if total != 1 || len(problems) != 1 {
		t.Fatalf("problem count = %d/%d, want 1", total, len(problems))
	}
	if problems[0].Eventid != "70001" || problems[0].Name != "CPU high" {
		t.Fatalf("problem = %+v, want event 70001 named CPU high", problems[0])
	}
}

func TestGetProblemsFromInstanceRejectsUnavailableAPI(t *testing.T) {
	if _, _, err := GetProblemsFromInstance(nil); err == nil {
		t.Fatal("GetProblemsFromInstance(nil) error = nil, want unavailable API error")
	}
	if _, _, err := GetProblemsFromInstance(&APIInstance{}); err == nil {
		t.Fatal("GetProblemsFromInstance with nil client error = nil, want unavailable API error")
	}
}
