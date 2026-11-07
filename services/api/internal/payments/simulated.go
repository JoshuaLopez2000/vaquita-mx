package payments

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"sync"
	"time"
)

// simulatedPayment is the provider-side record. It exists only in the local
// simulator process; it is not a bank transfer or provider credential.
type simulatedPayment struct {
	amountCents   int64
	currency      string
	receiverRef   string
	correlationID string
	expiresAt     time.Time
	settledEvent  string
}

// SimulatedProvider keeps provider-side state so the reconciliation loop can
// verify what really happened at the provider, independently of the client.
type SimulatedProvider struct {
	Now func() time.Time

	mu       sync.Mutex
	requests map[string]simulatedPayment
}

func NewSimulatedProvider() *SimulatedProvider {
	return &SimulatedProvider{requests: map[string]simulatedPayment{}}
}

func (p *SimulatedProvider) Name() string { return "simulated" }

func (p *SimulatedProvider) CreateRequest(_ context.Context, input CreateRequest) (PaymentRequest, error) {
	if err := input.Validate(); err != nil {
		return PaymentRequest{}, err
	}

	id, err := randomID("pr_")
	if err != nil {
		return PaymentRequest{}, fmt.Errorf("generate payment request id: %w", err)
	}
	providerRef, err := randomID("sreq_")
	if err != nil {
		return PaymentRequest{}, fmt.Errorf("generate provider reference: %w", err)
	}
	correlation := input.GroupID + ":" + input.DebtorID
	expiresAt := p.now().Add(24 * time.Hour)

	p.mu.Lock()
	if p.requests == nil {
		p.requests = map[string]simulatedPayment{}
	}
	p.requests[providerRef] = simulatedPayment{
		amountCents:   input.AmountCents,
		currency:      input.Currency,
		receiverRef:   input.CreditorID,
		correlationID: correlation,
		expiresAt:     expiresAt,
	}
	p.mu.Unlock()

	return PaymentRequest{
		ID:            id,
		Provider:      p.Name(),
		Status:        StatusPending,
		AmountCents:   input.AmountCents,
		Currency:      input.Currency,
		PaymentURL:    "vaquitamx://payment-requests/" + id,
		ExpiresAt:     expiresAt,
		CorrelationID: correlation,
		ProviderRef:   providerRef,
	}, nil
}

// SimulateSettlement moves the provider-side payment to PAID and returns the
// provider event that callbacks and reconciliation will both observe. It never
// touches this service's ledger.
func (p *SimulatedProvider) SimulateSettlement(providerRef string) (string, error) {
	event, err := randomID("pe_")
	if err != nil {
		return "", fmt.Errorf("generate simulated settlement event: %w", err)
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	payment, exists := p.requests[providerRef]
	if !exists {
		return "", ErrProviderUnknown
	}
	if p.now().After(payment.expiresAt) {
		return "", fmt.Errorf("simulated payment %q expired", providerRef)
	}
	payment.settledEvent = event
	p.requests[providerRef] = payment
	return event, nil
}

func (p *SimulatedProvider) Lookup(_ context.Context, providerRef string) (ProviderPayment, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	payment, exists := p.requests[providerRef]
	if !exists {
		return ProviderPayment{}, ErrProviderUnknown
	}
	result := ProviderPayment{
		ProviderRef:     providerRef,
		ProviderEventID: payment.settledEvent,
		ReceiverRef:     payment.receiverRef,
		CorrelationID:   payment.correlationID,
		AmountCents:     payment.amountCents,
		Currency:        payment.currency,
	}
	switch {
	case payment.settledEvent != "":
		result.Status = StatusPaid
	case p.now().After(payment.expiresAt):
		result.Status = StatusExpired
	default:
		result.Status = StatusPending
	}
	return result, nil
}

func (p *SimulatedProvider) now() time.Time {
	if p.Now == nil {
		return time.Now().UTC()
	}
	return p.Now().UTC()
}

func randomID(prefix string) (string, error) {
	value := make([]byte, 16)
	if _, err := rand.Read(value); err != nil {
		return "", err
	}
	return prefix + hex.EncodeToString(value), nil
}
