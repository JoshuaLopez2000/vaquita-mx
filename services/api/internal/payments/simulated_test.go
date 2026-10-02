package payments

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestSimulatedProviderCreatesMXNRequest(t *testing.T) {
	now := time.Date(2026, time.September, 24, 12, 0, 0, 0, time.UTC)
	provider := SimulatedProvider{Now: func() time.Time { return now }}

	result, err := provider.CreateRequest(context.Background(), CreateRequest{
		GroupID:     "group-1",
		DebtorID:    "user-2",
		AmountCents: 25050,
		Currency:    "MXN",
	})
	if err != nil {
		t.Fatalf("CreateRequest returned error: %v", err)
	}
	if result.Status != StatusPending {
		t.Fatalf("status = %q, want %q", result.Status, StatusPending)
	}
	if result.ExpiresAt != now.Add(24*time.Hour) {
		t.Fatalf("expires_at = %v", result.ExpiresAt)
	}
}

func TestSimulatedProviderRejectsNonMXNRequest(t *testing.T) {
	provider := SimulatedProvider{}
	_, err := provider.CreateRequest(context.Background(), CreateRequest{
		GroupID: "group-1", DebtorID: "user-2", AmountCents: 100, Currency: "USD",
	})
	if !errors.Is(err, ErrInvalidRequest) {
		t.Fatalf("error = %v, want ErrInvalidRequest", err)
	}
}
