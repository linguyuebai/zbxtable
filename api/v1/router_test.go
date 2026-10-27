package v1

import (
	"io"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"
)

func TestEmbeddedFrontendJavaScriptIsServed(t *testing.T) {
	router := InitRouter()
	root := httptest.NewRecorder()
	router.ServeHTTP(root, httptest.NewRequest("GET", "/", nil))
	if root.Code != 200 {
		t.Fatalf("GET / status = %d, want 200", root.Code)
	}

	script := regexp.MustCompile(`src=["']([^"']+\.js)["']`).FindStringSubmatch(root.Body.String())
	if len(script) != 2 {
		t.Fatal("index.html does not contain a JavaScript entrypoint")
	}
	asset := httptest.NewRecorder()
	router.ServeHTTP(asset, httptest.NewRequest("GET", script[1], nil))
	if asset.Code != 200 {
		t.Fatalf("GET %s status = %d, want 200", script[1], asset.Code)
	}
	body, err := io.ReadAll(asset.Body)
	if err != nil {
		t.Fatalf("read JavaScript response: %v", err)
	}
	if len(body) == 0 || strings.Contains(strings.ToLower(string(body)), "<html") {
		t.Fatalf("JavaScript asset returned empty content or HTML fallback")
	}
}
