package handler

import (
	"zbxtable/internal/model"
	"zbxtable/pkg/response"

	"github.com/gin-gonic/gin"
)

// GetTemplateList returns templates from the selected or default Zabbix instance.
func GetTemplateList(c *gin.Context) {
	list, err := model.TemplateListGetFromInstance(c.Query("zid"))
	if err != nil {
		response.InternalError(c, "获取模板失败: "+err.Error())
		return
	}
	response.Success(c, list)
}

// GetItemByTemplateID returns monitoring items for a template.
func GetItemByTemplateID(c *gin.Context) {
	list, err := model.TemplateByItemFromInstance(c.Query("zid"), c.Param("templateid"))
	if err != nil {
		response.InternalError(c, "获取模板监控项失败: "+err.Error())
		return
	}
	response.Success(c, list)
}
