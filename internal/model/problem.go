package model

import (
	"fmt"
	"zbxtable/pkg/logger"
)

// ProblemsRes rest
type ProblemsRes struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Data    struct {
		Items []Problems `json:"items"`
		Total int64      `json:"total"`
	} `json:"data"`
}

// Problems struct
type Problems struct {
	Acknowledged  string `json:"acknowledged"`
	Clock         string `json:"clock"`
	Correlationid string `json:"correlationid"`
	Eventid       string `json:"eventid"`
	Name          string `json:"name"`
	Objectid      string `json:"objectid"`
	Severity      string `json:"severity"`
}

// GetProblems get porblems
func GetProblems() ([]Problems, int64, error) {
	instances, err := GetAllEnabledAPIInstances()
	if err != nil {
		logger.Log.Error(err)
		return []Problems{}, 0, err
	}
	allProblems := make([]Problems, 0)
	for _, inst := range instances {
		problems, _, callErr := GetProblemsFromInstance(inst)
		if callErr != nil {
			logger.Log.Errorf("从实例 %s 获取未恢复告警失败: %v", inst.Name, callErr)
			continue
		}
		allProblems = append(allProblems, problems...)
	}
	return allProblems, int64(len(allProblems)), nil
}

// GetProblemsFromInstance returns active problems from the selected Zabbix instance.
func GetProblemsFromInstance(inst *APIInstance) ([]Problems, int64, error) {
	if inst == nil || inst.API == nil {
		return []Problems{}, 0, fmt.Errorf("Zabbix instance API is unavailable")
	}
	par := []string{"eventid"}
	problems, err := inst.API.CallWithError("problem.get", Params{"output": "extend",
		"sortfield": par,
		"sortorder": "DESC"})
	if err != nil {
		return []Problems{}, 0, err
	}
	hba, err := json.Marshal(problems.Result)
	if err != nil {
		logger.Log.Error(err)
		return []Problems{}, 0, err
	}
	var hb []Problems
	err = json.Unmarshal(hba, &hb)
	if err != nil {
		logger.Log.Error(err)
		return []Problems{}, 0, err
	}
	return hb, int64(len(hb)), err
}
