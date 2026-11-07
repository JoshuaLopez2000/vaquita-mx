package payments

import (
	"context"
	"fmt"
	"sync"
	"testing"
	"time"
)

type fakeStore struct {
	mu       sync.Mutex
	claims   []StoredRequest // each pop is one due request
	attempts map[string]int
	parked   map[string]bool
	terminal map[string]Status
	complete []string // request ids completed by provider
	results  []string // "outcome:request" audit rows
}

func newFakeStore(requests ...StoredRequest) *fakeStore {
	return &fakeStore{
		claims:   append([]StoredRequest{}, requests...),
		attempts: map[string]int{},
		parked:   map[string]bool{},
		terminal: map[string]Status{},
	}
}

func (s *fakeStore) ClaimStalePending(_ context.Context, _, _ time.Time, limit int) ([]StoredRequest, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	count := limit
	if count > len(s.claims) {
		count = len(s.claims)
	}
	claimed := append([]StoredRequest{}, s.claims[:count]...)
	s.claims = s.claims[count:]
	for i := range claimed {
		claimed[i].Attempts = s.attempts[claimed[i].ID]
	}
	return claimed, nil
}

// Requeue pushes a request back into the claim pool, simulating the next
// reconciliation cycle after its backoff elapses.
func (s *fakeStore) Requeue(request StoredRequest) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.claims = append(s.claims, request)
}

func (s *fakeStore) CompleteByProvider(_ context.Context, requestID, _ string) (StoredRequest, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.complete = append(s.complete, requestID)
	return StoredRequest{}, true, nil
}

func (s *fakeStore) MarkTerminal(_ context.Context, requestID string, status Status) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.terminal[requestID] = status
	return nil
}

func (s *fakeStore) MarkReconcileResult(_ context.Context, requestID string, attempts int, until *time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.attempts[requestID] = attempts
	if until == nil {
		s.parked[requestID] = true
	}
	return nil
}

func (s *fakeStore) RecordReconcile(_ context.Context, requestID, provider, outcome, detail string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.results = append(s.results, outcome+":"+requestID)
	return nil
}

func (s *fakeStore) completedTimes(requestID string) int {
	s.mu.Lock()
	defer s.mu.Unlock()
	count := 0
	for _, id := range s.complete {
		if id == requestID {
			count++
		}
	}
	return count
}

func reconcilerForTests(provider Provider, store *fakeStore) *Reconciler {
	reconciler := NewReconciler(provider, store)
	reconciler.BackoffBase = time.Minute
	reconciler.BackoffCap = time.Minute
	reconciler.MaxAttempts = 5
	return reconciler
}

func pendingStored(id string) StoredRequest {
	return StoredRequest{
		PaymentRequest:   PaymentRequest{ID: id, ProviderRef: "sreq_" + id, CorrelationID: "corr-" + id, AmountCents: 5000, Currency: "MXN", Provider: "fake"},
		CreditorMemberID: "member-1",
	}
}

type fakeProvider struct {
	states map[string]ProviderPayment
	err    error
	errs   map[string]error
}

func (p *fakeProvider) Name() string { return "fake" }

func (p *fakeProvider) CreateRequest(_ context.Context, _ CreateRequest) (PaymentRequest, error) {
	return PaymentRequest{}, nil
}

func (p *fakeProvider) Lookup(_ context.Context, providerRef string) (ProviderPayment, error) {
	if err, exists := p.errs[providerRef]; exists {
		return ProviderPayment{}, err
	}
	if p.err != nil {
		return ProviderPayment{}, p.err
	}
	state, exists := p.states[providerRef]
	if !exists {
		return ProviderPayment{}, ErrProviderUnknown
	}
	return state, nil
}

func TestReconcilerConfirmsLostPaidCallbackExactlyOnce(t *testing.T) {
	request := pendingStored("pr-1")
	paid := ProviderPayment{
		ProviderRef:     request.ProviderRef,
		ProviderEventID: "pe_event",
		ReceiverRef:     request.CreditorMemberID,
		CorrelationID:   request.CorrelationID,
		AmountCents:     request.AmountCents,
		Currency:        "MXN",
		Status:          StatusPaid,
	}
	store := newFakeStore(request)
	provider := &fakeProvider{states: map[string]ProviderPayment{request.ProviderRef: paid}}
	reconciler := reconcilerForTests(provider, store)

	report, err := reconciler.Cycle(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if report.Claimed != 1 || report.Paid != 1 {
		t.Fatalf("first cycle report = %#v", report)
	}
	if completed := store.completedTimes(request.ID); completed != 1 {
		t.Fatalf("completed calls = %d, want exactly one", completed)
	}

	// The same provider state replays: reconciliation settles nothing again.
	report, err = reconciler.Cycle(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if report.Claimed != 0 || report.Paid != 0 {
		t.Fatalf("second cycle report = %#v, want an empty idempotent cycle", report)
	}
	if completed := store.completedTimes(request.ID); completed != 1 {
		t.Fatalf("completed calls after replay = %d, want one settlement only", completed)
	}
}

func TestReconcilerDistributesClaimsUnderConcurrentJobs(t *testing.T) {
	requests := make([]StoredRequest, 0, 6)
	states := map[string]ProviderPayment{}
	for index := range 6 {
		request := pendingStored(fmt.Sprintf("pr-%d", index))
		requests = append(requests, request)
		states[request.ProviderRef] = ProviderPayment{
			ProviderRef:     request.ProviderRef,
			ProviderEventID: "pe_" + request.ID,
			ReceiverRef:     request.CreditorMemberID,
			CorrelationID:   request.CorrelationID,
			AmountCents:     request.AmountCents,
			Currency:        "MXN",
			Status:          StatusPaid,
		}
	}
	store := newFakeStore(requests...)
	provider := &fakeProvider{states: states}

	var wg sync.WaitGroup
	for range 2 {
		reconciler := reconcilerForTests(provider, store)
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, err := reconciler.Cycle(context.Background()); err != nil {
				t.Errorf("concurrent cycle error: %v", err)
			}
		}()
	}
	wg.Wait()

	for _, request := range requests {
		if completed := store.completedTimes(request.ID); completed != 1 {
			t.Fatalf("request %q completed %d times across concurrent jobs, want exactly once", request.ID, completed)
		}
	}
}

func TestReconcilerRetriesProviderTimeoutsWithBackoff(t *testing.T) {
	request := pendingStored("pr-2")
	store := newFakeStore(request)
	provider := &fakeProvider{err: ErrProviderUnavailable}
	reconciler := reconcilerForTests(provider, store)

	report, err := reconciler.Cycle(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if report.Retryable != 1 {
		t.Fatalf("cycle report = %#v", report)
	}
	if store.attempts[request.ID] != 1 {
		t.Fatalf("attempts = %d, want 1", store.attempts[request.ID])
	}
	if store.parked[request.ID] {
		t.Fatal("first provider timeout parked the request")
	}
	if store.completedTimes(request.ID) != 0 {
		t.Fatal("provider timeout completed a settlement")
	}
}

func TestReconcilerClosesTerminalProviderStates(t *testing.T) {
	request := pendingStored("pr-3")
	store := newFakeStore(request)
	failed := ProviderPayment{ProviderRef: request.ProviderRef, Status: StatusFailed}
	provider := &fakeProvider{states: map[string]ProviderPayment{request.ProviderRef: failed}}
	reconciler := reconcilerForTests(provider, store)

	report, err := reconciler.Cycle(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if report.Terminal != 1 {
		t.Fatalf("cycle report = %#v", report)
	}
	if store.terminal[request.ID] != StatusFailed {
		t.Fatalf("terminal status = %q, want FAILED", store.terminal[request.ID])
	}
	if store.completedTimes(request.ID) != 0 {
		t.Fatal("terminal provider state completed a settlement")
	}
}

func TestReconcilerFlagsMismatchesAndParksAfterMaxAttempts(t *testing.T) {
	request := pendingStored("pr-4")
	// The provider paid a different amount: the request can never settle
	// safely and needs manual review after the bounded attempts.
	diverged := ProviderPayment{
		ProviderRef:     request.ProviderRef,
		ProviderEventID: "pe_event",
		ReceiverRef:     request.CreditorMemberID,
		CorrelationID:   request.CorrelationID,
		AmountCents:     4999,
		Currency:        "MXN",
		Status:          StatusPaid,
	}
	store := newFakeStore(request)
	provider := &fakeProvider{states: map[string]ProviderPayment{request.ProviderRef: diverged}}
	reconciler := reconcilerForTests(provider, store)

	for cycle := 0; cycle < reconciler.MaxAttempts-1; cycle++ {
		report, err := reconciler.Cycle(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		if report.Mismatch != 1 || report.Manual != 0 {
			t.Fatalf("cycle %d report = %#v, want one unmatched attempt", cycle+1, report)
		}
		store.Requeue(request)
		if store.completedTimes(request.ID) != 0 {
			t.Fatal("mismatch completed a settlement")
		}
	}
	report, err := reconciler.Cycle(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if report.Manual != 1 {
		t.Fatalf("park cycle report = %#v, want one manual review outcome", report)
	}
	if !store.parked[request.ID] {
		t.Fatal("repeated mismatches did not park the request for manual review")
	}
}

func TestReconcilerReschedulesPendingProviderStateWithoutExhaustingAttempts(t *testing.T) {
	request := pendingStored("pr-5")
	pending := ProviderPayment{
		ProviderRef:   request.ProviderRef,
		Status:        StatusPending,
		AmountCents:   request.AmountCents,
		Currency:      "MXN",
		CorrelationID: request.CorrelationID,
		ReceiverRef:   request.CreditorMemberID,
	}
	store := newFakeStore(request)
	provider := &fakeProvider{states: map[string]ProviderPayment{request.ProviderRef: pending}}
	reconciler := reconcilerForTests(provider, store)

	for cycle := 0; cycle < reconciler.MaxAttempts+2; cycle++ {
		report, err := reconciler.Cycle(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		if report.Retryable != 1 {
			t.Fatalf("cycle %d report = %#v", cycle+1, report)
		}
		store.Requeue(request)
	}
	if store.attempts[request.ID] != 0 {
		t.Fatalf("plain provider-pending states inflated attempts to %d", store.attempts[request.ID])
	}
	if store.parked[request.ID] {
		t.Fatal("a plain provider-pending state parked the request")
	}
}

func TestReconcilerUnknownProviderRefClosesExpired(t *testing.T) {
	request := pendingStored("pr-6")
	store := newFakeStore(request)
	provider := &fakeProvider{states: map[string]ProviderPayment{}}
	reconciler := reconcilerForTests(provider, store)

	report, err := reconciler.Cycle(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if report.Terminal != 1 {
		t.Fatalf("cycle report = %#v", report)
	}
	if store.terminal[request.ID] != StatusExpired {
		t.Fatalf("terminal status = %q, want EXPIRED", store.terminal[request.ID])
	}
}
