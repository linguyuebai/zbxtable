package handler

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestChangePasswordGinAcceptsEmbeddedUIFields(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.POST("/password", ChangePasswordGin)

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/password", strings.NewReader(`{"oldpwd":"old","pwd1":"new","pwd2":"different"}`))
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("HTTP status = %d, want 200", w.Code)
	}
	if !strings.Contains(w.Body.String(), `"code":422`) {
		t.Fatalf("response = %s, want validation error", w.Body.String())
	}
}

func TestChangePasswordGinAcceptsLegacyFields(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.POST("/password", ChangePasswordGin)

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/password", strings.NewReader(`{"old":"old","new":"new","confirm":"new"}`))
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("HTTP status = %d, want 200", w.Code)
	}
	// Parsing passed; without the auth context the handler must stop before
	// touching the database.
	if !strings.Contains(w.Body.String(), `"code":401`) {
		t.Fatalf("response = %s, want unauthorized response", w.Body.String())
	}
}
