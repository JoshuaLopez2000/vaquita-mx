package main

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/your-user/vaquita-mx/services/api/internal/groups"
	"github.com/your-user/vaquita-mx/services/api/internal/payments"
)

type application struct {
	payments payments.Provider
	groups   *groups.Repository
}

func main() {
	if len(os.Args) == 2 && os.Args[1] == "healthcheck" {
		runHealthcheck()
		return
	}
	port := getenv("PORT", "8080")
	databaseURL := getenv("DATABASE_URL", "postgres://vaquita:vaquita-local@localhost:5432/vaquita?sslmode=disable")
	startupContext, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	repository, err := groups.Open(startupContext, databaseURL)
	if err != nil {
		slog.Error("connect database", "error", err)
		os.Exit(1)
	}
	defer repository.Close()
	if err := repository.Migrate(startupContext); err != nil {
		slog.Error("migrate database", "error", err)
		os.Exit(1)
	}
	app := application{
		payments: payments.SimulatedProvider{},
		groups:   repository,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", app.health)
	mux.HandleFunc("GET /api/v1/groups", app.listGroups)
	mux.HandleFunc("POST /api/v1/groups", app.createGroup)
	mux.HandleFunc("POST /api/v1/groups/{groupID}/expenses", app.addExpense)
	mux.HandleFunc("POST /api/v1/groups/{groupID}/settlements", app.addSettlement)
	mux.HandleFunc("GET /api/v1/payment-providers", app.providers)
	mux.HandleFunc("POST /api/v1/payment-requests", app.createPaymentRequest)

	server := &http.Server{
		Addr:              ":" + port,
		Handler:           requestLogger(mux),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	slog.Info("api listening", "address", server.Addr, "payment_provider", app.payments.Name())
	if err := server.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
		slog.Error("api stopped", "error", err)
		os.Exit(1)
	}
}

func runHealthcheck() {
	client := http.Client{Timeout: 2 * time.Second}
	response, err := client.Get("http://127.0.0.1:" + getenv("PORT", "8080") + "/healthz")
	if err != nil || response.StatusCode != http.StatusOK {
		os.Exit(1)
	}
	response.Body.Close()
}

func (app application) health(w http.ResponseWriter, _ *http.Request) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if err := app.groups.Ping(ctx); err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "unavailable", "service": "vaquita-api"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok", "service": "vaquita-api"})
}

func (app application) listGroups(w http.ResponseWriter, r *http.Request) {
	result, err := app.groups.List(r.Context())
	if err != nil {
		serverError(w, "list groups", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"groups": result})
}

func (app application) createGroup(w http.ResponseWriter, r *http.Request) {
	var input groups.CreateGroupInput
	if !decodeJSON(w, r, &input) {
		return
	}
	result, err := app.groups.Create(r.Context(), input)
	if errors.Is(err, groups.ErrInvalid) {
		writeJSON(w, http.StatusUnprocessableEntity, map[string]string{"error": "a name and at least one member are required"})
		return
	}
	if err != nil {
		serverError(w, "create group", err)
		return
	}
	writeJSON(w, http.StatusCreated, result)
}

func (app application) addExpense(w http.ResponseWriter, r *http.Request) {
	var input groups.AddExpenseInput
	if !decodeJSON(w, r, &input) {
		return
	}
	result, err := app.groups.AddExpense(r.Context(), r.PathValue("groupID"), input)
	if errors.Is(err, groups.ErrInvalid) {
		writeJSON(w, http.StatusUnprocessableEntity, map[string]string{"error": "invalid expense or group member"})
		return
	}
	if errors.Is(err, groups.ErrNotFound) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "group not found"})
		return
	}
	if err != nil {
		serverError(w, "add expense", err)
		return
	}
	writeJSON(w, http.StatusCreated, result)
}

func (app application) addSettlement(w http.ResponseWriter, r *http.Request) {
	var input struct {
		MemberID string `json:"member_id"`
	}
	if !decodeJSON(w, r, &input) {
		return
	}
	result, err := app.groups.AddSettlement(r.Context(), r.PathValue("groupID"), input.MemberID)
	if errors.Is(err, groups.ErrInvalid) {
		writeJSON(w, http.StatusUnprocessableEntity, map[string]string{"error": "member has no balance to settle"})
		return
	}
	if errors.Is(err, groups.ErrNotFound) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "group not found"})
		return
	}
	if err != nil {
		serverError(w, "add settlement", err)
		return
	}
	writeJSON(w, http.StatusCreated, result)
}

func (app application) providers(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"active": app.payments.Name(),
		"providers": []map[string]any{{
			"id": app.payments.Name(), "live": false,
		}},
	})
}

func (app application) createPaymentRequest(w http.ResponseWriter, r *http.Request) {
	var input payments.CreateRequest
	if !decodeJSON(w, r, &input) {
		return
	}
	result, err := app.payments.CreateRequest(r.Context(), input)
	if errors.Is(err, payments.ErrInvalidRequest) {
		writeJSON(w, http.StatusUnprocessableEntity, map[string]string{"error": "group_id, expense_id, debtor_id, a positive amount_cents, and currency MXN are required"})
		return
	}
	if err != nil {
		slog.Error("create payment request", "error", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}
	writeJSON(w, http.StatusCreated, result)
}

func decodeJSON(w http.ResponseWriter, r *http.Request, destination any) bool {
	defer r.Body.Close()
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON body"})
		return false
	}
	return true
}

func serverError(w http.ResponseWriter, operation string, err error) {
	slog.Error(operation, "error", err)
	writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
}

func requestLogger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		started := time.Now()
		next.ServeHTTP(w, r)
		slog.Info("request", "method", r.Method, "path", r.URL.Path, "duration_ms", time.Since(started).Milliseconds())
	})
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(value); err != nil {
		slog.Error("encode response", "error", err)
	}
}

func getenv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
