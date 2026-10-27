package handler

import (
	"strings"
	"testing"
	"time"
)

func TestQueryPeriodDefaultsForIncompleteInput(t *testing.T) {
	start, end, err := queryPeriod([]string{"2026-10-27 10:00:00"}, time.Hour)
	if err != nil || end <= start || end-start < 3590 || end-start > 3610 {
		t.Fatalf("unexpected default period: start=%d end=%d err=%v", start, end, err)
	}
}

func TestQueryPeriodRejectsInvalidRange(t *testing.T) {
	_, _, err := queryPeriod([]string{"bad", "2026-10-27 11:00:00"}, time.Hour)
	if err == nil || !strings.Contains(err.Error(), "开始时间") {
		t.Fatalf("expected invalid start error, got %v", err)
	}
	_, _, err = queryPeriod([]string{"2026-10-27 12:00:00", "2026-10-27 11:00:00"}, time.Hour)
	if err == nil || !strings.Contains(err.Error(), "结束时间不能早于") {
		t.Fatalf("expected reversed range error, got %v", err)
	}
}
