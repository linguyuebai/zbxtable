package v1

import (
	_ "embed"
	"io"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"
)

//go:embed testdata/official-v3.0.6-routes.txt
var officialV306RouteContract string

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

	checks := []struct {
		name    string
		pattern *regexp.Regexp
	}{
		{name: "JavaScript entrypoint", pattern: regexp.MustCompile(`src=["']([^"']+\.js)["']`)},
		{name: "stylesheet", pattern: regexp.MustCompile(`href=["']([^"']+\.css)["']`)},
	}
	for _, check := range checks {
		matches := check.pattern.FindAllStringSubmatch(root.Body.String(), -1)
		if len(matches) == 0 {
			t.Fatalf("index.html does not contain a %s", check.name)
		}
		for _, match := range matches {
			assetPath := match[1]
			if !strings.HasPrefix(assetPath, "/") {
				// Vue CLI emits relative static/js paths while the older
				// embedded bundle emits /js paths. Both are valid browser URLs.
				assetPath = "/" + assetPath
			}
			asset := httptest.NewRecorder()
			router.ServeHTTP(asset, httptest.NewRequest("GET", assetPath, nil))
			if asset.Code != 200 {
				t.Errorf("GET %s status = %d, want 200", assetPath, asset.Code)
				continue
			}
			body, err := io.ReadAll(asset.Body)
			if err != nil {
				t.Errorf("read frontend asset %s: %v", assetPath, err)
				continue
			}
			if len(body) == 0 || strings.Contains(strings.ToLower(string(body)), "<html") {
				t.Errorf("frontend asset %s returned empty content or HTML fallback", assetPath)
			}
		}
	}

	// The embedded service worker must only precache assets present in the
	// embedded distribution; stale precache entries can leave users with a
	// partially updated white screen after a release upgrade.
	serviceWorker := httptest.NewRecorder()
	router.ServeHTTP(serviceWorker, httptest.NewRequest("GET", "/service-worker.js", nil))
	if serviceWorker.Code != 200 {
		t.Fatalf("GET /service-worker.js status = %d, want 200", serviceWorker.Code)
	}
	precachePattern := regexp.MustCompile(`url:\s*["']([^"']+)["']`)
	for _, match := range precachePattern.FindAllStringSubmatch(serviceWorker.Body.String(), -1) {
		assetPath := match[1]
		if !strings.HasPrefix(assetPath, "/") {
			assetPath = "/" + assetPath
		}
		asset := httptest.NewRecorder()
		router.ServeHTTP(asset, httptest.NewRequest("GET", assetPath, nil))
		if asset.Code != 200 {
			t.Errorf("service worker precache asset %s returned %d", assetPath, asset.Code)
		}
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

func TestInspectionReportBrowserRouteServesSPA(t *testing.T) {
	router := InitRouter()
	page := httptest.NewRecorder()
	router.ServeHTTP(page, httptest.NewRequest("GET", "/report/inspect", nil))
	if page.Code != 200 {
		t.Fatalf("GET /report/inspect status = %d, want 200", page.Code)
	}
	if !strings.Contains(strings.ToLower(page.Body.String()), "<!doctype") {
		t.Fatalf("GET /report/inspect did not return the SPA document: %s", page.Body.String())
	}
	if page.Header().Get("Cache-Control") == "" || !strings.Contains(page.Header().Get("Cache-Control"), "no-store") {
		t.Fatalf("GET /report/inspect Cache-Control = %q, want no-store", page.Header().Get("Cache-Control"))
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
	if response.Code != 503 {
		t.Fatalf("POST /v1/manager/info HTTP status = %d, want 503 before installation", response.Code)
	}
	if !strings.Contains(response.Body.String(), `"redirect":"/install"`) {
		t.Fatalf("POST /v1/manager/info response = %s, want install redirect", response.Body.String())
	}
}

func TestLoginEndpointIsRegistered(t *testing.T) {
	router := InitRouter()
	response := httptest.NewRecorder()
	request := httptest.NewRequest("POST", "/v1/login", strings.NewReader(`{invalid-json`))
	router.ServeHTTP(response, request)
	if response.Code != 503 || !strings.Contains(response.Body.String(), `"redirect":"/install"`) {
		t.Fatalf("POST /v1/login before installation returned HTTP %d: %s", response.Code, response.Body.String())
	}
}

func TestLegacyRootLoginAliasReturnsJSON(t *testing.T) {
	router := InitRouter()
	response := httptest.NewRecorder()
	request := httptest.NewRequest("POST", "/login", strings.NewReader(`{invalid-json`))
	request.Header.Set("Accept", "application/json")
	router.ServeHTTP(response, request)
	if response.Code != 503 {
		t.Fatalf("POST /login before installation returned HTTP %d, want 503: %s", response.Code, response.Body.String())
	}
	if got := response.Header().Get("Content-Type"); !strings.Contains(got, "application/json") {
		t.Fatalf("POST /login Content-Type = %q, want application/json", got)
	}
	if !strings.Contains(response.Body.String(), `"redirect":"/install"`) {
		t.Fatalf("POST /login response = %s, want install redirect", response.Body.String())
	}
}

func TestUnknownV1APIPathNeverFallsBackToHTML(t *testing.T) {
	router := InitRouter()
	response := httptest.NewRecorder()
	router.ServeHTTP(response, httptest.NewRequest("GET", "/v1/unknown", nil))
	if response.Code != 404 {
		t.Fatalf("GET /v1/unknown status = %d, want 404", response.Code)
	}
	if got := response.Header().Get("Content-Type"); !strings.Contains(got, "application/json") {
		t.Fatalf("GET /v1/unknown Content-Type = %q, want application/json", got)
	}
	if strings.Contains(strings.ToLower(response.Body.String()), "<!doctype") {
		t.Fatalf("GET /v1/unknown returned the SPA document: %s", response.Body.String())
	}
}

func TestLoginBrowserRouteServesEmbeddedSPA(t *testing.T) {
	router := InitRouter()
	response := httptest.NewRecorder()
	router.ServeHTTP(response, httptest.NewRequest("GET", "/user/login", nil))
	if response.Code != 200 || !strings.Contains(strings.ToLower(response.Body.String()), "<!doctype") {
		t.Fatalf("GET /user/login returned HTTP %d, expected the embedded SPA document", response.Code)
	}
	if response.Header().Get("Cache-Control") == "" || !strings.Contains(response.Header().Get("Cache-Control"), "no-store") {
		t.Fatalf("GET /user/login Cache-Control = %q, want no-store", response.Header().Get("Cache-Control"))
	}
}

func TestOfficialAndExtensionRoutesRemainRegistered(t *testing.T) {
	router := InitRouter()
	routes := make(map[string]bool)
	for _, route := range router.Routes() {
		routes[route.Method+" "+route.Path] = true
	}

	// Keep the v3.0.6 product areas reachable while extending the application
	// with instance management, inspection and security-log reporting.
	want := []string{
		"GET /v1/index/overview",
		"GET /v1/host",
		"GET /v1/host_group",
		"GET /v1/template",
		"GET /v1/item",
		"POST /v1/history",
		"GET /v1/trend",
		"POST /v1/graph",
		"GET /v1/alarm",
		"GET /v1/problem",
		"GET /v1/topology",
		"GET /v1/topodata/:id",
		"GET /v1/report",
		"POST /v1/export/inventory",
		"GET /v1/system/config",
		"GET /v1/asset-group",
		"GET /v1/asset-type",
		"GET /v1/egress/configs",
		"GET /v1/user",
		"GET /v1/group",
		"GET /v1/menu",
		"GET /v1/zabbix/instance",
		"GET /v1/inspection/policies",
		"POST /v1/inspection/run",
		"GET /v1/inspection/policies/:id/summary",
		"POST /v1/inspection/export",
	}
	for _, key := range want {
		if !routes[key] {
			t.Errorf("required official or extension route %q is not registered", key)
		}
	}
	if !routes["POST /install/database-info"] {
		t.Error("database discovery route is not registered")
	}
}

func TestAllOfficialV306RoutesRemainRegistered(t *testing.T) {
	router := InitRouter()
	routes := make(map[string]bool)
	for _, route := range router.Routes() {
		routes[route.Method+" "+route.Path] = true
	}

	checked := 0
	for _, line := range strings.Split(officialV306RouteContract, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		checked++
		if !routes[line] {
			t.Errorf("official v3.0.6 route %q is no longer registered", line)
		}
	}
	if checked != 170 {
		t.Fatalf("official route contract contains %d routes, want 170", checked)
	}
}
