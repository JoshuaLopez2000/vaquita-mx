package payments

import (
	"context"
	"errors"
	"strings"
	"time"
)

var ErrInvalidRequest = errors.New("invalid payment request")

type Status string

const (
	StatusPending Status = "PENDING"
	StatusPaid    Status = "PAID"
	StatusExpired Status = "EXPIRED"
	StatusFailed  Status = "FAILED"
)

type CreateRequest struct {
	GroupID     string `json:"group_id"`
	ExpenseID   string `json:"expense_id"`
	DebtorID    string `json:"debtor_id"`
	AmountCents int64  `json:"amount_cents"`
	Currency    string `json:"currency"`
	Description string `json:"description"`
}

func (r CreateRequest) Validate() error {
	if strings.TrimSpace(r.GroupID) == "" || strings.TrimSpace(r.ExpenseID) == "" || strings.TrimSpace(r.DebtorID) == "" {
		return ErrInvalidRequest
	}
	if r.AmountCents <= 0 || r.Currency != "MXN" {
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
}

type Provider interface {
	Name() string
	CreateRequest(context.Context, CreateRequest) (PaymentRequest, error)
}
