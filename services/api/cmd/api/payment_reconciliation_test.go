package main

import (
	"context"
	"testing"
	"time"

	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/payments"
)

type reconciliationProvider struct {
	states map[string]payments.ProviderPayment
	err    error
}

func (p *reconciliationProvider) Name() string { return "fake" }

func (p *reconciliationProvider) CreateRequest(_ context.Context, _ payments.CreateRequest) (payments.PaymentRequest, error) {
	return payments.PaymentRequest{}, nil
}

func (p *reconciliationProvider) Lookup(_ context.Context, providerRef string) (payments.ProviderPayment, error) {
	if p.err != nil {
		return payments.ProviderPayment{}, p.err
	}
	state, exists := p.states[providerRef]
	if !exists {
		return payments.ProviderPayment{}, payments.ErrProviderUnavailable
	}
	return state, nil
}

func makeDue(t *testing.T, setup paymentRevalidationSetup, requestID string) {
	t.Helper()
	if _, err := setup.pg.db.Exec(`UPDATE payment_requests SET reconcile_after = now() - interval '1 hour' WHERE id=$1`, requestID); err != nil {
		t.Fatal(err)
	}
}

func requestStatus(t *testing.T, setup paymentRevalidationSetup, requestID string) string {
	t.Helper()
	var status string
	if err := setup.pg.db.QueryRow(`SELECT status FROM payment_requests WHERE id=$1`, requestID).Scan(&status); err != nil {
		t.Fatal(err)
	}
	return status
}

// TestReconciliationCompletesDurablePaidRequest covers the lost-callback
// recovery end to end: the provider confirmed money movement, and the job
// settles the ledger exactly once through the shared completion transaction.
func TestReconciliationCompletesDurablePaidRequest(t *testing.T) {
	t.Parallel()
	setup := paymentRevalidationFixture(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	request := requestPayment(t, setup, "reconcile-paid-1", 50)
	makeDue(t, setup, request.ID)
	if _, err := setup.provider.SimulateSettlement(request.ProviderRef); err != nil {
		t.Fatalf("simulate provider settlement: %v", err)
	}

	repo, err := payments.Open(ctx, setup.pg.dbURL)
	if err != nil {
		t.Fatal(err)
	}
	defer repo.Close()
	reconciler := payments.NewReconciler(setup.provider, repo)
	report, err := reconciler.Cycle(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if report.Claimed != 1 || report.Paid != 1 {
		t.Fatalf("reconciliation report = %#v", report)
	}
	if status := requestStatus(t, setup, request.ID); status != "PAID" {
		t.Fatalf("payment request status = %q, want PAID", status)
	}
	var settlements, reconcileEvents, providerEvents int
	if err := setup.pg.db.QueryRow(`SELECT count(*) FROM settlements WHERE group_id=$1`, setup.group.ID).Scan(&settlements); err != nil {
		t.Fatal(err)
	}
	if err := setup.pg.db.QueryRow(`SELECT count(*) FROM payment_reconcile_events WHERE payment_request_id=$1 AND outcome='PAID'`, request.ID).Scan(&reconcileEvents); err != nil {
		t.Fatal(err)
	}
	if err := setup.pg.db.QueryRow(`SELECT count(*) FROM payment_provider_events WHERE payment_request_id=$1`, request.ID).Scan(&providerEvents); err != nil {
		t.Fatal(err)
	}
	if settlements != 1 || reconcileEvents != 1 || providerEvents != 1 {
		t.Fatalf("settlements=%d reconcileAuditRows=%d providerEvents=%d, want one each", settlements, reconcileEvents, providerEvents)
	}

	// A second reconciliation cycle sees no due requests and settles nothing.
	report, err = reconciler.Cycle(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if report.Claimed != 0 || report.Paid != 0 {
		t.Fatalf("idempotent replay report = %#v", report)
	}
	var finalSettlements int
	if err := setup.pg.db.QueryRow(`SELECT count(*) FROM settlements WHERE group_id=$1`, setup.group.ID).Scan(&finalSettlements); err != nil {
		t.Fatal(err)
	}
	if finalSettlements != 1 {
		t.Fatalf("replay created a second settlement: %d", finalSettlements)
	}
}

func TestReconciliationReschedulesPendingProviderState(t *testing.T) {
	t.Parallel()
	setup := paymentRevalidationFixture(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	request := requestPayment(t, setup, "reconcile-pending-1", 50)
	makeDue(t, setup, request.ID)

	repo, err := payments.Open(ctx, setup.pg.dbURL)
	if err != nil {
		t.Fatal(err)
	}
	defer repo.Close()
	reconciler := payments.NewReconciler(setup.provider, repo)
	report, err := reconciler.Cycle(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if report.Retryable != 1 || report.Paid != 0 {
		t.Fatalf("reconciliation report = %#v", report)
	}
	if status := requestStatus(t, setup, request.ID); status != "PENDING" {
		t.Fatalf("payment request status = %q, want PENDING", status)
	}
	var settlements int
	if err := setup.pg.db.QueryRow(`SELECT count(*) FROM settlements WHERE group_id=$1`, setup.group.ID).Scan(&settlements); err != nil {
		t.Fatal(err)
	}
	if settlements != 0 {
		t.Fatalf("pending provider state created %d settlements", settlements)
	}
	// The claimed row is postponed so later claims cannot double-process it.
	var attempts int
	var reconcileAfter any
	if err := setup.pg.db.QueryRow(`SELECT reconcile_attempts, reconcile_after FROM payment_requests WHERE id=$1`, request.ID).Scan(&attempts, &reconcileAfter); err != nil {
		t.Fatal(err)
	}
	if attempts != 0 || reconcileAfter == nil {
		t.Fatalf("claim bookkeeping attempts=%d reconcile_after=%#v", attempts, reconcileAfter)
	}
}

func TestReconciliationClosesFailedProviderState(t *testing.T) {
	t.Parallel()
	setup := paymentRevalidationFixture(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	request := requestPayment(t, setup, "reconcile-failed-1", 50)
	makeDue(t, setup, request.ID)
	provider := &reconciliationProvider{states: map[string]payments.ProviderPayment{
		request.ProviderRef: {Status: payments.StatusFailed},
	}}

	repo, err := payments.Open(ctx, setup.pg.dbURL)
	if err != nil {
		t.Fatal(err)
	}
	defer repo.Close()
	report, err := payments.NewReconciler(provider, repo).Cycle(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if report.Terminal != 1 {
		t.Fatalf("reconciliation report = %#v", report)
	}
	if status := requestStatus(t, setup, request.ID); status != "FAILED" {
		t.Fatalf("payment request status = %q, want FAILED", status)
	}
	var settlements int
	if err := setup.pg.db.QueryRow(`SELECT count(*) FROM settlements WHERE group_id=$1`, setup.group.ID).Scan(&settlements); err != nil {
		t.Fatal(err)
	}
	if settlements != 0 {
		t.Fatalf("failed provider state created %d settlements", settlements)
	}
}

func TestReconciliationRecordsMismatchForDivergentProviderPayment(t *testing.T) {
	t.Parallel()
	setup := paymentRevalidationFixture(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	request := requestPayment(t, setup, "reconcile-mismatch-1", 50)
	makeDue(t, setup, request.ID)
	provider := &reconciliationProvider{states: map[string]payments.ProviderPayment{
		request.ProviderRef: {
			ProviderRef:     request.ProviderRef,
			ProviderEventID: "pe_divergent",
			Status:          payments.StatusPaid,
			AmountCents:     4999,
			Currency:        "MXN",
		},
	}}

	repo, err := payments.Open(ctx, setup.pg.dbURL)
	if err != nil {
		t.Fatal(err)
	}
	defer repo.Close()
	reconciler := payments.NewReconciler(provider, repo)
	report, err := reconciler.Cycle(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if report.Mismatch != 1 || report.Paid != 0 {
		t.Fatalf("reconciliation report = %#v", report)
	}
	if status := requestStatus(t, setup, request.ID); status != "PENDING" {
		t.Fatalf("payment request status = %q, want PENDING (needs manual review)", status)
	}
	var settlements int
	if err := setup.pg.db.QueryRow(`SELECT count(*) FROM settlements WHERE group_id=$1`, setup.group.ID).Scan(&settlements); err != nil {
		t.Fatal(err)
	}
	if settlements != 0 {
		t.Fatalf("divergent provider payment created %d settlements", settlements)
	}
	var mismatches int
	if err := setup.pg.db.QueryRow(`SELECT count(*) FROM payment_reconcile_events WHERE payment_request_id=$1 AND outcome='MISMATCH'`, request.ID).Scan(&mismatches); err != nil {
		t.Fatal(err)
	}
	if mismatches != 1 {
		t.Fatalf("mismatch audit rows = %d, want 1", mismatches)
	}
}

// TestClaimLeaseExpiresAfterCrashedWorker ensures a claimed-but-never-completed
// request becomes claimable again once its lease passes.
func TestClaimLeaseExpiresAfterCrashedWorker(t *testing.T) {
	t.Parallel()
	setup := paymentRevalidationFixture(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	request := requestPayment(t, setup, "reconcile-lease-1", 50)
	makeDue(t, setup, request.ID)

	repo, err := payments.Open(ctx, setup.pg.dbURL)
	if err != nil {
		t.Fatal(err)
	}
	defer repo.Close()
	now := time.Now().UTC().Add(12 * time.Hour) // past the creation grace
	first, err := repo.ClaimStalePending(ctx, now, now, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(first) != 1 || first[0].ID != request.ID {
		t.Fatalf("first claim = %#v", first)
	}
	// Lease equals the claim time here, so it is already expired: the next
	// worker claims the same request again after the crashed one.
	second, err := repo.ClaimStalePending(ctx, now, now.Add(time.Minute), 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(second) != 1 || second[0].ID != request.ID {
		t.Fatalf("recovery claim = %#v, want the same request reclaimed", second)
	}
}

