package model

import "time"

// InspectionPolicy describes which hosts and Zabbix items are checked.
// JSON fields are kept as text so existing MySQL and PostgreSQL installations
// can be upgraded through GORM AutoMigrate without database-specific JSON types.
type InspectionPolicy struct {
	ID              int       `gorm:"column:id;primaryKey;autoIncrement" json:"id"`
	Name            string    `gorm:"column:name;size:255;not null" json:"name"`
	ZID             int       `gorm:"column:zid;index;not null" json:"zid"`
	HostIDs         string    `gorm:"column:host_ids;type:text" json:"host_ids"`
	GroupIDs        string    `gorm:"column:group_ids;type:text" json:"group_ids"`
	ItemKeys        string    `gorm:"column:item_keys;type:text" json:"item_keys"`
	Thresholds      string    `gorm:"column:thresholds;type:text" json:"thresholds"`
	AllowedIPs      string    `gorm:"column:allowed_ips;type:text" json:"allowed_ips"`
	AllowedAccounts string    `gorm:"column:allowed_accounts;type:text" json:"allowed_accounts"`
	LogPatterns     string    `gorm:"column:log_patterns;type:text" json:"log_patterns"`
	Enabled         string    `gorm:"column:enabled;size:10;default:1" json:"enabled"`
	CreatedAt       time.Time `gorm:"column:created_at;autoCreateTime" json:"created_at"`
	UpdatedAt       time.Time `gorm:"column:updated_at;autoUpdateTime" json:"updated_at"`
}

func (InspectionPolicy) TableName() string { return TableName("inspection_policy") }

type InspectionResult struct {
	ID                 int       `gorm:"column:id;primaryKey;autoIncrement" json:"id"`
	PolicyID           int       `gorm:"column:policy_id;index;not null" json:"policy_id"`
	ZID                int       `gorm:"column:zid;index;not null" json:"zid"`
	HostID             string    `gorm:"column:host_id;size:255;index" json:"host_id"`
	HostName           string    `gorm:"column:host_name;size:255" json:"host_name"`
	IP                 string    `gorm:"column:ip;size:255" json:"ip"`
	MemoryTotal        float64   `gorm:"column:memory_total" json:"memory_total"`
	MemoryUsed         float64   `gorm:"column:memory_used" json:"memory_used"`
	MemoryPercent      float64   `gorm:"column:memory_percent" json:"memory_percent"`
	CPUPercent         float64   `gorm:"column:cpu_percent" json:"cpu_percent"`
	DiskPercent        float64   `gorm:"column:disk_percent" json:"disk_percent"`
	DiskFree           float64   `gorm:"column:disk_free" json:"disk_free"`
	TimeOffset         float64   `gorm:"column:time_offset" json:"time_offset"`
	TimeSynced         bool      `gorm:"column:time_synced" json:"time_synced"`
	LoginFailures      int       `gorm:"column:login_failures" json:"login_failures"`
	BruteForce         int       `gorm:"column:brute_force" json:"brute_force"`
	UnexpectedAccounts string    `gorm:"column:unexpected_accounts;type:text" json:"unexpected_accounts"`
	Status             string    `gorm:"column:status;size:20;index" json:"status"`
	Details            string    `gorm:"column:details;type:text" json:"details"`
	CheckedAt          time.Time `gorm:"column:checked_at;index" json:"checked_at"`
}

func (InspectionResult) TableName() string { return TableName("inspection_result") }

type InspectionItemKeys struct {
	CPU         string `json:"cpu"`
	MemoryTotal string `json:"memory_total"`
	MemoryUsed  string `json:"memory_used"`
	MemoryPct   string `json:"memory_percent"`
	DiskPct     string `json:"disk_percent"`
	DiskFree    string `json:"disk_free"`
	DiskMount   string `json:"disk_mount"`
	Time        string `json:"time"`
	LoginLog    string `json:"login_log"`
	BruteForce  string `json:"brute_force_log"`
}

type InspectionThresholds struct {
	CPUPercent    float64 `json:"cpu_percent"`
	MemoryPercent float64 `json:"memory_percent"`
	DiskPercent   float64 `json:"disk_percent"`
	DiskFree      float64 `json:"disk_free"`
	TimeOffset    float64 `json:"time_offset_seconds"`
	LoginFailures int     `json:"login_failures"`
	BruteForce    int     `json:"brute_force"`
	WindowMinutes int     `json:"window_minutes"`
}

// InspectionSummary is the compact, presentation-ready view used by the
// weekly/monthly reports. Values are averages over the selected results; no
// daily rows are exposed in this response.
type InspectionSummary struct {
	Total         int                       `json:"total"`
	Normal        int                       `json:"normal"`
	Abnormal      int                       `json:"abnormal"`
	CPUAverage    float64                   `json:"cpu_average"`
	MemoryAverage float64                   `json:"memory_average"`
	DiskAverage   float64                   `json:"disk_average"`
	LastChecked   time.Time                 `json:"last_checked"`
	CommonIssues  []InspectionIssue         `json:"common_issues"`
	Devices       []InspectionDeviceSummary `json:"devices"`
}

type InspectionIssue struct {
	Name  string `json:"name"`
	Count int    `json:"count"`
}

// InspectionDeviceSummary contains one row per device for weekly/monthly
// reporting. It deliberately contains averages only, so daily samples do not
// appear in a management report.
type InspectionDeviceSummary struct {
	HostID             string    `json:"host_id"`
	HostName           string    `json:"host_name"`
	IP                 string    `json:"ip"`
	Samples            int       `json:"samples"`
	MemoryTotal        float64   `json:"memory_total"`
	MemoryUsed         float64   `json:"memory_used"`
	CPUAverage         float64   `json:"cpu_average"`
	MemoryAverage      float64   `json:"memory_average"`
	DiskAverage        float64   `json:"disk_average"`
	DiskFree           float64   `json:"disk_free"`
	TimeOffset         float64   `json:"time_offset"`
	TimeSynced         bool      `json:"time_synced"`
	LoginFailures      int       `json:"login_failures"`
	BruteForce         int       `json:"brute_force"`
	UnexpectedAccounts string    `json:"unexpected_accounts"`
	Status             string    `json:"status"`
	LastChecked        time.Time `json:"last_checked"`
}

var DefaultInspectionItemKeys = InspectionItemKeys{
	CPU:         "system.cpu.util[,idle]",
	MemoryTotal: "vm.memory.size[total]",
	MemoryUsed:  "vm.memory.size[used]",
	MemoryPct:   "vm.memory.utilization",
	DiskPct:     "vfs.fs.size[/,pused]",
	DiskFree:    "vfs.fs.size[/,free]",
	DiskMount:   "/",
	Time:        "system.localtime",
}

var DefaultInspectionThresholds = InspectionThresholds{
	CPUPercent:    80,
	MemoryPercent: 80,
	DiskPercent:   80,
	DiskFree:      0,
	TimeOffset:    60,
	LoginFailures: 5,
	BruteForce:    1,
	WindowMinutes: 10,
}
