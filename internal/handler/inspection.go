package handler

import (
	stdjson "encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"
	"zbxtable/internal/model"
	"zbxtable/pkg/response"

	"github.com/gin-gonic/gin"
)

type inspectionPolicyRequest struct {
	Name            string             `json:"name"`
	ZID             int                `json:"zid"`
	HostIDs         stdjson.RawMessage `json:"host_ids"`
	GroupIDs        stdjson.RawMessage `json:"group_ids"`
	ItemKeys        stdjson.RawMessage `json:"item_keys"`
	Thresholds      stdjson.RawMessage `json:"thresholds"`
	AllowedIPs      stdjson.RawMessage `json:"allowed_ips"`
	AllowedAccounts stdjson.RawMessage `json:"allowed_accounts"`
	LogPatterns     stdjson.RawMessage `json:"log_patterns"`
	Enabled         string             `json:"enabled"`
}

func inspectionJSON(raw stdjson.RawMessage) (string, error) {
	if len(raw) == 0 || string(raw) == "null" {
		return "", nil
	}
	var value interface{}
	if err := stdjson.Unmarshal(raw, &value); err != nil {
		return "", err
	}
	switch typed := value.(type) {
	case string:
		return typed, nil
	case []interface{}:
		parts := make([]string, 0, len(typed))
		for _, item := range typed {
			parts = append(parts, fmt.Sprint(item))
		}
		return strings.Join(parts, ","), nil
	default:
		data, err := stdjson.Marshal(value)
		return string(data), err
	}
}

func inspectionPolicyFromRequest(req inspectionPolicyRequest, id int) (model.InspectionPolicy, error) {
	hostIDs, err := inspectionJSON(req.HostIDs)
	if err != nil {
		return model.InspectionPolicy{}, err
	}
	groupIDs, err := inspectionJSON(req.GroupIDs)
	if err != nil {
		return model.InspectionPolicy{}, err
	}
	itemKeys, err := inspectionJSON(req.ItemKeys)
	if err != nil {
		return model.InspectionPolicy{}, err
	}
	thresholds, err := inspectionJSON(req.Thresholds)
	if err != nil {
		return model.InspectionPolicy{}, err
	}
	allowedIPs, err := inspectionJSON(req.AllowedIPs)
	if err != nil {
		return model.InspectionPolicy{}, err
	}
	allowedAccounts, err := inspectionJSON(req.AllowedAccounts)
	if err != nil {
		return model.InspectionPolicy{}, err
	}
	patterns, err := inspectionJSON(req.LogPatterns)
	if err != nil {
		return model.InspectionPolicy{}, err
	}
	enabled := req.Enabled
	if enabled == "" {
		enabled = "1"
	}
	return model.InspectionPolicy{ID: id, Name: strings.TrimSpace(req.Name), ZID: req.ZID, HostIDs: hostIDs, GroupIDs: groupIDs, ItemKeys: itemKeys, Thresholds: thresholds, AllowedIPs: allowedIPs, AllowedAccounts: allowedAccounts, LogPatterns: patterns, Enabled: enabled}, nil
}

// GetInspectionPolicies lists configurable inspection policies.
func GetInspectionPolicies(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	query := model.DB.Model(&model.InspectionPolicy{})
	if name := c.Query("name"); name != "" {
		query = query.Where("name LIKE ?", "%"+name+"%")
	}
	if zid := c.Query("zid"); zid != "" {
		query = query.Where("zid = ?", zid)
	}
	var total int64
	if err := query.Count(&total).Error; err != nil {
		response.DatabaseError(c, err.Error())
		return
	}
	var rows []model.InspectionPolicy
	if page < 1 {
		page = 1
	}
	if limit < 1 || limit > 200 {
		limit = 20
	}
	if err := query.Order("updated_at DESC").Offset((page - 1) * limit).Limit(limit).Find(&rows).Error; err != nil {
		response.DatabaseError(c, err.Error())
		return
	}
	response.SuccessWithPage(c, rows, total)
}

func GetInspectionPolicy(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	var policy model.InspectionPolicy
	if err := model.DB.First(&policy, id).Error; err != nil {
		response.NotFound(c, "巡检策略不存在")
		return
	}
	response.Success(c, policy)
}

func CreateInspectionPolicy(c *gin.Context) {
	var req inspectionPolicyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "请求参数格式错误: "+err.Error())
		return
	}
	if strings.TrimSpace(req.Name) == "" || req.ZID <= 0 {
		response.ValidationError(c, "名称和 Zabbix 实例不能为空")
		return
	}
	policy, err := inspectionPolicyFromRequest(req, 0)
	if err != nil {
		response.BadRequest(c, err.Error())
		return
	}
	if err := model.DB.Create(&policy).Error; err != nil {
		response.DatabaseError(c, err.Error())
		return
	}
	response.SuccessWithMessage(c, "创建成功", policy)
}

func UpdateInspectionPolicy(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	var req inspectionPolicyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "请求参数格式错误: "+err.Error())
		return
	}
	policy, err := inspectionPolicyFromRequest(req, id)
	if err != nil {
		response.BadRequest(c, err.Error())
		return
	}
	if err := model.DB.Model(&model.InspectionPolicy{}).Where("id = ?", id).Updates(map[string]interface{}{
		"name": policy.Name, "zid": policy.ZID, "host_ids": policy.HostIDs, "group_ids": policy.GroupIDs,
		"item_keys": policy.ItemKeys, "thresholds": policy.Thresholds, "allowed_ips": policy.AllowedIPs,
		"allowed_accounts": policy.AllowedAccounts, "log_patterns": policy.LogPatterns, "enabled": policy.Enabled, "updated_at": time.Now(),
	}).Error; err != nil {
		response.DatabaseError(c, err.Error())
		return
	}
	response.SuccessWithMessage(c, "保存成功", policy)
}

func DeleteInspectionPolicy(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	if err := model.DB.Delete(&model.InspectionPolicy{}, id).Error; err != nil {
		response.DatabaseError(c, err.Error())
		return
	}
	response.SuccessWithMessage(c, "删除成功", nil)
}

func RunInspection(c *gin.Context) {
	var body struct {
		ID int `json:"id"`
	}
	if err := c.ShouldBindJSON(&body); err != nil || body.ID <= 0 {
		response.ValidationError(c, "id 不能为空")
		return
	}
	rows, err := model.RunInspectionPolicy(body.ID)
	if err != nil {
		response.InternalError(c, "巡检执行失败: "+err.Error())
		return
	}
	response.SuccessWithMessage(c, "巡检完成", rows)
}

func GetInspectionResults(c *gin.Context) {
	policyID, _ := strconv.Atoi(c.Param("id"))
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	total, rows, err := model.GetInspectionResults(policyID, page, limit, c.Query("status"))
	if err != nil {
		response.DatabaseError(c, err.Error())
		return
	}
	response.SuccessWithPage(c, rows, total)
}

// GetInspectionSummary returns an aggregated weekly/monthly style report.
// Optional start/end query values are RFC3339 timestamps. The aggregation is
// done in Go so it behaves identically on MySQL, MariaDB and PostgreSQL.
func GetInspectionSummary(c *gin.Context) {
	policyID, _ := strconv.Atoi(c.Param("id"))
	var start, end time.Time
	var err error
	if raw := c.Query("start"); raw != "" {
		start, err = time.Parse(time.RFC3339, raw)
		if err != nil {
			response.BadRequest(c, "start 必须是 RFC3339 时间")
			return
		}
	}
	if raw := c.Query("end"); raw != "" {
		end, err = time.Parse(time.RFC3339, raw)
		if err != nil {
			response.BadRequest(c, "end 必须是 RFC3339 时间")
			return
		}
	}
	summary, err := model.GetInspectionSummary(policyID, start, end)
	if err != nil {
		response.DatabaseError(c, err.Error())
		return
	}
	response.Success(c, summary)
}

func ExportInspection(c *gin.Context) {
	var body struct {
		PolicyID       int    `json:"policy_id"`
		Status         string `json:"status"`
		IncludeDetails *bool  `json:"include_details"`
		Start          string `json:"start"`
		End            string `json:"end"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		response.BadRequest(c, "请求参数格式错误")
		return
	}
	query := model.DB.Model(&model.InspectionResult{}).Order("checked_at DESC").Limit(10000)
	if body.PolicyID > 0 {
		query = query.Where("policy_id = ?", body.PolicyID)
	}
	if body.Status != "" {
		query = query.Where("status = ?", body.Status)
	}
	if body.Start != "" {
		start, err := time.Parse(time.RFC3339, body.Start)
		if err != nil {
			response.BadRequest(c, "start 必须是 RFC3339 时间")
			return
		}
		query = query.Where("checked_at >= ?", start)
	}
	if body.End != "" {
		end, err := time.Parse(time.RFC3339, body.End)
		if err != nil {
			response.BadRequest(c, "end 必须是 RFC3339 时间")
			return
		}
		query = query.Where("checked_at <= ?", end)
	}
	var rows []model.InspectionResult
	if err := query.Find(&rows).Error; err != nil {
		response.DatabaseError(c, err.Error())
		return
	}
	// 管理报表默认只显示汇总和每台设备的周期平均值；需要审计明细时
	// 显式传 include_details=true。这样周报/月报不会展开每天的数值。
	includeDetails := false
	if body.IncludeDetails != nil {
		includeDetails = *body.IncludeDetails
	}
	data, err := model.ExportInspectionReport(rows, includeDetails)
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}
	c.Header("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
	c.Header("Content-Disposition", "attachment; filename=inspection-results.xlsx")
	c.Header("Access-Control-Expose-Headers", "Content-Disposition")
	c.Data(http.StatusOK, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", data)
}
