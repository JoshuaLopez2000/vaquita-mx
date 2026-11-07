package payments

import (
	"context"
	"errors"
	"testing"
	"time"
)

func simulatedAt(now time.Time) *SimulatedProvider {
	provider := NewSimulatedProvider()
	provider.Now = func() time.Time { return now }
	return provider
}

func TestSimulatedProviderCreatesMXNRequest(t *testing.T) {
	now := time.Date(2026, time.September, 24, 12, 0, 0, 0, time.UTC)
	provider := simulatedAt(now)

	result, err := provider.CreateRequest(context.Background(), CreateRequest{
		GroupID:     "group-1",
		DebtorID:    "user-2",
		CreditorID:  "member-1",
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
	if result.ProviderRef == "" {
		t.Fatal("provider reference is required for provider-side lookups")
	}
}

func TestSimulatedProviderRejectsInvalidRequests(t *testing.T) {
	provider := NewSimulatedProvider()
	if _, err := provider.CreateRequest(context.Background(), CreateRequest{
		GroupID: "group-1", DebtorID: "user-2", CreditorID: "member-1", AmountCents: 100, Currency: "USD",
	}); !errors.Is(err, ErrInvalidRequest) {
		t.Fatalf("error = %v, want ErrInvalidRequest", err)
	}
	if _, err := provider.CreateRequest(context.Background(), CreateRequest{
		GroupID: "group-1", DebtorID: "user-2", AmountCents: 100, Currency: "MXN",
	}); !errors.Is(err, ErrInvalidRequest) {
		t.Fatalf("missing creditor error = %v, want ErrInvalidRequest", err)
	}
}

func TestSimulatedProviderLookupAndSettlementDocket(t *testing.T) {
	now := time.Date(2026, time.September, 24, 12, 0, 0, 0, time.UTC)
	provider := simulatedAt(now)
	request, err := provider.CreateRequest(context.Background(), CreateRequest{
		GroupID: "group-1", DebtorID: "user-2", CreditorID: "member-1", AmountCents: 5000, Currency: "MXN",
	})
	if err != nil {
		t.Fatal(err)
	}

	pending, err := provider.Lookup(context.Background(), request.ProviderRef)
	if err != nil {
		t.Fatal(err)
	}
	if pending.Status != StatusPending || pending.AmountCents != 5000 || pending.Currency != "MXN" ||
		pending.CorrelationID != request.CorrelationID || pending.ReceiverRef != "member-1" ||
		pending.ProviderRef != request.ProviderRef || pending.ProviderEventID != "" {
		t.Fatalf("pending lookup = %#v", pending)
	}

	event, err := provider.SimulateSettlement(request.ProviderRef)
	if err != nil || event == "" {
		t.Fatalf("SimulateSettlement = (%q, %v)", event, err)
	}
	paid, err := provider.Lookup(context.Background(), request.ProviderRef)
	if err != nil {
		t.Fatal(err)
	}
	if paid.Status != StatusPaid || paid.ProviderEventID != event {
		t.Fatalf("paid lookup = %#v, want event %q", paid, event)
	}

	if _, err := provider.SimulateSettlement("sreq_unknown"); !errors.Is(err, ErrProviderUnknown) {
		t.Fatalf("unknown ref error = %v, want ErrProviderUnknown", err)
	}
	if _, err := provider.Lookup(context.Background(), "sreq_unknown"); !errors.Is(err, ErrProviderUnknown) {
		t.Fatalf("lookup unknown ref error = %v, want ErrProviderUnknown", err)
	}

	stale, err := provider.CreateRequest(context.Background(), CreateRequest{
		GroupID: "group-1", DebtorID: "user-2", CreditorID: "member-1", AmountCents: 100, Currency: "MXN",
	})
	if err != nil {
		t.Fatal(err)
	}

	// After expiry the provider refuses settlement and reports EXPIRED.
	late := now.Add(25 * time.Hour)
	provider.Now = func() time.Time { return late }
	if _, err := provider.SimulateSettlement(stale.ProviderRef); err == nil {
		t.Fatal("settling an expired payment must fail")
	}
	expiredState, err := provider.Lookup(context.Background(), stale.ProviderRef)
	if err != nil {
		t.Fatal(err)
	}
	if expiredState.Status != StatusExpired {
		t.Fatalf("expired lookup status = %q, want %q", expiredState.Status, StatusExpired)
	}
}
