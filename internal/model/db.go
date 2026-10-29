package model

import (
	"fmt"
	"net"
	"net/url"
	"time"

	mysqlDriver "github.com/go-sql-driver/mysql"
	"gorm.io/driver/mysql"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

var (
	// DB GORM 数据库实例
	DB *gorm.DB
)

// InitGormDB 初始化 GORM 数据库连接
func InitGormDB(dbtype, dbhost, dbuser, dbpass, dbname, dbport string, runmode string) error {
	var dialector gorm.Dialector
	var err error

	switch dbtype {
	case "mysql":
		// 使用 loc=Local 让数据库使用服务器本地时区
		dialector = mysql.Open(mysqlConfigDSN(dbuser, dbpass, dbhost, dbport, dbname))
	case "postgresql":
		dialector = postgres.Open(postgresConfigDSN(dbuser, dbpass, dbhost, dbport, dbname))
	default:
		// 默认使用 MySQL，使用 loc=Local 让数据库使用服务器本地时区
		dialector = mysql.Open(mysqlConfigDSN(dbuser, dbpass, dbhost, dbport, dbname))
	}

	// 配置日志级别
	logLevel := logger.Silent
	if runmode == "dev" {
		logLevel = logger.Info
	}

	// 打开数据库连接
	DB, err = gorm.Open(dialector, &gorm.Config{
		Logger: logger.Default.LogMode(logLevel),
		NowFunc: func() time.Time {
			return time.Now().Local()
		},
	})
	if err != nil {
		return fmt.Errorf("failed to connect database: %w", err)
	}

	// 获取底层 sql.DB 设置连接池
	sqlDB, err := DB.DB()
	if err != nil {
		return fmt.Errorf("failed to get database instance: %w", err)
	}

	// 设置连接池参数
	sqlDB.SetMaxIdleConns(10)
	sqlDB.SetMaxOpenConns(100)
	sqlDB.SetConnMaxLifetime(time.Hour)

	// 测试连接
	if err = sqlDB.Ping(); err != nil {
		return fmt.Errorf("failed to ping database: %w", err)
	}

	return nil
}

func postgresConfigDSN(user, password, host, port, database string) string {
	connectionURL := url.URL{
		Scheme: "postgres",
		User:   url.UserPassword(user, password),
		Host:   net.JoinHostPort(host, port),
		Path:   "/" + database,
	}
	query := connectionURL.Query()
	query.Set("sslmode", "disable")
	query.Set("TimeZone", "Asia/Shanghai")
	connectionURL.RawQuery = query.Encode()
	return connectionURL.String()
}

func mysqlConfigDSN(user, password, host, port, database string) string {
	config := mysqlDriver.Config{
		User: user, Passwd: password, Net: "tcp",
		Addr: net.JoinHostPort(host, port), DBName: database,
		ParseTime: true, Loc: time.Local, Timeout: 5 * time.Second,
		Collation: "utf8_general_ci",
		// Config is built directly instead of parsed from a DSN, so preserve
		// the driver's default. Otherwise FormatDSN writes
		// allowNativePasswords=false and MariaDB/MySQL native-password users
		// cannot connect.
		AllowNativePasswords: true,
		Params:               map[string]string{"charset": "utf8"},
	}
	return config.FormatDSN()
}

// AutoMigrate 自动迁移数据库表
func AutoMigrate() error {
	// GORM 会自动使用模型的 TableName() 方法（如果存在）
	// 否则使用默认的命名策略（结构体名的复数形式）
	return DB.AutoMigrate(
		&AssetType{},
		&AssetGroup{},
		&Alarm{},
		&User{},
		&Topology{},
		&System{},
		&Report{},
		&Egress{},
		&TaskLog{},
		&Rule{},
		&UserGroup{},
		&EventLog{},
		&Config{},
		&Menu{},
		&ZabbixInstance{},
		&MetricMapping{},
		&MetricMappingHistory{},
		&SystemHistory{},
		&InspectionPolicy{},
		&InspectionResult{},
		//&MappingRule{},
	//&ZabbixInstance{},
	//&ZabbixInstanceBinding{},
	)
}

// GetDB 获取数据库实例
func GetDB() *gorm.DB {
	return DB
}
