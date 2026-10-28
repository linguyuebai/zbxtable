package model

import (
	"net/url"
	"testing"

	mysqlDriver "github.com/go-sql-driver/mysql"
)

func TestTableNameUsesZbxTablePrefix(t *testing.T) {
	for _, name := range []string{"user", "config", "inspection_policy", "zabbix"} {
		if got, want := TableName(name), "zbxtable_"+name; got != want {
			t.Fatalf("TableName(%q) = %q, want %q", name, got, want)
		}
	}
}

func TestMySQLConfigDSNPreservesCredentialsAndIPv6(t *testing.T) {
	password := "p@ss:/?#%'&=\\value"
	dsn := mysqlConfigDSN("zbxtable", password, "2001:db8::1", "3306", "zabbix")
	config, err := mysqlDriver.ParseDSN(dsn)
	if err != nil {
		t.Fatalf("ParseDSN(%q): %v", dsn, err)
	}
	if config.Passwd != password {
		t.Fatalf("parsed password = %q, want original value", config.Passwd)
	}
	if config.Addr != "[2001:db8::1]:3306" {
		t.Fatalf("parsed address = %q, want IPv6 host and port", config.Addr)
	}
	if config.DBName != "zabbix" {
		t.Fatalf("parsed database = %q, want zabbix", config.DBName)
	}
}

func TestPostgresConfigDSNEncodesCredentialsAndIPv6(t *testing.T) {
	password := "p@ss:/?#%'&=\\value"
	dsn := postgresConfigDSN("zbxtable user", password, "2001:db8::1", "5432", "zabbix db")
	parsed, err := url.Parse(dsn)
	if err != nil {
		t.Fatalf("url.Parse(%q): %v", dsn, err)
	}
	parsedPassword, ok := parsed.User.Password()
	if !ok || parsedPassword != password {
		t.Fatalf("parsed password = %q, want original value", parsedPassword)
	}
	if parsed.Host != "[2001:db8::1]:5432" || parsed.Path != "/zabbix db" {
		t.Fatalf("parsed host/path = %q/%q, want IPv6 host and escaped database path", parsed.Host, parsed.Path)
	}
}
