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
	if root.Header().Get("Cache-Control") == "" || !strings.Contains(root.Header().Get("Cache-Control"), "no-store") {
		t.Fatalf("GET / Cache-Control = %q, want no-store", root.Header().Get("Cache-Control"))
	}

	script := regexp.MustCompile(`src=["']([^"']+\.js)["']`).FindStringSubmatch(root.Body.String())
	if len(script) < 2 {
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

	missingAsset := httptest.NewRecorder()
	router.ServeHTTP(missingAsset, httptest.NewRequest("GET", "/js/missing-asset.js", nil))
	if missingAsset.Code != 404 {
		t.Fatalf("missing JavaScript asset status = %d, want 404", missingAsset.Code)
	}
	if strings.Contains(strings.ToLower(missingAsset.Body.String()), "<html") {
		t.Fatal("missing JavaScript asset incorrectly returned the SPA document")
	}
}

func TestServiceWorkerIsServedWithoutBrowserCache(t *testing.T) {
	router := InitRouter()
	response := httptest.NewRecorder()
	router.ServeHTTP(response, httptest.NewRequest("GET", "/service-worker.js", nil))
	if response.Code != 200 {
		t.Fatalf("GET /service-worker.js status = %d, want 200", response.Code)
	}
	if response.Header().Get("Cache-Control") == "" || !strings.Contains(response.Header().Get("Cache-Control"), "no-store") {
		t.Fatalf("service worker Cache-Control = %q, want no-store", response.Header().Get("Cache-Control"))
	}
}

func TestInstallPageIsServedByBrowserRoute(t *testing.T) {
	router := InitRouter()
	page := httptest.NewRecorder()
	router.ServeHTTP(page, httptest.NewRequest("GET", "/install", nil))
	if page.Code != 200 {
		t.Fatalf("GET /install status = %d, want 200", page.Code)
	}
	if !strings.Contains(strings.ToLower(page.Body.String()), "<!doctype") {
		t.Fatal("GET /install did not return the embedded HTML document")
	}

	status := httptest.NewRecorder()
	router.ServeHTTP(status, httptest.NewRequest("GET", "/install/status", nil))
	if status.Code != 200 {
		t.Fatalf("GET /install/status status = %d, want 200", status.Code)
	}
}

func TestManagerInfoEndpointIsRegisteredAndProtected(t *testing.T) {
	router := InitRouter()
	response := httptest.NewRecorder()
	request := httptest.NewRequest("POST", "/v1/manager/info", strings.NewReader(`{}`))
	router.ServeHTTP(response, request)
	if response.Code != 401 {
		t.Fatalf("POST /v1/manager/info HTTP status = %d, want 401", response.Code)
	}
	if !strings.Contains(response.Body.String(), `"code":50014`) {
		t.Fatalf("POST /v1/manager/info response = %s, want authentication error (not 404)", response.Body.String())
	}
}

func TestLoginEndpointIsRegistered(t *testing.T) {
	router := InitRouter()
	response := httptest.NewRecorder()
	request := httptest.NewRequest("POST", "/v1/login", strings.NewReader(`{invalid-json`))
	router.ServeHTTP(response, request)
	if response.Code != 200 || !strings.Contains(response.Body.String(), `"code":400`) {
		t.Fatalf("POST /v1/login was not routed to the login handler: HTTP %d: %s", response.Code, response.Body.String())
	}
}
