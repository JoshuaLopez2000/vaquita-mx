package main

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/your-user/vaquita-mx/services/api/internal/auth"
	"github.com/your-user/vaquita-mx/services/api/internal/groups"
	"github.com/your-user/vaquita-mx/services/api/internal/payments"
)

type application struct {
	auth     *auth.Repository
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
	authRepository, err := auth.Open(databaseURL)
	if err != nil {
		slog.Error("connect auth database", "error", err)
		os.Exit(1)
	}
	defer authRepository.Close()
	if err := authRepository.Migrate(startupContext); err != nil {
		slog.Error("migrate auth database", "error", err)
		os.Exit(1)
	}
	if err := repository.Migrate(startupContext); err != nil {
		slog.Error("migrate database", "error", err)
		os.Exit(1)
	}
	app := application{
		auth:     authRepository,
		payments: payments.SimulatedProvider{},
		groups:   repository,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", app.health)
	mux.HandleFunc("POST /api/v1/auth/register", app.register)
	mux.HandleFunc("POST /api/v1/auth/login", app.login)
	mux.HandleFunc("POST /api/v1/contacts/matches", app.requireUser(app.matchContacts))
	mux.HandleFunc("GET /api/v1/contacts", app.requireUser(app.listContacts))
	mux.HandleFunc("POST /api/v1/contacts", app.requireUser(app.saveContacts))
	mux.HandleFunc("GET /api/v1/groups", app.requireUser(app.listGroups))
	mux.HandleFunc("GET /api/v1/group-invitations", app.requireUser(app.listInvitations))
	mux.HandleFunc("POST /api/v1/group-invitations/{groupID}/response", app.requireUser(app.respondInvitation))
	mux.HandleFunc("POST /api/v1/groups", app.requireUser(app.createGroup))
	mux.HandleFunc("PATCH /api/v1/groups/{groupID}", app.requireUser(app.updateGroup))
	mux.HandleFunc("POST /api/v1/groups/{groupID}/members", app.requireUser(app.addMember))
	mux.HandleFunc("PATCH /api/v1/groups/{groupID}/members/{memberID}", app.requireUser(app.updateMember))
	mux.HandleFunc("POST /api/v1/groups/{groupID}/expenses", app.requireUser(app.addExpense))
	mux.HandleFunc("POST /api/v1/groups/{groupID}/settlements", app.requireUser(app.addSettlement))
	mux.HandleFunc("DELETE /api/v1/groups/{groupID}/members/{memberID}", app.requireUser(app.removeMember))
	mux.HandleFunc("GET /api/v1/groups/{groupID}/unpaid", app.requireUser(app.unpaid))
	mux.HandleFunc("GET /api/v1/status", app.requireUser(app.status))
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

func (app application) register(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Name        string `json:"name"`
		Email       string `json:"email"`
		Phone       string `json:"phone"`
		Password    string `json:"password"`
		SalaryCents int64  `json:"salary_cents"`
	}
	if !decodeJSON(w, r, &input) {
		return
	}
	session, err := app.auth.Register(r.Context(), input.Name, input.Email, input.Phone, input.Password, input.SalaryCents)
	if errors.Is(err, auth.ErrInvalid) {
		writeJSON(w, http.StatusUnprocessableEntity, map[string]string{"error": "name, valid email, Mexican mobile number, non-negative monthly salary, and an 8-character password are required"})
		return
	}
	if errors.Is(err, auth.ErrEmailInUse) {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "email is already registered"})
		return
	}
	if err != nil {
		serverError(w, "register", err)
		return
	}
	writeJSON(w, http.StatusCreated, session)
}

func (app application) updateGroup(w http.ResponseWriter, r *http.Request) {
	var input groups.UpdateGroupInput
	if !decodeJSON(w, r, &input) {
		return
	}
	result, err := app.groups.Update(r.Context(), userID(r), r.PathValue("groupID"), input)
	if errors.Is(err, groups.ErrInvalid) {
		writeJSON(w, http.StatusUnprocessableEntity, map[string]string{"error": "invalid group settings"})
		return
	}
	if errors.Is(err, groups.ErrNotFound) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "group not found"})
		return
	}
	if err != nil {
		serverError(w, "update group", err)
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (app application) addMember(w http.ResponseWriter, r *http.Request) {
	var input groups.MemberInput
	if !decodeJSON(w, r, &input) {
		return
	}
	result, err := app.groups.AddMember(r.Context(), userID(r), r.PathValue("groupID"), input)
	if errors.Is(err, groups.ErrInvalid) {
		writeJSON(w, http.StatusUnprocessableEntity, map[string]string{"error": "a member needs a name or Mexican mobile number"})
		return
	}
	if errors.Is(err, groups.ErrNotFound) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "group not found"})
		return
	}
	if err != nil {
		serverError(w, "add member", err)
		return
	}
	writeJSON(w, http.StatusCreated, result)
}

func (app application) updateMember(w http.ResponseWriter, r *http.Request) {
	var input groups.UpdateMemberInput
	if !decodeJSON(w, r, &input) {
		return
	}
	result, err := app.groups.UpdateMember(r.Context(), userID(r), r.PathValue("groupID"), r.PathValue("memberID"), input)
	if errors.Is(err, groups.ErrInvalid) {
		writeJSON(w, http.StatusUnprocessableEntity, map[string]string{"error": "invalid member update or salary consent"})
		return
	}
	if errors.Is(err, groups.ErrNotFound) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "group or member not found"})
		return
	}
	if err != nil {
		serverError(w, "update member", err)
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (app application) login(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if !decodeJSON(w, r, &input) {
		return
	}
	session, err := app.auth.Login(r.Context(), input.Email, input.Password)
	if errors.Is(err, auth.ErrInvalid) {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid email or password"})
		return
	}
	if err != nil {
		serverError(w, "login", err)
		return
	}
	writeJSON(w, http.StatusOK, session)
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

func (app application) requireUser(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		user, err := app.auth.UserForToken(r.Context(), token)
		if err != nil {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "authentication required"})
			return
		}
		next(w, r.WithContext(context.WithValue(r.Context(), userIDKey{}, user.ID)))
	}
}

type userIDKey struct{}

func userID(r *http.Request) string { return r.Context().Value(userIDKey{}).(string) }

func (app application) matchContacts(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Phones []string `json:"phones"`
	}
	if !decodeJSON(w, r, &input) {
		return
	}
	if len(input.Phones) > 500 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "at most 500 contacts can be matched at once"})
		return
	}
	phones := make([]string, 0, len(input.Phones))
	seen := map[string]bool{}
	for _, value := range input.Phones {
		if phone, ok := auth.NormalizePhone(value); ok && !seen[phone] {
			phones, seen[phone] = append(phones, phone), true
		}
	}
	contacts, err := app.auth.Contacts(r.Context(), userID(r), phones)
	if err != nil {
		serverError(w, "match contacts", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"contacts": contacts})
}

func (app application) listContacts(w http.ResponseWriter, r *http.Request) {
	contacts, err := app.auth.ListContacts(r.Context(), userID(r))
	if err != nil {
		serverError(w, "list contacts", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"contacts": contacts})
}
func (app application) saveContacts(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Contacts []auth.Contact `json:"contacts"`
	}
	if !decodeJSON(w, r, &input) {
		return
	}
	contacts, err := app.auth.SaveContacts(r.Context(), userID(r), input.Contacts)
	if err != nil {
		serverError(w, "save contacts", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"contacts": contacts})
}

func (app application) listGroups(w http.ResponseWriter, r *http.Request) {
	result, err := app.groups.List(r.Context(), userID(r))
	if err != nil {
		serverError(w, "list groups", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"groups": result})
}

func (app application) listInvitations(w http.ResponseWriter, r *http.Request) {
	result, err := app.groups.Invitations(r.Context(), userID(r))
	if err != nil {
		serverError(w, "list invitations", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"invitations": result})
}

func (app application) respondInvitation(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Accept bool `json:"accept"`
	}
	if !decodeJSON(w, r, &input) {
		return
	}
	err := app.groups.RespondInvitation(r.Context(), userID(r), r.PathValue("groupID"), input.Accept)
	if errors.Is(err, groups.ErrNotFound) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "invitation not found"})
		return
	}
	if err != nil {
		serverError(w, "respond invitation", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (app application) createGroup(w http.ResponseWriter, r *http.Request) {
	var input groups.CreateGroupInput
	if !decodeJSON(w, r, &input) {
		return
	}
	result, err := app.groups.Create(r.Context(), userID(r), input)
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
	result, err := app.groups.AddExpense(r.Context(), userID(r), r.PathValue("groupID"), input)
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
	result, err := app.groups.AddSettlement(r.Context(), userID(r), r.PathValue("groupID"), input.MemberID)
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

func (app application) removeMember(w http.ResponseWriter, r *http.Request) {
	err := app.groups.RemoveMember(r.Context(), userID(r), r.PathValue("groupID"), r.PathValue("memberID"))
	if errors.Is(err, groups.ErrInvalid) {
		writeJSON(w, http.StatusUnprocessableEntity, map[string]string{"error": "you cannot remove yourself"})
		return
	}
	if errors.Is(err, groups.ErrNotFound) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "member not found"})
		return
	}
	if err != nil {
		serverError(w, "remove member", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (app application) unpaid(w http.ResponseWriter, r *http.Request) {
	result, err := app.groups.Unpaid(r.Context(), userID(r), r.PathValue("groupID"))
	if errors.Is(err, groups.ErrNotFound) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "group not found"})
		return
	}
	if err != nil {
		serverError(w, "unpaid", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"balances": result})
}

func (app application) status(w http.ResponseWriter, r *http.Request) {
	result, err := app.groups.Status(r.Context(), userID(r))
	if err != nil {
		serverError(w, "status", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"contacts": result})
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
