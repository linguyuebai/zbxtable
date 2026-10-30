package handler

import (
	"crypto/tls"
	"database/sql"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"time"
	"zbxtable/internal/model"
	"zbxtable/pkg/logger"
	"zbxtable/pkg/response"

	"github.com/canghai908/zabbix-go"
	"github.com/gin-gonic/gin"
	mysqlDriver "github.com/go-sql-driver/mysql"
	_ "github.com/lib/pq"
	"gopkg.in/ini.v1"
)

// ZabbixAPIError Zabbix API 错误
type ZabbixAPIError struct {
	Message string
}

func (e *ZabbixAPIError) Error() string {
	return e.Message
}

// checkZabbixAPISafe 安全地检查 Zabbix API（不退出程序）
func checkZabbixAPISafe(address, user, pass, token string) (string, error) {
	// TLS SkipVerify
	transport := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	// 判断API地址是否正确，http get访问api地址判断状态码是不是412
	addURL := address + "/api_jsonrpc.php"
	dClient := http.Client{
		Transport: transport,
		Timeout:   3 * time.Second,
	}
	resp, err := dClient.Get(addURL)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusPreconditionFailed {
		return "", &ZabbixAPIError{Message: "Zabbix API 地址不正确，状态码: " + strconv.Itoa(resp.StatusCode)}
	}
	// api定义
	api := zabbix.NewAPI(addURL)
	if token != "" {
		api.SetAuth(token)
	} else {
		_, err := api.Login(user, pass)
		if err != nil {
			return "", err
		}
	}
	// zabbix api data get test
	outputPar := []string{"hostid", "host", "available", "status", "name", "error"}
	type params map[string]interface{}
	_, err = api.CallWithError("host.get", params{
		"output":  outputPar,
		"hostids": "10084",
	})
	if err != nil {
		return "", err
	}
	// version get
	version, err := api.Version()
	if err != nil {
		return "", err
	}
	return version, nil
}

// checkDatabaseConnection 检查数据库连接
func checkDatabaseConnection(dbdriver, dbhost, dbuser, dbpass, dbname, dbport string) error {
	switch dbdriver {
	case "mysql":
		config := mysqlDriver.Config{
			User: dbuser, Passwd: dbpass, Net: "tcp",
			Addr: net.JoinHostPort(dbhost, dbport), DBName: dbname,
			ParseTime: true, Loc: time.FixedZone("CST", 8*60*60), Timeout: 5 * time.Second,
			Collation: "utf8_general_ci", AllowNativePasswords: true,
			Params: map[string]string{"charset": "utf8"},
		}
		db, err := sql.Open("mysql", config.FormatDSN())
		if err != nil {
			return err
		}
		defer db.Close()
		err = db.Ping()
		if err != nil {
			return err
		}
	case "postgresql":
		connectionURL := url.URL{
			Scheme: "postgres",
			User:   url.UserPassword(dbuser, dbpass),
			Host:   net.JoinHostPort(dbhost, dbport),
			Path:   "/" + dbname,
		}
		query := connectionURL.Query()
		query.Set("sslmode", "disable")
		connectionURL.RawQuery = query.Encode()
		db, err := sql.Open("postgres", connectionURL.String())
		if err != nil {
			return err
		}
		defer db.Close()
		err = db.Ping()
		if err != nil {
			return err
		}
	default:
		return fmt.Errorf("unsupported database type %q", dbdriver)
	}
	return nil
}

const defaultInstallDatabase = "zbxtable_lg"

// databaseExists checks the server without selecting a database. This lets
// the first-run wizard create a dedicated ZbxTable database while leaving the
// existing Zabbix database untouched.
func databaseExists(dbdriver, dbhost, dbuser, dbpass, dbname, dbport string) (bool, error) {
	if dbname == "" {
		return false, nil
	}
	switch dbdriver {
	case "mysql":
		config := mysqlDriver.Config{User: dbuser, Passwd: dbpass, Net: "tcp", Addr: net.JoinHostPort(dbhost, dbport), ParseTime: true, Loc: time.Local, Timeout: 5 * time.Second, AllowNativePasswords: true}
		db, err := sql.Open("mysql", config.FormatDSN())
		if err != nil {
			return false, err
		}
		defer db.Close()
		var found string
		err = db.QueryRow("SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = ?", dbname).Scan(&found)
		if err == sql.ErrNoRows {
			return false, nil
		}
		return err == nil, err
	case "postgresql":
		u := url.URL{Scheme: "postgres", User: url.UserPassword(dbuser, dbpass), Host: net.JoinHostPort(dbhost, dbport), Path: "/postgres"}
		q := u.Query()
		q.Set("sslmode", "disable")
		u.RawQuery = q.Encode()
		db, err := sql.Open("postgres", u.String())
		if err != nil {
			return false, err
		}
		defer db.Close()
		var found string
		err = db.QueryRow("SELECT datname FROM pg_database WHERE datname = $1", dbname).Scan(&found)
		if err == sql.ErrNoRows {
			return false, nil
		}
		return err == nil, err
	default:
		return false, fmt.Errorf("unsupported database type %q", dbdriver)
	}
}

func createDatabase(dbdriver, dbhost, dbuser, dbpass, dbname, dbport string) error {
	if !regexp.MustCompile(`^[A-Za-z0-9_]+$`).MatchString(dbname) {
		return fmt.Errorf("database name must contain only letters, numbers and underscores")
	}
	switch dbdriver {
	case "mysql":
		config := mysqlDriver.Config{User: dbuser, Passwd: dbpass, Net: "tcp", Addr: net.JoinHostPort(dbhost, dbport), ParseTime: true, Loc: time.Local, Timeout: 5 * time.Second, AllowNativePasswords: true}
		db, err := sql.Open("mysql", config.FormatDSN())
		if err != nil {
			return err
		}
		defer db.Close()
		_, err = db.Exec("CREATE DATABASE IF NOT EXISTS `" + dbname + "` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci")
		return err
	case "postgresql":
		u := url.URL{Scheme: "postgres", User: url.UserPassword(dbuser, dbpass), Host: net.JoinHostPort(dbhost, dbport), Path: "/postgres"}
		q := u.Query()
		q.Set("sslmode", "disable")
		u.RawQuery = q.Encode()
		db, err := sql.Open("postgres", u.String())
		if err != nil {
			return err
		}
		defer db.Close()
		_, err = db.Exec(`CREATE DATABASE "` + dbname + `"`)
		if strings.Contains(strings.ToLower(fmt.Sprint(err)), "already exists") {
			return nil
		}
		return err
	default:
		return fmt.Errorf("unsupported database type %q", dbdriver)
	}
}

// writeConfigFile 写入配置文件
func writeConfigFile(
	dbtype, dbhost, dbuser, dbpass, dbname, dbport,
	httpport, runmode, timeout string) error {
	cfg := ini.Empty()
	// zbxtable info
	//cfg.Section("").Key("appname").Comment = "zbxtable"
	// migrate httpport
	if httpport == "" {
		cfg.Section("").NewKey("httpport", "8089")
	} else {
		cfg.Section("").NewKey("httpport", httpport)
	}
	// migrate runmode
	if runmode == "" {
		cfg.Section("").NewKey("runmode", "prod")
	} else {
		cfg.Section("").NewKey("runmode", runmode)
	}
	// migrate timeout
	if timeout == "" {
		cfg.Section("").NewKey("timeout", "12")
	} else {
		cfg.Section("").NewKey("timeout", timeout)
	}
	// logger defaults (copyrequestbody 已废弃，不再写入)
	cfg.Section("").NewKey("log_level", "3")
	cfg.Section("").NewKey("log_path", "log")
	cfg.Section("").NewKey("maxlines", "1000")
	cfg.Section("").NewKey("maxsize", "0")
	cfg.Section("").NewKey("maxdays", "10")
	cfg.Section("").NewKey("daily", "true")
	// database info
	cfg.Section("").Key("dbtype").Comment = "database"
	cfg.Section("").NewKey("dbtype", dbtype)
	cfg.Section("").NewKey("dbhost", dbhost)
	cfg.Section("").NewKey("dbuser", dbuser)
	// Preserve passwords verbatim. Removing apostrophes or shell-like symbols
	// silently changes valid database credentials and makes login fail later.
	cfg.Section("").NewKey("dbpass", dbpass)
	cfg.Section("").NewKey("dbname", dbname)
	cfg.Section("").NewKey("dbport", dbport)
	// zabbix info（安装阶段不再写入，用户可在系统设置里管理多个 Zabbix）
	// check
	confpath := "./config"
	_, err := os.Stat(confpath)
	if err != nil {
		err := os.MkdirAll(confpath, 0755)
		if err != nil {
			return err
		}
	}
	err = cfg.SaveTo("./config/app.conf")
	if err != nil {
		return err
	}
	return os.Chmod("./config/app.conf", 0600)
}

// InstallStatusResponse 安装状态响应
type InstallStatusResponse struct {
	Installed bool `json:"installed"`
}

// GetInstallStatus 获取安装状态
func GetInstallStatus(c *gin.Context) {
	// 检查配置文件是否存在
	confPath := "./config/app.conf"
	_, err := os.Stat(confPath)
	if err != nil {
		response.Success(c, gin.H{
			"installed": false,
		})
		return
	}
	// 检查数据库连接是否配置
	cfg, err := ini.Load(confPath)
	if err != nil {
		response.Success(c, gin.H{
			"installed": false,
		})
		return
	}
	dbtype := cfg.Section("").Key("dbtype").String()
	dbname := cfg.Section("").Key("dbname").String()
	// 检查数据库类型和数据库名
	if dbtype == "" || dbname == "" {
		response.Success(c, gin.H{
			"installed": false,
		})
		return
	}
	// 检查 dbhost
	dbhost := cfg.Section("").Key("dbhost").String()
	if dbhost == "" {
		response.Success(c, gin.H{
			"installed": false,
		})
		return
	}
	// 这里简化处理，实际可以检查特定表是否存在
	response.Success(c, gin.H{
		"installed": true,
	})
}

// CheckDatabaseRequest 数据库检查请求
type CheckDatabaseRequest struct {
	DBType         string `json:"dbtype" binding:"required"`
	DBHost         string `json:"dbhost"`
	DBUser         string `json:"dbuser"`
	DBPass         string `json:"dbpass"`
	DBName         string `json:"dbname"`
	DBPort         string `json:"dbport"`
	CreateDatabase bool   `json:"create_database"`
}

type DatabaseInfoRequest struct {
	DBType string `json:"dbtype" binding:"required"`
	DBHost string `json:"dbhost"`
	DBUser string `json:"dbuser"`
	DBPass string `json:"dbpass"`
	DBPort string `json:"dbport"`
}

// GetDatabaseInfo reports the host OS, reachable database server and likely
// Zabbix database. It never returns passwords and never changes data.
func GetDatabaseInfo(c *gin.Context) {
	var req DatabaseInfoRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误: "+err.Error())
		return
	}
	if req.DBHost == "" || req.DBUser == "" || req.DBPort == "" {
		response.BadRequest(c, "数据库地址、端口和用户不能为空")
		return
	}
	if req.DBType != "mysql" && req.DBType != "postgresql" {
		response.BadRequest(c, "仅支持 MySQL/MariaDB 或 PostgreSQL")
		return
	}
	dbs, err := listDatabases(req.DBType, req.DBHost, req.DBUser, req.DBPass, req.DBPort)
	if err != nil {
		response.InternalError(c, "读取数据库列表失败: "+err.Error())
		return
	}
	zabbix := make([]string, 0)
	for _, name := range dbs {
		lower := strings.ToLower(name)
		if lower == "zabbix" || strings.Contains(lower, "zabbix") {
			zabbix = append(zabbix, name)
		}
	}
	response.Success(c, gin.H{"os": runtime.GOOS, "arch": runtime.GOARCH, "database_type": req.DBType, "databases": dbs, "zabbix_databases": zabbix, "recommended_database": defaultInstallDatabase})
}

func listDatabases(dbdriver, dbhost, dbuser, dbpass, dbport string) ([]string, error) {
	var db *sql.DB
	var err error
	if dbdriver == "mysql" {
		config := mysqlDriver.Config{User: dbuser, Passwd: dbpass, Net: "tcp", Addr: net.JoinHostPort(dbhost, dbport), ParseTime: true, Loc: time.Local, Timeout: 5 * time.Second, AllowNativePasswords: true}
		db, err = sql.Open("mysql", config.FormatDSN())
	} else {
		u := url.URL{Scheme: "postgres", User: url.UserPassword(dbuser, dbpass), Host: net.JoinHostPort(dbhost, dbport), Path: "/postgres"}
		q := u.Query()
		q.Set("sslmode", "disable")
		u.RawQuery = q.Encode()
		db, err = sql.Open("postgres", u.String())
	}
	if err != nil {
		return nil, err
	}
	defer db.Close()
	query := "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA"
	if dbdriver == "postgresql" {
		query = "SELECT datname FROM pg_database WHERE datistemplate = false"
	}
	rows, err := db.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return nil, err
		}
		out = append(out, name)
	}
	return out, rows.Err()
}

// CheckDatabase 检查数据库连接
func CheckDatabase(c *gin.Context) {
	var req CheckDatabaseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误: "+err.Error())
		return
	}

	// 验证必需字段
	if req.DBHost == "" || req.DBUser == "" || req.DBPort == "" {
		response.BadRequest(c, "参数错误：数据库需要 dbhost、dbuser、dbport；dbpass 可以为空")
		return
	}

	if req.DBName == "" {
		req.DBName = defaultInstallDatabase
	}
	created := false
	exists, existsErr := databaseExists(req.DBType, req.DBHost, req.DBUser, req.DBPass, req.DBName, req.DBPort)
	if existsErr != nil {
		response.InternalError(c, "数据库检查失败: "+existsErr.Error())
		return
	}
	if !exists && req.CreateDatabase {
		if err := createDatabase(req.DBType, req.DBHost, req.DBUser, req.DBPass, req.DBName, req.DBPort); err != nil {
			response.InternalError(c, "创建 ZbxTable 数据库失败: "+err.Error())
			return
		}
		created = true
	}
	err := checkDatabaseConnection(req.DBType, req.DBHost, req.DBUser, req.DBPass, req.DBName, req.DBPort)
	if err != nil {
		response.InternalError(c, "数据库连接失败: "+err.Error())
		return
	}

	response.SuccessWithMessage(c, "数据库连接成功", gin.H{
		"success": true, "database": req.DBName, "created": created, "isolated_from_zabbix": strings.ToLower(req.DBName) != "zabbix",
	})
}

// CheckZabbixRequest Zabbix 检查请求（安装不再强制，仅用于后续系统设置里测试连接）
type CheckZabbixRequest struct {
	ZabbixWeb  string `json:"zabbix_web" binding:"required"`
	ZabbixUser string `json:"zabbix_user"`
	ZabbixPass string `json:"zabbix_pass"`
	Token      string `json:"token"`
}

// CheckZabbixAPI 检查 Zabbix API 连接
func CheckZabbixAPI(c *gin.Context) {
	var req CheckZabbixRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误: "+err.Error())
		return
	}

	version, err := checkZabbixAPISafe(req.ZabbixWeb, req.ZabbixUser, req.ZabbixPass, req.Token)
	if err != nil {
		response.InternalError(c, "Zabbix API 连接失败: "+err.Error())
		return
	}

	response.SuccessWithMessage(c, "Zabbix API 连接成功", gin.H{
		"success": true,
		"version": version,
	})
}

// InstallRequest 安装请求
type InstallRequest struct {
	CheckDatabaseRequest
	HTTPPort string `json:"httpport"`
	RunMode  string `json:"runmode"`
	Timeout  string `json:"timeout"`
}

// DoInstall 执行安装
func DoInstall(c *gin.Context) {
	var req InstallRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误: "+err.Error())
		return
	}

	// 验证必需字段
	if req.DBHost == "" || req.DBUser == "" || req.DBPort == "" {
		response.BadRequest(c, "参数错误：数据库需要 dbhost、dbuser、dbport；dbpass 可以为空")
		return
	}
	if req.DBName == "" {
		req.DBName = defaultInstallDatabase
	}

	// 检查是否已安装
	confPath := "./config/app.conf"
	_, err := os.Stat(confPath)
	if err == nil {
		// 配置文件已存在，检查是否已初始化数据库
		cfg, err := ini.Load(confPath)
		if err == nil {
			dbtype := cfg.Section("").Key("dbtype").String()
			if dbtype != "" {
				response.BadRequest(c, "系统已安装，如需重新安装请先删除配置文件")
				return
			}
		}
	}

	// Create the dedicated database automatically when it does not exist. If
	// the operator intentionally selected the existing Zabbix database, leave
	// it untouched and only create the zbxtable_* tables inside it.
	exists, existsErr := databaseExists(req.DBType, req.DBHost, req.DBUser, req.DBPass, req.DBName, req.DBPort)
	if existsErr != nil {
		response.InternalError(c, "数据库检查失败: "+existsErr.Error())
		return
	}
	if !exists {
		if err = createDatabase(req.DBType, req.DBHost, req.DBUser, req.DBPass, req.DBName, req.DBPort); err != nil {
			response.InternalError(c, "创建 ZbxTable 数据库失败，请确认数据库账号具有 CREATE DATABASE 权限: "+err.Error())
			return
		}
	}
	// 再次验证数据库连接
	err = checkDatabaseConnection(req.DBType, req.DBHost, req.DBUser, req.DBPass, req.DBName, req.DBPort)
	if err != nil {
		response.InternalError(c, "数据库连接失败: "+err.Error())
		return
	}

	// 设置默认值
	if req.HTTPPort == "" {
		req.HTTPPort = "8089"
	}
	if req.RunMode == "" {
		req.RunMode = "prod"
	}
	if req.Timeout == "" {
		req.Timeout = "12"
	}

	// 写入配置文件
	err = writeConfigFile(
		req.DBType, req.DBHost, req.DBUser, req.DBPass, req.DBName, req.DBPort,
		req.HTTPPort, req.RunMode, req.Timeout,
	)
	if err != nil {
		response.InternalError(c, "写入配置文件失败: "+err.Error())
		return
	}

	// 初始化数据库
	err = model.ModelInit(
		req.DBType,
		req.DBHost,
		req.DBUser,
		req.DBPass,
		req.DBName,
		req.DBPort)
	if err != nil {
		response.InternalError(c, "数据库初始化失败: "+err.Error())
		return
	}
	logger.Log.Info("配置文件已生成，数据库已初始化")

	// 检查端口是否发生变化
	currentPort := c.Request.Host
	if strings.Contains(currentPort, ":") {
		currentPort = strings.Split(currentPort, ":")[1]
	} else {
		currentPort = "8089" // 默认端口
	}
	portChanged := req.HTTPPort != "" && req.HTTPPort != currentPort

	response.SuccessWithMessage(c, "安装成功！请手动重启程序以加载配置", gin.H{
		"success":                   true,
		"need_restart":              true,
		"port_changed":              portChanged,
		"old_port":                  currentPort,
		"new_port":                  req.HTTPPort,
		"database":                  req.DBName,
		"database_created":          !exists,
		"zabbix_database_unchanged": true,
	})
}
