package handler

import (
	"io"
	"net/http"
	"time"
	"zbxtable/internal/model"
	"zbxtable/pkg/response"

	"github.com/gin-gonic/gin"
	jsoniter "github.com/json-iterator/go"
)

// GetHistoryByItemID 获取历史数据
func GetHistoryByItemID(c *gin.Context) {
	body, err := io.ReadAll(c.Request.Body)
	if err != nil {
		response.InternalError(c, "请求体读取失败")
		return
	}

	var v model.HistoryQuery
	var HistoryRes model.HistoryList
	err = jsoniter.Unmarshal(body, &v)
	if err != nil {
		HistoryRes.Code = 500
		HistoryRes.Message = err.Error()
		c.JSON(http.StatusOK, HistoryRes)
		return
	}
	start, end, periodErr := queryPeriod(v.Period, 10*time.Minute)
	if periodErr != nil {
		response.BadRequest(c, periodErr.Error())
		return
	}
	his, err := model.GetHistoryByItemID(v.Itemids, v.History, start, end)
	if err != nil {
		HistoryRes.Code = 500
		HistoryRes.Message = err.Error()
		c.JSON(http.StatusOK, HistoryRes)
		return
	}
	HistoryRes.Code = 200
	HistoryRes.Message = "获取成功"
	HistoryRes.Data.Items = his
	c.JSON(http.StatusOK, HistoryRes)
}
