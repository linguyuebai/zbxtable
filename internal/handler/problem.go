package handler

import (
	"strconv"
	"zbxtable/internal/model"
	"zbxtable/pkg/response"

	"github.com/gin-gonic/gin"
)

// GetAllProblem 获取未恢复告警
func GetAllProblem(c *gin.Context) {
	var b []model.Problems
	var cnt int64
	var err error
	if zid := c.Query("zid"); zid != "" {
		id, parseErr := strconv.Atoi(zid)
		if parseErr != nil || id <= 0 {
			response.BadRequest(c, "无效的 Zabbix 实例 ID")
			return
		}
		inst, apiErr := model.GetAPIByZID(id)
		if apiErr != nil {
			response.InternalError(c, apiErr.Error())
			return
		}
		b, cnt, err = model.GetProblemsFromInstance(inst)
	} else {
		b, cnt, err = model.GetProblems()
	}
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}
	response.SuccessWithPage(c, b, cnt)
}
