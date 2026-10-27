package handler

import (
	"fmt"
	"time"
)

// queryPeriod converts the frontend's [start,end] values safely. Malformed or
// incomplete ranges fall back to the endpoint's default lookback window; a
// supplied invalid timestamp is reported instead of silently querying year 1.
func queryPeriod(values []string, fallback time.Duration) (int64, int64, error) {
	now := time.Now()
	if len(values) < 2 || values[0] == "" || values[1] == "" {
		return now.Add(-fallback).Unix(), now.Unix(), nil
	}
	loc, err := time.LoadLocation("Local")
	if err != nil {
		loc = time.Local
	}
	const layout = "2006-01-02 15:04:05"
	start, err := time.ParseInLocation(layout, values[0], loc)
	if err != nil {
		return 0, 0, fmt.Errorf("开始时间格式错误: %w", err)
	}
	end, err := time.ParseInLocation(layout, values[1], loc)
	if err != nil {
		return 0, 0, fmt.Errorf("结束时间格式错误: %w", err)
	}
	if end.Before(start) {
		return 0, 0, fmt.Errorf("结束时间不能早于开始时间")
	}
	return start.Unix(), end.Unix(), nil
}
