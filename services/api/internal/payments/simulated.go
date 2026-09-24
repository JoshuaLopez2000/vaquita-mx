package payments

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"time"
)

type SimulatedProvider struct {
	Now func() time.Time
}

func (p SimulatedProvider) Name() string { return "simulated" }

func (p SimulatedProvider) CreateRequest(_ context.Context, input CreateRequest) (PaymentRequest, error) {
	if err := input.Validate(); err != nil {
		return PaymentRequest{}, err
	}

	id, err := randomID()
	if err != nil {
		return PaymentRequest{}, fmt.Errorf("generate payment request id: %w", err)
	}
	now := time.Now().UTC()
	if p.Now != nil {
		now = p.Now().UTC()
	}

	return PaymentRequest{
		ID:            id,
		Provider:      p.Name(),
		Status:        StatusPending,
		AmountCents:   input.AmountCents,
		Currency:      input.Currency,
		PaymentURL:    "vaquitamx://payment-requests/" + id,
		ExpiresAt:     now.Add(24 * time.Hour),
		CorrelationID: input.ExpenseID + ":" + input.DebtorID,
	}, nil
}

func randomID() (string, error) {
	value := make([]byte, 16)
	if _, err := rand.Read(value); err != nil {
		return "", err
	}
	return "pr_" + hex.EncodeToString(value), nil
}
