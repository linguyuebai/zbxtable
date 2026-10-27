package model

import (
	"testing"
	"time"
)

func TestInspectionPatternCount(t *testing.T) {
	entries := []inspectionLogEntry{{Value: "Failed password for root"}, {Value: "accepted password"}, {Value: "登录失败"}}
	if got := inspectionPatternCount(entries, nil, `failed|登录失败`); got != 2 {
		t.Fatalf("inspectionPatternCount() = %d, want 2", got)
	}
}

func TestInspectionIPAllowed(t *testing.T) {
	if !inspectionIPAllowed("10.0.0.12", []string{"10.0.0.0/24"}) {
		t.Fatal("CIDR should allow the host IP")
	}
	if inspectionIPAllowed("10.0.1.12", []string{"10.0.0.0/24"}) {
		t.Fatal("IP outside the CIDR should be rejected")
	}
	unexpected := inspectionUnexpectedLogIPs([]inspectionLogEntry{{Value: "Failed password from 10.0.1.12"}}, []string{"10.0.0.0/24"})
	if len(unexpected) != 1 || unexpected[0] != "10.0.1.12" {
		t.Fatalf("unexpected log IPs = %v", unexpected)
	}
}

func TestParseInspectionFloat(t *testing.T) {
	if value, ok := parseInspectionFloat(" 85.5% "); !ok || value != 85.5 {
		t.Fatalf("parseInspectionFloat() = %v, %v", value, ok)
	}
}

func TestInspectionUnexpectedAccounts(t *testing.T) {
	entries := []inspectionLogEntry{{Value: "Account Name: Administrator\nIpAddress: 10.0.0.1"}, {Value: "TargetUserName: svc-backup"}}
	accounts := inspectionUnexpectedAccounts(entries, []string{"Administrator"})
	if len(accounts) != 1 || accounts[0] != "svc-backup" {
		t.Fatalf("unexpected accounts = %v", accounts)
	}
}

func TestBuildInspectionSummary(t *testing.T) {
	now := time.Now()
	summary := BuildInspectionSummary([]InspectionResult{
		{Status: "ok", CPUPercent: 20.123, MemoryPercent: 30.123, DiskPercent: 40.123, CheckedAt: now},
		{Status: "warning", CPUPercent: 40.456, MemoryPercent: 50.456, DiskPercent: 60.456, Details: "CPU超阈值;", CheckedAt: now.Add(time.Minute)},
	})
	if summary.Total != 2 || summary.Normal != 1 || summary.Abnormal != 1 || summary.CPUAverage != 30.29 || summary.MemoryAverage != 40.29 || summary.DiskAverage != 50.29 || len(summary.CommonIssues) != 1 {
		t.Fatalf("summary = %+v", summary)
	}
}
