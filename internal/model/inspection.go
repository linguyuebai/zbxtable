package model

import (
	"bytes"
	"encoding/json"
	"fmt"
	"math"
	"net"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/xuri/excelize/v2"
	"zbxtable/pkg/logger"
)

type inspectionItemValue struct {
	Itemid    string `json:"itemid"`
	Key       string `json:"key_"`
	Name      string `json:"name"`
	Lastvalue string `json:"lastvalue"`
	Lastclock string `json:"lastclock"`
	Units     string `json:"units"`
}

type inspectionLogEntry struct {
	Clock string `json:"clock"`
	Value string `json:"value"`
}

func decodeInspectionConfig(p InspectionPolicy) (InspectionItemKeys, InspectionThresholds, []string, []string, []string, error) {
	keys := DefaultInspectionItemKeys
	thresholds := DefaultInspectionThresholds
	if strings.TrimSpace(p.ItemKeys) != "" {
		if err := json.Unmarshal([]byte(p.ItemKeys), &keys); err != nil {
			return keys, thresholds, nil, nil, nil, fmt.Errorf("item_keys 格式错误: %w", err)
		}
	}
	if strings.TrimSpace(p.Thresholds) != "" {
		if err := json.Unmarshal([]byte(p.Thresholds), &thresholds); err != nil {
			return keys, thresholds, nil, nil, nil, fmt.Errorf("thresholds 格式错误: %w", err)
		}
	}
	var allowed, accounts, patterns []string
	if strings.TrimSpace(p.AllowedIPs) != "" {
		if err := json.Unmarshal([]byte(p.AllowedIPs), &allowed); err != nil {
			allowed = splitInspectionIDs(p.AllowedIPs)
		}
	}
	if strings.TrimSpace(p.AllowedAccounts) != "" {
		if err := json.Unmarshal([]byte(p.AllowedAccounts), &accounts); err != nil {
			accounts = splitInspectionIDs(p.AllowedAccounts)
		}
	}
	if strings.TrimSpace(p.LogPatterns) != "" {
		if err := json.Unmarshal([]byte(p.LogPatterns), &patterns); err != nil {
			patterns = splitInspectionIDs(p.LogPatterns)
		}
	}
	if thresholds.WindowMinutes <= 0 {
		thresholds.WindowMinutes = DefaultInspectionThresholds.WindowMinutes
	}
	if thresholds.TimeOffset <= 0 {
		thresholds.TimeOffset = DefaultInspectionThresholds.TimeOffset
	}
	return keys, thresholds, allowed, accounts, patterns, nil
}

func splitInspectionIDs(raw string) []string {
	parts := strings.FieldsFunc(raw, func(r rune) bool { return r == ',' || r == ' ' || r == '\n' || r == '\t' })
	result := make([]string, 0, len(parts))
	for _, part := range parts {
		if strings.TrimSpace(part) != "" {
			result = append(result, strings.TrimSpace(part))
		}
	}
	return result
}

func parseInspectionFloat(value string) (float64, bool) {
	value = strings.TrimSpace(strings.TrimSuffix(value, "%"))
	n, err := strconv.ParseFloat(value, 64)
	return n, err == nil && !math.IsNaN(n) && !math.IsInf(n, 0)
}

func (p *InspectionPolicy) hosts(inst *APIInstance) ([]Hosts, error) {
	if ids := splitInspectionIDs(p.HostIDs); len(ids) > 0 {
		all, err := SearchHostFromInstance(inst, "")
		if err != nil {
			return nil, err
		}
		wanted := make(map[string]bool, len(ids))
		for _, id := range ids {
			wanted[id] = true
		}
		result := make([]Hosts, 0, len(ids))
		for _, host := range all {
			if wanted[host.HostID] {
				result = append(result, host)
			}
		}
		return result, nil
	}
	if groups := splitInspectionIDs(p.GroupIDs); len(groups) > 0 {
		return GetHostsByGroupIDsFromInstance(inst, groups)
	}
	return SearchHostFromInstance(inst, "")
}

func getInspectionItem(inst *APIInstance, hostID, key string) (*inspectionItemValue, error) {
	if strings.TrimSpace(key) == "" {
		return nil, nil
	}
	rep, err := inst.API.CallWithError("item.get", Params{
		"output":  []string{"itemid", "key_", "name", "lastvalue", "lastclock", "units"},
		"hostids": hostID, "filter": map[string]string{"key_": key}, "limit": 1,
	})
	if err != nil {
		return nil, err
	}
	data, err := json.Marshal(rep.Result)
	if err != nil {
		return nil, err
	}
	var items []inspectionItemValue
	if err := json.Unmarshal(data, &items); err != nil {
		return nil, err
	}
	if len(items) == 0 {
		return nil, nil
	}
	return &items[0], nil
}

func inspectionValue(inst *APIInstance, hostID string, keys ...string) (float64, bool, error) {
	for _, key := range keys {
		item, err := getInspectionItem(inst, hostID, key)
		if err != nil {
			return 0, false, err
		}
		if item == nil {
			continue
		}
		if value, ok := parseInspectionFloat(item.Lastvalue); ok {
			return value, true, nil
		}
	}
	return 0, false, nil
}

func inspectionLogs(inst *APIInstance, hostID, key string, minutes int) ([]inspectionLogEntry, error) {
	item, err := getInspectionItem(inst, hostID, key)
	if err != nil || item == nil {
		return nil, err
	}
	from := time.Now().Add(-time.Duration(minutes) * time.Minute).Unix()
	var entries []inspectionLogEntry
	for _, historyType := range []int{2, 1, 4} {
		rep, callErr := inst.API.CallWithError("history.get", Params{
			"output": "extend", "history": historyType, "itemids": []string{item.Itemid},
			"time_from": from, "sortfield": "clock", "sortorder": "DESC", "limit": 1000,
		})
		if callErr != nil {
			continue
		}
		data, marshalErr := json.Marshal(rep.Result)
		if marshalErr != nil {
			continue
		}
		var candidate []inspectionLogEntry
		if json.Unmarshal(data, &candidate) == nil && len(candidate) > len(entries) {
			entries = candidate
		}
	}
	return entries, nil
}

func inspectionPatternCount(entries []inspectionLogEntry, patterns []string, fallback string) int {
	if len(patterns) == 0 {
		patterns = []string{fallback}
	}
	count := 0
	for _, entry := range entries {
		for _, pattern := range patterns {
			if pattern == "" {
				continue
			}
			matched, err := regexp.MatchString("(?i)"+pattern, entry.Value)
			if err == nil && matched {
				count++
				break
			}
		}
	}
	return count
}

func inspectionIPAllowed(ip string, allowed []string) bool {
	if len(allowed) == 0 {
		return true
	}
	parsed := net.ParseIP(strings.TrimSpace(ip))
	for _, raw := range allowed {
		raw = strings.TrimSpace(raw)
		if raw == "" {
			continue
		}
		if raw == ip {
			return true
		}
		if _, network, err := net.ParseCIDR(raw); err == nil && parsed != nil && network.Contains(parsed) {
			return true
		}
	}
	return false
}

func inspectionUnexpectedLogIPs(entries []inspectionLogEntry, allowed []string) []string {
	if len(allowed) == 0 {
		return nil
	}
	pattern := regexp.MustCompile(`\b(?:\d{1,3}\.){3}\d{1,3}\b`)
	seen := make(map[string]bool)
	result := make([]string, 0)
	for _, entry := range entries {
		for _, ip := range pattern.FindAllString(entry.Value, -1) {
			if !inspectionIPAllowed(ip, allowed) && !seen[ip] {
				seen[ip] = true
				result = append(result, ip)
			}
		}
	}
	return result
}

// inspectionUnexpectedAccounts extracts the account fields emitted by
// Windows Security event logs and common Linux auth log formats. Values such
// as '-', SYSTEM and ANONYMOUS LOGON are ignored because they are placeholders
// rather than user accounts.
func inspectionUnexpectedAccounts(entries []inspectionLogEntry, allowed []string) []string {
	allowedSet := make(map[string]bool, len(allowed))
	for _, account := range allowed {
		allowedSet[strings.ToLower(strings.TrimSpace(account))] = true
	}
	field := regexp.MustCompile(`(?im)(?:account\s*name|targetusername|target user name|user(?:name)?)[\s:=]+([^\r\n,;]+)`)
	result := make([]string, 0)
	seen := make(map[string]bool)
	for _, entry := range entries {
		for _, match := range field.FindAllStringSubmatch(entry.Value, -1) {
			if len(match) < 2 {
				continue
			}
			account := strings.TrimSpace(match[1])
			account = strings.Trim(account, `"'`)
			if account == "" || account == "-" || strings.EqualFold(account, "system") || strings.EqualFold(account, "anonymous logon") {
				continue
			}
			key := strings.ToLower(account)
			if len(allowedSet) > 0 && allowedSet[key] {
				continue
			}
			if !seen[key] {
				seen[key] = true
				result = append(result, account)
			}
		}
	}
	return result
}

func inspectionTimeOffset(inst *APIInstance, hostID, key string) (float64, bool, error) {
	value, ok, err := inspectionValue(inst, hostID, key)
	if err != nil || !ok {
		return 0, false, err
	}
	if value > 1000000000 {
		return math.Abs(float64(time.Now().Unix()) - value), true, nil
	}
	return math.Abs(value), true, nil
}

func collectInspectionResult(policy InspectionPolicy, inst *APIInstance, host Hosts, keys InspectionItemKeys, thresholds InspectionThresholds, allowed, accounts, patterns []string) (InspectionResult, error) {
	result := InspectionResult{PolicyID: policy.ID, ZID: policy.ZID, HostID: host.HostID, HostName: host.Name, IP: host.Interfaces, CheckedAt: time.Now(), Status: "ok"}
	cpu, cpuOK, err := inspectionValue(inst, host.HostID, keys.CPU)
	if err != nil {
		return result, err
	}
	if cpuOK && strings.Contains(keys.CPU, "idle") {
		cpu = 100 - cpu
	}
	result.CPUPercent = math.Max(0, math.Min(100, cpu))
	memTotal, _, err := inspectionValue(inst, host.HostID, keys.MemoryTotal)
	if err != nil {
		return result, err
	}
	memUsed, memUsedOK, err := inspectionValue(inst, host.HostID, keys.MemoryUsed)
	if err != nil {
		return result, err
	}
	if !memUsedOK {
		// Older Zabbix templates expose available memory instead of used memory.
		available, availableOK, availableErr := inspectionValue(inst, host.HostID, "vm.memory.size[available]")
		if availableErr != nil {
			return result, availableErr
		}
		if availableOK && memTotal > available {
			memUsed, memUsedOK = memTotal-available, true
		}
	}
	memPct, memPctOK, err := inspectionValue(inst, host.HostID, keys.MemoryPct)
	if err != nil {
		return result, err
	}
	result.MemoryTotal, result.MemoryUsed = memTotal, memUsed
	if !memPctOK && memUsedOK && memTotal > 0 {
		memPct = memUsed / memTotal * 100
		memPctOK = true
	}
	if memPctOK {
		result.MemoryPercent = math.Max(0, math.Min(100, memPct))
	}
	diskPct, _, err := inspectionValue(inst, host.HostID, keys.DiskPct)
	if err != nil {
		return result, err
	}
	diskFree, _, err := inspectionValue(inst, host.HostID, keys.DiskFree)
	if err != nil {
		return result, err
	}
	result.DiskPercent, result.DiskFree = diskPct, diskFree
	offset, timeOK, err := inspectionTimeOffset(inst, host.HostID, keys.Time)
	if err != nil {
		return result, err
	}
	result.TimeOffset, result.TimeSynced = offset, timeOK && offset <= thresholds.TimeOffset
	if !timeOK {
		result.Status = "warning"
		result.Details += "时间同步检测项缺失;"
	} else if !result.TimeSynced {
		result.Status = "warning"
		result.Details += fmt.Sprintf("时间偏差 %.0f 秒;", offset)
	}
	if result.CPUPercent > thresholds.CPUPercent {
		result.Status = "warning"
		result.Details += "CPU超阈值;"
	}
	if memPctOK && result.MemoryPercent > thresholds.MemoryPercent {
		result.Status = "warning"
		result.Details += "内存超阈值;"
	}
	if result.DiskPercent > thresholds.DiskPercent {
		result.Status = "warning"
		result.Details += "磁盘超阈值;"
	}
	if thresholds.DiskFree > 0 && result.DiskFree < thresholds.DiskFree {
		result.Status = "warning"
		result.Details += "磁盘剩余容量不足;"
	}
	loginEntries, err := inspectionLogs(inst, host.HostID, keys.LoginLog, thresholds.WindowMinutes)
	if err != nil {
		return result, err
	}
	if unexpected := inspectionUnexpectedLogIPs(loginEntries, allowed); len(unexpected) > 0 {
		result.Status = "warning"
		result.Details += "非常用登录IP: " + strings.Join(unexpected, ",") + ";"
	}
	if unexpected := inspectionUnexpectedAccounts(loginEntries, accounts); len(unexpected) > 0 {
		result.Status = "warning"
		result.UnexpectedAccounts = strings.Join(unexpected, ",")
		result.Details += "异常账号: " + result.UnexpectedAccounts + ";"
	}
	result.LoginFailures = inspectionPatternCount(loginEntries, patterns, `failed|failure|authentication failure|登录失败`)
	bruteEntries, err := inspectionLogs(inst, host.HostID, keys.BruteForce, thresholds.WindowMinutes)
	if err != nil {
		return result, err
	}
	if keys.BruteForce == "" {
		bruteEntries = loginEntries
	}
	result.BruteForce = inspectionPatternCount(bruteEntries, nil, `brute|暴力破解|too many attempts`)
	if thresholds.LoginFailures > 0 && result.LoginFailures >= thresholds.LoginFailures {
		result.Status = "warning"
		result.Details += "登录失败次数过多;"
	}
	if thresholds.BruteForce > 0 && result.BruteForce >= thresholds.BruteForce {
		result.Status = "warning"
		result.Details += "检测到暴力破解;"
	}
	return result, nil
}

func saveInspectionResult(result *InspectionResult) error {
	return DB.Create(result).Error
}

func emitInspectionAlerts(policy InspectionPolicy, result InspectionResult) {
	if result.Status == "ok" {
		return
	}
	alertMessage := "巡检异常[" + policy.Name + "]"
	// A short deduplication window prevents each scheduled inspection from
	// producing an identical notification on every run.
	var previous int64
	DB.Model(&Alarm{}).Where("zid = ? AND host_id = ? AND hkey = ? AND message = ? AND occurtime > ?", result.ZID, result.HostID, "inspection", alertMessage, time.Now().Add(-30*time.Minute)).Count(&previous)
	if previous > 0 {
		return
	}
	alarm := &Alarm{ZID: result.ZID, HostID: result.HostID, Hostname: result.HostName, Host: result.HostName, HostsIP: result.IP,
		OccurTime: result.CheckedAt, Level: "4", Message: alertMessage, Hkey: "inspection", Status: "1", Detail: result.Details}
	if _, err := AddAlarm(alarm); err == nil {
		GenAlert(alarm)
	} else {
		logger.Log.Error("保存巡检告警失败:", err)
	}
}

// RunInspectionPolicy executes a policy immediately and persists one result per host.
func RunInspectionPolicy(policyID int) ([]InspectionResult, error) {
	var policy InspectionPolicy
	if err := DB.First(&policy, policyID).Error; err != nil {
		return nil, err
	}
	inst, err := GetAPIByZID(policy.ZID)
	if err != nil {
		return nil, err
	}
	keys, thresholds, allowed, accounts, patterns, err := decodeInspectionConfig(policy)
	if err != nil {
		return nil, err
	}
	hosts, err := policy.hosts(inst)
	if err != nil {
		return nil, err
	}
	results := make([]InspectionResult, 0, len(hosts))
	for _, host := range hosts {
		result, collectErr := collectInspectionResult(policy, inst, host, keys, thresholds, allowed, accounts, patterns)
		if collectErr != nil {
			return results, collectErr
		}
		if err := saveInspectionResult(&result); err != nil {
			return results, err
		}
		emitInspectionAlerts(policy, result)
		results = append(results, result)
	}
	return results, nil
}

// RunScheduledInspections executes all enabled policies. It is intentionally
// best-effort so one unavailable Zabbix host does not stop other policies.
func RunScheduledInspections() error {
	var policies []InspectionPolicy
	if err := DB.Where("enabled = ?", "1").Find(&policies).Error; err != nil {
		return err
	}
	for _, policy := range policies {
		if _, err := RunInspectionPolicy(policy.ID); err != nil {
			logger.Log.Errorf("巡检策略[%d]执行失败: %v", policy.ID, err)
		}
	}
	return nil
}

func GetInspectionResults(policyID, page, limit int, status string) (int64, []InspectionResult, error) {
	if page < 1 {
		page = 1
	}
	if limit < 1 || limit > 500 {
		limit = 50
	}
	query := DB.Model(&InspectionResult{}).Where("policy_id = ?", policyID)
	if status != "" {
		query = query.Where("status = ?", status)
	}
	var total int64
	if err := query.Count(&total).Error; err != nil {
		return 0, nil, err
	}
	var rows []InspectionResult
	err := query.Order("checked_at DESC").Offset((page - 1) * limit).Limit(limit).Find(&rows).Error
	return total, rows, err
}

func BuildInspectionSummary(rows []InspectionResult) InspectionSummary {
	summary := InspectionSummary{Total: len(rows)}
	issueCounts := make(map[string]int)
	var cpu, memory, disk float64
	for _, row := range rows {
		if row.Status == "ok" {
			summary.Normal++
		} else {
			summary.Abnormal++
		}
		cpu += row.CPUPercent
		memory += row.MemoryPercent
		disk += row.DiskPercent
		if row.CheckedAt.After(summary.LastChecked) {
			summary.LastChecked = row.CheckedAt
		}
		for _, issue := range strings.Split(row.Details, ";") {
			issue = strings.TrimSpace(issue)
			if issue == "" {
				continue
			}
			// Remove volatile values so the summary groups the same reason.
			if idx := strings.Index(issue, ":"); idx > 0 {
				issue = strings.TrimSpace(issue[:idx])
			}
			issueCounts[issue]++
		}
	}
	if summary.Total > 0 {
		summary.CPUAverage = cpu / float64(summary.Total)
		summary.MemoryAverage = memory / float64(summary.Total)
		summary.DiskAverage = disk / float64(summary.Total)
	}
	for name, count := range issueCounts {
		summary.CommonIssues = append(summary.CommonIssues, InspectionIssue{Name: name, Count: count})
	}
	sort.Slice(summary.CommonIssues, func(i, j int) bool { return summary.CommonIssues[i].Count > summary.CommonIssues[j].Count })
	if len(summary.CommonIssues) > 10 {
		summary.CommonIssues = summary.CommonIssues[:10]
	}
	summary.Devices = BuildInspectionDeviceSummaries(rows)
	return summary
}

func BuildInspectionDeviceSummaries(rows []InspectionResult) []InspectionDeviceSummary {
	type accumulator struct {
		InspectionDeviceSummary
		cpu, memory, disk float64
		timeSyncedCount   int
	}
	byHost := make(map[string]*accumulator)
	for _, row := range rows {
		key := row.HostID
		if key == "" {
			key = row.HostName + "|" + row.IP
		}
		item := byHost[key]
		if item == nil {
			item = &accumulator{InspectionDeviceSummary: InspectionDeviceSummary{HostID: row.HostID, HostName: row.HostName, IP: row.IP, Status: "ok"}}
			byHost[key] = item
		}
		item.Samples++
		item.cpu += row.CPUPercent
		item.memory += row.MemoryPercent
		item.disk += row.DiskPercent
		if row.TimeSynced {
			item.timeSyncedCount++
		}
		if row.Status != "ok" {
			item.Status = "warning"
		}
		if row.CheckedAt.After(item.LastChecked) {
			item.LastChecked = row.CheckedAt
		}
	}
	result := make([]InspectionDeviceSummary, 0, len(byHost))
	for _, item := range byHost {
		if item.Samples > 0 {
			item.CPUAverage = item.cpu / float64(item.Samples)
			item.MemoryAverage = item.memory / float64(item.Samples)
			item.DiskAverage = item.disk / float64(item.Samples)
			item.TimeSynced = item.timeSyncedCount == item.Samples
		}
		result = append(result, item.InspectionDeviceSummary)
	}
	sort.Slice(result, func(i, j int) bool { return result[i].HostName < result[j].HostName })
	return result
}

func GetInspectionSummary(policyID int, start, end time.Time) (InspectionSummary, error) {
	query := DB.Model(&InspectionResult{}).Where("policy_id = ?", policyID)
	if !start.IsZero() {
		query = query.Where("checked_at >= ?", start)
	}
	if !end.IsZero() {
		query = query.Where("checked_at <= ?", end)
	}
	var rows []InspectionResult
	if err := query.Order("checked_at DESC").Limit(100000).Find(&rows).Error; err != nil {
		return InspectionSummary{}, err
	}
	return BuildInspectionSummary(rows), nil
}

func ExportInspectionResults(rows []InspectionResult) ([]byte, error) {
	return ExportInspectionReport(rows, true)
}

// ExportInspectionReport creates a management report. By default callers can
// omit daily samples and receive only the summary and one average row per
// device; includeDetails is available for audit exports.
func ExportInspectionReport(rows []InspectionResult, includeDetails bool) ([]byte, error) {
	xlsx := excelize.NewFile()
	summarySheet := "巡检汇总"
	deviceSheet := "设备平均"
	sheet := "巡检明细"
	if includeDetails {
		xlsx.SetSheetName("Sheet1", sheet)
		xlsx.NewSheet(summarySheet)
	} else {
		xlsx.SetSheetName("Sheet1", summarySheet)
	}
	xlsx.NewSheet(deviceSheet)
	summary := BuildInspectionSummary(rows)
	deviceRows := BuildInspectionDeviceSummaries(rows)
	for i, value := range []interface{}{"巡检汇总报告", "设备总数", summary.Total, "正常数", summary.Normal, "异常数", summary.Abnormal, "CPU平均占用(%)", summary.CPUAverage, "内存平均占用(%)", summary.MemoryAverage, "磁盘平均占用(%)", summary.DiskAverage, "最近检查时间", summary.LastChecked.Format("2006-01-02 15:04:05")} {
		cell, _ := excelize.CoordinatesToCellName(i+1, 1)
		xlsx.SetCellValue(summarySheet, cell, value)
	}
	xlsx.SetCellValue(summarySheet, "A3", "常见异常原因")
	xlsx.SetCellValue(summarySheet, "B3", "次数")
	for i, issue := range summary.CommonIssues {
		xlsx.SetCellValue(summarySheet, fmt.Sprintf("A%d", i+4), issue.Name)
		xlsx.SetCellValue(summarySheet, fmt.Sprintf("B%d", i+4), issue.Count)
	}
	deviceHeaders := []string{"主机ID", "主机名称", "IP", "样本数", "CPU平均(%)", "内存平均(%)", "磁盘平均(%)", "时间同步", "状态", "最近检查时间"}
	for i, header := range deviceHeaders {
		cell, _ := excelize.CoordinatesToCellName(i+1, 1)
		xlsx.SetCellValue(deviceSheet, cell, header)
	}
	for rowIndex, row := range deviceRows {
		values := []interface{}{row.HostID, row.HostName, row.IP, row.Samples, row.CPUAverage, row.MemoryAverage, row.DiskAverage, row.TimeSynced, row.Status, row.LastChecked.Format("2006-01-02 15:04:05")}
		for col, value := range values {
			cell, _ := excelize.CoordinatesToCellName(col+1, rowIndex+2)
			xlsx.SetCellValue(deviceSheet, cell, value)
		}
	}
	if includeDetails {
		headers := []string{"检查时间", "实例", "主机ID", "主机名称", "IP", "内存总量(bytes)", "内存已用(bytes)", "内存占用(%)", "CPU占用(%)", "磁盘占用(%)", "磁盘剩余(bytes)", "时间偏差(s)", "时间同步", "登录失败", "暴力破解", "异常账号", "状态", "详情"}
		for i, header := range headers {
			cell, _ := excelize.CoordinatesToCellName(i+1, 1)
			xlsx.SetCellValue(sheet, cell, header)
		}
		for rowIndex, row := range rows {
			values := []interface{}{row.CheckedAt.Format("2006-01-02 15:04:05"), row.ZID, row.HostID, row.HostName, row.IP, row.MemoryTotal, row.MemoryUsed, row.MemoryPercent, row.CPUPercent, row.DiskPercent, row.DiskFree, row.TimeOffset, row.TimeSynced, row.LoginFailures, row.BruteForce, row.UnexpectedAccounts, row.Status, row.Details}
			for col, value := range values {
				cell, _ := excelize.CoordinatesToCellName(col+1, rowIndex+2)
				xlsx.SetCellValue(sheet, cell, value)
			}
		}
	}
	style, err := xlsx.NewStyle(&excelize.Style{Font: &excelize.Font{Bold: true}})
	if err == nil {
		if includeDetails {
			_ = xlsx.SetCellStyle(sheet, "A1", "R1", style)
		}
		_ = xlsx.SetCellStyle(summarySheet, "A1", "O1", style)
		_ = xlsx.SetCellStyle(summarySheet, "A3", "B3", style)
		_ = xlsx.SetCellStyle(deviceSheet, "A1", "J1", style)
	}
	if len(rows) > 0 {
		// 所有容量、百分比和时间偏差字段统一以两位小数显示。
		decimalStyle, styleErr := xlsx.NewStyle(&excelize.Style{NumFmt: 2})
		if styleErr == nil {
			if includeDetails {
				_ = xlsx.SetCellStyle(sheet, "F2", "L"+strconv.Itoa(len(rows)+1), decimalStyle)
			}
			_ = xlsx.SetCellStyle(summarySheet, "H1", "L1", decimalStyle)
			if len(deviceRows) > 0 {
				_ = xlsx.SetCellStyle(deviceSheet, "E2", "G"+strconv.Itoa(len(deviceRows)+1), decimalStyle)
			}
		}
	}
	var buf bytes.Buffer
	if err := xlsx.Write(&buf); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}
