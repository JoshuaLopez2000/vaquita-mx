package payments

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"
)

// reconcileGrace postpones the first reconciliation of a fresh request, so a
// lost callback window elapses before the job starts querying the provider.
const reconcileGrace = 5 * time.Minute

// ReconcileStore is the persistence side of the reconciliation loop. The real
// implementation is *Repository; tests can substitute it.
type ReconcileStore interface {
	ClaimStalePending(ctx context.Context, claimBefore, leaseUntil time.Time, limit int) ([]StoredRequest, error)
	CompleteByProvider(ctx context.Context, requestID, providerEventID string) (StoredRequest, bool, error)
	MarkTerminal(ctx context.Context, requestID string, status Status) error
	MarkReconcileResult(ctx context.Context, requestID string, attempts int, until *time.Time) error
	RecordReconcile(ctx context.Context, requestID, providerName, outcome, detail string) error
}

// Reconcile outcome names stored in payment_reconcile_events.
const (
	OutcomePaid     = "PAID"
	OutcomeTerminal = "TERMINAL"
	OutcomeMismatch = "MISMATCH"
	OutcomeRetry    = "RETRY"
	OutcomeManual   = "MANUAL"
)

// ReconcileReport summarizes one cycle for metrics and logging.
type ReconcileReport struct {
	Claimed   int
	Paid      int
	Terminal  int
	Mismatch  int
	Retryable int
	Manual    int
}

// Reconciler finds pending payment requests whose provider callback was lost,
// checks the provider through the adapter, and applies valid transitions at
// most once. Server-side provider credentials stay inside the process; client
// payment state is never trusted.
type Reconciler struct {
	provider Provider
	store    ReconcileStore
	logger   *slog.Logger

	// Interval is the recurring cycle period.
	Interval time.Duration
	// Lease is how long one claimed batch stays invisible to other workers.
	Lease time.Duration
	// BackoffBase and BackoffCap bound the exponential retry delay.
	BackoffBase time.Duration
	BackoffCap  time.Duration
	// Batch is the largest claim per cycle.
	Batch int
	// MaxAttempts is how many fruitless provider checks a request gets before
	// reconciliation parks it for manual review.
	MaxAttempts int

	Now func() time.Time
}

func NewReconciler(provider Provider, store ReconcileStore) *Reconciler {
	return &Reconciler{
		provider:    provider,
		store:       store,
		logger:      slog.Default(),
		Interval:    30 * time.Second,
		Lease:       2 * time.Minute,
		BackoffBase: time.Minute,
		BackoffCap:  30 * time.Minute,
		Batch:       25,
		MaxAttempts: 5,
	}
}

// Run cycles until ctx is cancelled. Panics inside one cycle are logged and
// swallowed so a bug cannot kill the reconciliation goroutine.
func (rc *Reconciler) Run(ctx context.Context) {
	logger := rc.logger
	ticker := time.NewTicker(rc.Interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			rc.cycle(ctx, logger)
		}
	}
}

func (rc *Reconciler) cycle(ctx context.Context, logger *slog.Logger) {
	defer func() {
		if recovered := recover(); recovered != nil {
			logger.Error("payment reconciliation cycle panicked", "panic", recovered)
		}
	}()
	report, err := rc.Cycle(ctx)
	if err != nil {
		logger.Error("payment reconciliation cycle failed", "error", err)
		return
	}
	if report.Claimed > 0 {
		logger.Info("payment reconciliation cycle", "claimed", report.Claimed, "paid", report.Paid, "terminal", report.Terminal, "mismatch", report.Mismatch, "retryable", report.Retryable, "manual_review", report.Manual)
	}
}

// Cycle claims due pending requests and reconciles each one exactly once.
func (rc *Reconciler) Cycle(ctx context.Context) (ReconcileReport, error) {
	now := rc.now()
	claims, err := rc.store.ClaimStalePending(ctx, now, now.Add(rc.Lease), rc.Batch)
	if err != nil {
		return ReconcileReport{}, fmt.Errorf("claim stale payment requests: %w", err)
	}
	report := ReconcileReport{Claimed: len(claims)}
	for _, request := range claims {
		outcome := rc.reconcileOne(ctx, request)
		report.count(outcome)
	}
	return report, nil
}

func (rc *Reconciler) reconcileOne(ctx context.Context, request StoredRequest) string {
	state, err := rc.provider.Lookup(ctx, request.ProviderRef)
	if err != nil {
		if errors.Is(err, ErrProviderUnknown) {
			return rc.finishTerminal(ctx, request, StatusExpired, "provider has no record of the request")
		}
		return rc.retry(ctx, request, fmt.Sprintf("provider lookup unavailable: %v", err), true)
	}
	switch state.Status {
	case StatusPaid:
		return rc.confirm(ctx, request, state)
	case StatusPending:
		return rc.retry(ctx, request, "provider still reports the payment pending", false)
	case StatusExpired:
		return rc.finishTerminal(ctx, request, StatusExpired, "provider reports the payment expired")
	case StatusFailed:
		return rc.finishTerminal(ctx, request, StatusFailed, "provider reports the payment failed")
	default:
		return rc.mismatch(ctx, request, fmt.Sprintf("unsupported provider status %q", state.Status))
	}
}

// confirm applies a provider-confirmed PAID transition once and records the
// audit row. Amount, MXN currency, receiver, and correlation ID must match the
// original request before settlement.
func (rc *Reconciler) confirm(ctx context.Context, request StoredRequest, state ProviderPayment) string {
	if state.ProviderRef != request.ProviderRef {
		return rc.mismatch(ctx, request, "provider echoed a different reference")
	}
	if state.AmountCents != request.AmountCents ||
		state.Currency != request.Currency ||
		state.CorrelationID != request.CorrelationID ||
		state.ReceiverRef != request.CreditorMemberID ||
		state.ProviderEventID == "" {
		return rc.mismatch(ctx, request, fmt.Sprintf("provider payment never matched: %#v", state))
	}
	if _, _, err := rc.store.CompleteByProvider(ctx, request.ID, state.ProviderEventID); err != nil {
		rc.logger.Error("provider-confirmed payment completion failed", "request_id", request.ID, "error", err)
		return OutcomeRetry
	}
	if err := rc.store.RecordReconcile(ctx, request.ID, rc.provider.Name(), OutcomePaid, fmt.Sprintf("provider event %q confirmed %d centavos", state.ProviderEventID, state.AmountCents)); err != nil {
		rc.logger.Error("payment reconciliation audit row failed", "request_id", request.ID, "error", err)
	}
	rc.logger.Info("payment request settled by reconciliation", "request_id", request.ID, "provider", rc.provider.Name(), "amount_cents", request.AmountCents)
	return OutcomePaid
}

func (rc *Reconciler) finishTerminal(ctx context.Context, request StoredRequest, status Status, detail string) string {
	if err := rc.store.MarkTerminal(ctx, request.ID, status); err != nil {
		rc.logger.Error("terminal payment request update failed", "request_id", request.ID, "error", err)
		return OutcomeTerminal
	}
	if err := rc.store.RecordReconcile(ctx, request.ID, rc.provider.Name(), OutcomeTerminal, detail); err != nil {
		rc.logger.Error("payment reconciliation audit row failed", "request_id", request.ID, "error", err)
	}
	rc.logger.Info("payment request closed by reconciliation", "request_id", request.ID, "status", status)
	return OutcomeTerminal
}

func (rc *Reconciler) mismatch(ctx context.Context, request StoredRequest, detail string) string {
	rc.logger.Warn("payment request needs manual review", "request_id", request.ID, "reason", detail)
	attempts := request.Attempts + 1
	if err := rc.store.RecordReconcile(ctx, request.ID, rc.provider.Name(), OutcomeMismatch, fmt.Sprintf("%s; attempt %d of %d", detail, attempts, rc.MaxAttempts)); err != nil {
		rc.logger.Error("payment reconciliation audit row failed", "request_id", request.ID, "error", err)
	}
	if attempts >= rc.MaxAttempts {
		rc.park(ctx, request, attempts, detail)
		return OutcomeManual
	}
	return rc.reschedule(ctx, request, attempts, OutcomeMismatch)
}

func (rc *Reconciler) park(ctx context.Context, request StoredRequest, attempts int, detail string) {
	if err := rc.store.RecordReconcile(ctx, request.ID, rc.provider.Name(), OutcomeManual, fmt.Sprintf("%s; reconciliation gave up after %d attempts", detail, attempts)); err != nil {
		rc.logger.Error("payment reconciliation audit row failed", "request_id", request.ID, "error", err)
	}
	if err := rc.store.MarkReconcileResult(ctx, request.ID, attempts, nil); err != nil {
		rc.logger.Error("parking payment request failed", "request_id", request.ID, "error", err)
	}
}

func (rc *Reconciler) retry(ctx context.Context, request StoredRequest, detail string, countAttempt bool) string {
	rc.logger.Info("payment reconciliation rescheduled", "request_id", request.ID, "reason", detail)
	attempts := request.Attempts
	if countAttempt {
		attempts++
		if err := rc.store.RecordReconcile(ctx, request.ID, rc.provider.Name(), OutcomeRetry, fmt.Sprintf("%s; attempt %d of %d", detail, attempts, rc.MaxAttempts)); err != nil {
			rc.logger.Error("payment reconciliation audit row failed", "request_id", request.ID, "error", err)
		}
		if attempts >= rc.MaxAttempts {
			rc.park(ctx, request, attempts, detail)
			return OutcomeManual
		}
	}
	return rc.reschedule(ctx, request, attempts, OutcomeRetry)
}

func (rc *Reconciler) reschedule(ctx context.Context, request StoredRequest, attempts int, outcome string) string {
	now := rc.now()
	until := now.Add(rc.backoff(attempts))
	if err := rc.store.MarkReconcileResult(ctx, request.ID, attempts, &until); err != nil {
		rc.logger.Error("payment reconciliation reschedule failed", "request_id", request.ID, "error", err)
		return outcome
	}
	return outcome
}

func (rc *Reconciler) backoff(attempts int) time.Duration {
	delay := rc.BackoffBase << uint(max(0, attempts-1))
	if delay > rc.BackoffCap || delay <= 0 {
		return rc.BackoffCap
	}
	return delay
}

func (rc *Reconciler) now() time.Time {
	if rc.Now == nil {
		return time.Now().UTC()
	}
	return rc.Now().UTC()
}

func (report *ReconcileReport) count(outcome string) {
	switch outcome {
	case OutcomePaid:
		report.Paid++
	case OutcomeTerminal:
		report.Terminal++
	case OutcomeMismatch:
		report.Mismatch++
	case OutcomeManual:
		report.Manual++
	default:
		report.Retryable++
	}
}
