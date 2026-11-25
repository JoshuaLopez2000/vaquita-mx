package payments

import (
	"context"
	"errors"
	"strings"
	"time"
	"unicode/utf8"
)

var (
	ErrInvalidRequest      = errors.New("invalid payment request")
	ErrProviderUnavailable = errors.New("provider lookup unavailable")
	ErrProviderUnknown     = errors.New("unknown provider reference")
)

type Status string

const (
	StatusPending Status = "PENDING"
	StatusPaid    Status = "PAID"
	StatusExpired Status = "EXPIRED"
	StatusFailed  Status = "FAILED"
)

type CreateRequest struct {
	GroupID     string `json:"group_id"`
	DebtorID    string `json:"debtor_id"`
	AmountCents int64  `json:"amount_cents"`
	Currency    string `json:"currency"`
	Description string `json:"description"`
	// CreditorID is resolved server-side from the authenticated user and set
	// by the HTTP layer. Clients never post it.
	CreditorID string `json:"-"`
}

func (r CreateRequest) Validate() error {
	if strings.TrimSpace(r.GroupID) == "" || strings.TrimSpace(r.DebtorID) == "" || strings.TrimSpace(r.CreditorID) == "" {
		return ErrInvalidRequest
	}
	if r.AmountCents <= 0 || r.Currency != "MXN" {
		return ErrInvalidRequest
	}
	if utf8.RuneCountInString(strings.TrimSpace(r.Description)) > 200 {
		return ErrInvalidRequest
	}
	return nil
}

type PaymentRequest struct {
	ID            string    `json:"id"`
	Provider      string    `json:"provider"`
	Status        Status    `json:"status"`
	AmountCents   int64     `json:"amount_cents"`
	Currency      string    `json:"currency"`
	PaymentURL    string    `json:"payment_url"`
	ExpiresAt     time.Time `json:"expires_at"`
	CorrelationID string    `json:"correlation_id"`
	// ProviderRef is the provider's own record of the request. It is opaque
	// to clients (read-only) and keys authenticated provider-side lookups.
	ProviderRef string `json:"provider_ref,omitempty"`
}

// ProviderPayment is the provider's answer about its own record. Providers
// must echo the reference, correlation ID, amount, currency, and receiver they
// were created with; the reconciliation job matches them before settlement.
type ProviderPayment struct {
	ProviderRef     string
	ProviderEventID string
	ReceiverRef     string
	CorrelationID   string
	AmountCents     int64
	Currency        string
	Status          Status
}

type Provider interface {
	Name() string
	CreateRequest(context.Context, CreateRequest) (PaymentRequest, error)
	// Lookup asks the provider about its own record for a payment request.
	// Reconciliation never trusts client-reported payment state.
	Lookup(ctx context.Context, providerRef string) (ProviderPayment, error)
}
