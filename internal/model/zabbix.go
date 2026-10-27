package model

import (
	"errors"
	"fmt"
	"net/url"
	"strings"
	"time"
	"zbxtable/pkg/logger"
	"zbxtable/pkg/utils"

	zabbix "github.com/canghai908/zabbix-go"
	"gorm.io/gorm"
)

// TestZabbixInstanceConfig 测试 Zabbix 配置能否连通
func TestZabbixInstanceConfig(webURL, user, pass, token string) (string, error) {
	web := normalizeZabbixWebURL(webURL)
	if web == "" {
		return "", errors.New("invalid Zabbix URL: use http(s)://host[:port][/path]")
	}
	api := zabbix.NewAPI(web + "/api_jsonrpc.php")
	if strings.TrimSpace(token) != "" {
		if err := api.SetAuth(strings.TrimSpace(token)); err != nil {
			return "", fmt.Errorf("Zabbix API token setup failed: %w", err)
		}
	} else {
		if strings.TrimSpace(user) == "" || strings.TrimSpace(pass) == "" {
			return "", errors.New("provide an API token or a Zabbix username and password")
		}
		if _, err := api.Login(strings.TrimSpace(user), strings.TrimSpace(pass)); err != nil {
			return "", fmt.Errorf("Zabbix login failed: %w", err)
		}
	}
	if err := validateZabbixAPIReadAccess(api); err != nil {
		return "", fmt.Errorf("Zabbix API read permission check failed: %w", err)
	}
	ver, err := zabbixAPIVersion(api)
	if err != nil {
		return "", fmt.Errorf("Zabbix API request failed: %w", err)
	}
	return ver, nil
}

func zabbixAPIVersion(api *zabbix.API) (string, error) {
	if info := api.GetVersionInfo(); info != nil && info.Version != "" {
		return info.Version, nil
	}
	return api.Version()
}
func validateZabbixAPIReadAccess(api *zabbix.API) error {
	_, err := api.CallWithError("host.get", map[string]interface{}{"output": []string{"hostid"}, "limit": 1})
	return err
}
func normalizeZabbixWebURL(raw string) string {
	web := strings.TrimRight(strings.TrimSpace(raw), "/")
	web = strings.TrimSuffix(web, "/api_jsonrpc.php")
	web = strings.TrimRight(web, "/")
	if web == "" {
		return ""
	}
	u, err := url.Parse(web)
	if err != nil || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || (u.Scheme != "http" && u.Scheme != "https") {
		return ""
	}
	return web
}

// DecryptInstanceCredentials 解密 Zabbix 实例的密码和 Token
// 返回解密后的密码和 Token
func DecryptInstanceCredentials(instance *ZabbixInstance) (decryptedPass, decryptedToken string) {
	if instance == nil {
		return "", ""
	}

	encryptionKey := GetEncryptionKey()
	decryptedPass = instance.Pass
	decryptedToken = instance.Token

	// 解密密码
	if decryptedPass != "" {
		pass, err := utils.DecryptString(decryptedPass, encryptionKey)
		if err != nil {
			logger.Log.Errorf("解密密码失败 (实例: %s): %v", instance.Name, err)
		} else {
			decryptedPass = pass
		}
	}

	// 解密 Token
	if decryptedToken != "" {
		token, err := utils.DecryptString(decryptedToken, encryptionKey)
		if err != nil {
			logger.Log.Errorf("解密Token失败 (实例: %s): %v", instance.Name, err)
		} else {
			decryptedToken = token
		}
	}

	return decryptedPass, decryptedToken
}

// ListZabbixInstances 列出所有 Zabbix 实例
func ListZabbixInstance() ([]ZabbixInstance, error) {
	var list []ZabbixInstance
	err := DB.Order("id asc").Find(&list).Error
	return list, err
}

// GetAllZabbixInstances 获取所有 Zabbix 实例（别名方法）
func GetAllZabbixInstances() ([]ZabbixInstance, error) {
	return ListZabbixInstance()
}

// GetZabbixInstanceByZID 根据ZID获取实例
func GetZabbixInstanceByZID(id int) (*ZabbixInstance, error) {
	var instance ZabbixInstance
	err := DB.First(&instance, id).Error
	if err != nil {
		return nil, err
	}
	return &instance, nil
}

// GetZabbixInstanceByInstance 根据 instance 获取实例
func GetZabbixInstanceByInstance(instance string) (*ZabbixInstance, error) {
	iid := strings.TrimSpace(instance)
	if iid == "" {
		return nil, errors.New("instance is empty")
	}
	var inst ZabbixInstance
	err := DB.Where("instance = ?", iid).First(&inst).Error
	if err != nil {
		return nil, err
	}
	return &inst, nil
}

// CreateZabbixInstance creates a Zabbix integration.
func CreateZabbixInstance(m *ZabbixInstance) error {
	m.URL = normalizeZabbixWebURL(m.URL)
	m.Instance = strings.TrimSpace(m.Instance)
	m.Name = strings.TrimSpace(m.Name)
	m.User = strings.TrimSpace(m.User)
	if m.Instance == "" {
		return errors.New("instance is required")
	}
	if m.Name == "" {
		return errors.New("name is required")
	}
	if m.URL == "" {
		return errors.New("URL must be an http(s) Zabbix web address or API endpoint")
	}
	if strings.TrimSpace(m.Token) == "" && (m.User == "" || strings.TrimSpace(m.Pass) == "") {
		return errors.New("provide a Zabbix API token or username and password")
	}
	key := GetEncryptionKey()
	var err error
	if m.Pass != "" {
		m.Pass, err = utils.EncryptString(m.Pass, key)
		if err != nil {
			return fmt.Errorf("encrypt password: %w", err)
		}
	}
	if m.Token != "" {
		m.Token, err = utils.EncryptString(m.Token, key)
		if err != nil {
			return fmt.Errorf("encrypt token: %w", err)
		}
	}
	if m.NotifyMethod == "" {
		m.NotifyMethod = "webhook"
	}
	m.UpdatedAt = time.Now()
	return DB.Create(m).Error
}

// UpdateZabbixInstance updates an integration while preserving omitted credentials.
func UpdateZabbixInstance(zid int, patch *ZabbixInstance) (*ZabbixInstance, error) {
	var cur ZabbixInstance
	if err := DB.First(&cur, zid).Error; err != nil {
		return nil, err
	}
	key := GetEncryptionKey()
	oldPass, oldToken := DecryptInstanceCredentials(&cur)
	urlv := cur.URL
	if strings.TrimSpace(patch.URL) != "" {
		urlv = normalizeZabbixWebURL(patch.URL)
		if urlv == "" {
			return nil, errors.New("URL must be an http(s) Zabbix web address or API endpoint")
		}
	}
	user := strings.TrimSpace(patch.User)
	if user == "" {
		user = cur.User
	}
	pass := strings.TrimSpace(patch.Pass)
	token := strings.TrimSpace(patch.Token)
	if pass == "" && !patch.ClearPass {
		pass = oldPass
	}
	if token == "" && !patch.ClearToken {
		token = oldToken
	}
	if token == "" && (user == "" || pass == "") {
		return nil, errors.New("provide a Zabbix API token or username and password")
	}
	updates := map[string]interface{}{"instance": strings.TrimSpace(patch.Instance), "name": strings.TrimSpace(patch.Name), "url": urlv, "user": user, "enabled": patch.Enabled, "notify_method": patch.NotifyMethod, "updated_at": time.Now()}
	if updates["instance"] == "" {
		updates["instance"] = cur.Instance
	}
	if updates["name"] == "" {
		updates["name"] = cur.Name
	}
	if updates["notify_method"] == "" {
		updates["notify_method"] = cur.NotifyMethod
	}
	var err error
	if pass != "" {
		updates["pass"], err = utils.EncryptString(pass, key)
		if err != nil {
			return nil, err
		}
	} else {
		updates["pass"] = ""
	}
	if token != "" {
		updates["token"], err = utils.EncryptString(token, key)
		if err != nil {
			return nil, err
		}
	} else {
		updates["token"] = ""
	}
	changed := urlv != cur.URL || user != cur.User || pass != oldPass || token != oldToken
	if changed {
		updates["last_test_ok"] = false
		updates["last_test_message"] = "not tested"
		updates["last_test_at"] = nil
		updates["version"] = ""
	}
	if err := DB.Model(&ZabbixInstance{}).Where("id = ?", zid).Updates(updates).Error; err != nil {
		return nil, err
	}
	if changed {
		GetAPIPool().RemoveAPI(zid)
	}
	return GetZabbixInstanceByZID(zid)
}

func DeleteZabbixInstance(zid int) error {
	r := DB.Delete(&ZabbixInstance{}, zid)
	if r.Error != nil {
		return r.Error
	}
	if r.RowsAffected == 0 {
		return gorm.ErrRecordNotFound
	}
	GetAPIPool().RemoveAPI(zid)
	return nil
}

func SetZabbixInstanceEnabled(zid int, enabled bool) (*ZabbixInstance, error) {
	var cur ZabbixInstance
	if err := DB.First(&cur, zid).Error; err != nil {
		return nil, err
	}
	if err := DB.Model(&ZabbixInstance{}).Where("id = ?", zid).Update("enabled", enabled).Error; err != nil {
		return nil, err
	}
	GetAPIPool().RemoveAPI(zid)
	cur.Enabled = enabled
	return &cur, nil
}

// TestAndUpdateZabbixInstance 测试并更新实例
func TestAndUpdateZabbixInstance(zid int) (*ZabbixInstance, string, error) {
	var instance ZabbixInstance
	if err := DB.First(&instance, zid).Error; err != nil {
		return nil, "", err
	}

	// 解密密码和Token
	decryptedPass, decryptedToken := DecryptInstanceCredentials(&instance)

	now := time.Now()
	ver, err := TestZabbixInstanceConfig(instance.URL, instance.User, decryptedPass, decryptedToken)
	if err != nil {
		_ = DB.Model(&ZabbixInstance{}).Where("id = ?", zid).Updates(map[string]interface{}{
			"last_test_ok":      false,
			"last_test_message": err.Error(),
			"last_test_at":      &now,
		}).Error
		instance.LastTestOk = false
		instance.LastTestMessage = err.Error()
		instance.LastTestAt = &now
		return &instance, "", err
	}
	_ = DB.Model(&ZabbixInstance{}).Where("id = ?", zid).Updates(map[string]interface{}{
		"last_test_ok":      true,
		"last_test_message": "连接成功",
		"last_test_at":      &now,
		"version":           ver,
	}).Error
	instance.LastTestOk = true
	instance.LastTestMessage = "连接成功"
	instance.LastTestAt = &now
	instance.Version = ver

	// 测试成功后，清除该实例在 API 池中的缓存
	// 这样可以确保下次使用时会用新的认证信息（token 或账号密码）重新创建连接
	// 特别是当用户从 token 切换到账号密码登录时，需要重新获取 Web cookies
	logger.Log.Infof("测试成功，清除实例 %s (ZID=%d) 的 API 缓存以刷新认证信息", instance.Name, zid)
	GetAPIPool().RemoveAPI(zid)

	return &instance, ver, nil
}

// UninstallMSAgentFromZabbixInstance 从 Zabbix 实例中卸载 MS-Agent 配置
func UninstallMSAgentFromZabbixInstance(zid int) error {
	instance, err := GetZabbixInstanceByZID(zid)
	if err != nil {
		return fmt.Errorf("获取实例失败: %w", err)
	}

	// 解密密码和Token
	decryptedPass, decryptedToken := DecryptInstanceCredentials(instance)
	api := zabbix.NewAPI(instance.URL + "/api_jsonrpc.php")
	if decryptedToken != "" {
		api.Auth = decryptedToken
	} else {
		_, err := api.Login(instance.User, decryptedPass)
		if err != nil {
			return fmt.Errorf("登录 Zabbix 失败: %w", err)
		}
	}
	// 删除 Action
	logger.Log.Info("删除 MS-Agent Action...")
	actionParams := map[string]interface{}{
		"output": []string{"actionid"},
		"filter": map[string]string{"name": MSAction},
	}
	actionRes, err := api.CallWithError("action.get", actionParams)
	if err == nil && actionRes.Result != nil {
		resultArray, ok := actionRes.Result.([]interface{})
		if ok && len(resultArray) > 0 {
			actionMap := resultArray[0].(map[string]interface{})
			actionID := actionMap["actionid"].(string)
			_, _ = api.CallWithError("action.delete", []string{actionID})
			logger.Log.Info("Action 删除成功")
		}
	}

	// 获取并删除用户
	logger.Log.Info("查询 MS-Agent 用户...")
	userParams := map[string]interface{}{
		"output":        []string{"userid"},
		"selectUsrgrps": []string{"usrgrpid"},
		"selectMedias":  []string{"mediatypeid"},
		"filter":        map[string]string{"username": MSUser},
	}
	userRes, err := api.CallWithError("user.get", userParams)
	var usergroupID, mediatypeID string
	if err == nil && userRes.Result != nil {
		resultArray, ok := userRes.Result.([]interface{})
		if ok && len(resultArray) > 0 {
			userMap := resultArray[0].(map[string]interface{})
			userID := userMap["userid"].(string)
			if usrgrps, ok := userMap["usrgrps"].([]interface{}); ok && len(usrgrps) > 0 {
				grpMap := usrgrps[0].(map[string]interface{})
				usergroupID = grpMap["usrgrpid"].(string)
			}
			if medias, ok := userMap["medias"].([]interface{}); ok && len(medias) > 0 {
				mediaMap := medias[0].(map[string]interface{})
				mediatypeID = mediaMap["mediatypeid"].(string)
			}
			_, _ = api.CallWithError("user.delete", []string{userID})
			logger.Log.Info("用户删除成功")
		}
	}

	if usergroupID != "" {
		_, _ = api.CallWithError("usergroup.delete", []string{usergroupID})
		logger.Log.Info("用户组删除成功")
	}
	if mediatypeID != "" {
		_, _ = api.CallWithError("mediatype.delete", []string{mediatypeID})
		logger.Log.Info("Media Type 删除成功")
	}

	_ = DB.Model(&ZabbixInstance{}).Where("id = ?", zid).Updates(map[string]interface{}{
		"ms_agent_installed": false,
		"ms_agent_version":   "",
	}).Error

	logger.Log.Info("MS-Agent 配置卸载完成！")
	return nil
}
