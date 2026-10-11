package main

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestCORSAllowsConfiguredWebOriginAndPreflight(t *testing.T) {
	handler := cors(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	}), "http://localhost:3000,https://app.vaquita.mx")

	request := httptest.NewRequest(http.MethodOptions, "/api/v1/groups", nil)
	request.Header.Set("Origin", "http://localhost:3000")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)

	if response.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusNoContent)
	}
	if got := response.Header().Get("Access-Control-Allow-Origin"); got != "http://localhost:3000" {
		t.Fatalf("allow origin = %q", got)
	}
	if got := response.Header().Get("Access-Control-Allow-Headers"); got != "Authorization, Content-Type, Idempotency-Key, X-Correlation-ID" {
		t.Fatalf("allow headers = %q", got)
	}
	if got := response.Header().Get("Access-Control-Expose-Headers"); got != correlationHeader {
		t.Fatalf("expose headers = %q", got)
	}
}

func TestCorrelationIDsAcceptSafeValuesAndReplaceUnsafeValues(t *testing.T) {
	for _, test := range []struct {
		name   string
		input  string
		accept bool
	}{
		{name: "accepted", input: "mobile-01.test:abc", accept: true},
		{name: "spaces", input: "not log safe", accept: false},
		{name: "too long", input: strings.Repeat("a", 65), accept: false},
	} {
		t.Run(test.name, func(t *testing.T) {
			var contextID string
			handler := correlationIDs(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				contextID = correlationID(r)
				w.WriteHeader(http.StatusNoContent)
			}))
			request := httptest.NewRequest(http.MethodGet, "/healthz", nil)
			request.Header.Set(correlationHeader, test.input)
			response := httptest.NewRecorder()

			handler.ServeHTTP(response, request)

			got := response.Header().Get(correlationHeader)
			if got == "" || len(got) > 64 || got != contextID {
				t.Fatalf("response ID = %q, context ID = %q", got, contextID)
			}
			if test.accept && got != test.input {
				t.Fatalf("accepted ID = %q, want %q", got, test.input)
			}
			if !test.accept && got == test.input {
				t.Fatalf("unsafe ID was accepted: %q", got)
			}
		})
	}
}

func TestMalformedInputReturnsVersionedError(t *testing.T) {
	app := application{}
	request := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", strings.NewReader("{"))
	request.Header.Set(correlationHeader, "malformed-test")
	response := httptest.NewRecorder()

	app.routes("*").ServeHTTP(response, request)

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusBadRequest)
	}
	if got := response.Header().Get(correlationHeader); got != "malformed-test" {
		t.Fatalf("correlation ID = %q", got)
	}
	var body apiError
	if err := json.NewDecoder(response.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}
	if body.Version != errorVersion || body.Code != "invalid_json" || body.Fields["body"] != "invalid" || body.Error != body.Message {
		t.Fatalf("error response = %#v", body)
	}
}

func TestUnknownRouteReturnsVersionedError(t *testing.T) {
	app := application{}
	request := httptest.NewRequest(http.MethodGet, "/api/v1/unknown", nil)
	response := httptest.NewRecorder()

	app.routes("*").ServeHTTP(response, request)

	if response.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusNotFound)
	}
	var body apiError
	if err := json.NewDecoder(response.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}
	if body.Version != errorVersion || body.Code != "resource_not_found" {
		t.Fatalf("error response = %#v", body)
	}
	if !validCorrelationID(response.Header().Get(correlationHeader)) {
		t.Fatalf("invalid correlation ID %q", response.Header().Get(correlationHeader))
	}
}

func TestRequestLogIncludesCorrelationIDWithoutSensitiveInput(t *testing.T) {
	previous := slog.Default()
	var output bytes.Buffer
	slog.SetDefault(slog.New(slog.NewJSONHandler(&output, nil)))
	t.Cleanup(func() { slog.SetDefault(previous) })

	handler := correlationIDs(requestLogger(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		writeAPIError(w, http.StatusUnauthorized, "authentication_required", "authentication required", nil)
	})))
	request := httptest.NewRequest(http.MethodPost, "/api/v1/groups?phone=%2B525511112222", strings.NewReader(`{"description":"private dinner"}`))
	request.Header.Set(correlationHeader, "safe-log-id")
	request.Header.Set("Authorization", "Bearer secret-access-token")
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	logged := output.String()
	if !strings.Contains(logged, `"correlation_id":"safe-log-id"`) {
		t.Fatalf("correlation ID missing from log: %s", logged)
	}
	for _, sensitive := range []string{"secret-access-token", "+525511112222", "private dinner"} {
		if strings.Contains(logged, sensitive) {
			t.Fatalf("log contains sensitive value %q: %s", sensitive, logged)
		}
	}
}

func TestCORSRejectsUnknownOrigin(t *testing.T) {
	handler := cors(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	}), "https://app.vaquita.mx")

	request := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	request.Header.Set("Origin", "https://untrusted.example")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)

	if got := response.Header().Get("Access-Control-Allow-Origin"); got != "" {
		t.Fatalf("allow origin = %q, want empty", got)
	}
}
