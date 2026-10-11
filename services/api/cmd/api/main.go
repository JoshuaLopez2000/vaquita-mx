package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/auth"
	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/database"
	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/groups"
	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/payments"
)

type application struct {
	auth     *auth.Repository
	payments payments.Provider
	requests *payments.Repository
	groups   *groups.Repository
}

const (
	correlationHeader = "X-Correlation-ID"
	errorVersion      = "1"
)

type apiError struct {
	Version string            `json:"version"`
	Code    string            `json:"code"`
	Message string            `json:"message"`
	Fields  map[string]string `json:"fields,omitempty"`
	Error   string            `json:"error"` // Deprecated beta compatibility field.
}

type correlationIDKey struct{}

func main() {
	if len(os.Args) == 2 && os.Args[1] == "healthcheck" {
		runHealthcheck()
		return
	}
	if len(os.Args) == 2 && os.Args[1] == "migrate" {
		runMigrations()
		return
	}
	port := getenv("PORT", "8080")
	databaseURL := getenv("DATABASE_URL", "postgres://vaquita:vaquita-local@localhost:5432/vaquita?sslmode=disable")
	startupContext, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	schemaDatabase, err := database.Open(databaseURL)
	if err != nil {
		slog.Error("open schema database", "error", err)
		os.Exit(1)
	}
	version, err := database.Verify(startupContext, schemaDatabase)
	_ = schemaDatabase.Close()
	if err != nil {
		slog.Error("verify database schema", "error", err)
		os.Exit(1)
	}
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
	paymentRepository, err := payments.Open(startupContext, databaseURL)
	if err != nil {
		slog.Error("connect payments database", "error", err)
		os.Exit(1)
	}
	defer paymentRepository.Close()
	app := application{
		auth:     authRepository,
		payments: payments.SimulatedProvider{},
		requests: paymentRepository,
		groups:   repository,
	}

	server := &http.Server{
		Addr:              ":" + port,
		Handler:           app.routes(getenv("ALLOWED_ORIGINS", "*")),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	slog.Info("api listening", "address", server.Addr, "payment_provider", app.payments.Name(), "schema_version", version)
	if err := server.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
		slog.Error("api stopped", "error", err)
		os.Exit(1)
	}
}

func runMigrations() {
	databaseURL := getenv("DATABASE_URL", "postgres://vaquita:vaquita-local@localhost:5432/vaquita?sslmode=disable")
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	db, err := database.Open(databaseURL)
	if err != nil {
		slog.Error("open migration database", "error", err)
		os.Exit(1)
	}
	defer db.Close()
	result, err := database.Migrate(ctx, db)
	if err != nil {
		slog.Error("migrate database", "error", err)
		os.Exit(1)
	}
	for _, migration := range result.Applied {
		slog.Info("applied database migration", "version", migration.Version, "name", migration.Name)
	}
	slog.Info("database migrations complete", "schema_version", result.CurrentVersion, "applied", len(result.Applied))
}

// cors permits the separately hosted Flutter web client to call the API. In
// development the default accepts any origin; deployed environments should set
// ALLOWED_ORIGINS to a comma-separated list of their HTTPS web origins.
func getenv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
