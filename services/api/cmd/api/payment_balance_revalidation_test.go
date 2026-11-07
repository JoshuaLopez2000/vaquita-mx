package main

import (
	"database/sql"
	"net/http"
	"testing"

	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/groups"
	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/payments"
)

type paymentRevalidationSetup struct {
	pg           postgresApplication
	client       *http.Client
	baseURL      string
	group        groups.Group
	creditor     groups.Member
	debtor       groups.Member
	creditorTok  string
	debtorTok    string
}

// paymentRevalidationFixture builds a creditor, an accepted debtor, and a
// 100-centavo expense split 50/50, so the debtor owes the creditor exactly 50
// centavos riding the deterministic settlement projection.
func paymentRevalidationFixture(t *testing.T) paymentRevalidationSetup {
	t.Helper()
	test := newPostgreSQLApplication(t)
	client, baseURL := test.server.Client(), test.server.URL
	creditor := registerUser(t, client, baseURL, "Ana", "revalid-ana@example.test", "+525511115001")
	debtor := registerUser(t, client, baseURL, "Beto", "revalid-beto@example.test", "+525511115002")
	var group groups.Group
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/groups", creditor.Token, map[string]any{
		"name": "Revalidacion", "emoji": "V", "visibility": "shared",
		"members": []map[string]string{{"name": "Beto", "phone": "+525511115002"}},
	}, http.StatusCreated, &group)
	creditorMember, debtorMember := findMember(t, group, creditor.User.ID), findMember(t, group, debtor.User.ID)
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/group-invitations/"+group.ID+"/response", debtor.Token, map[string]bool{"accept": true}, http.StatusNoContent, nil)
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/groups/"+group.ID+"/expenses", creditor.Token, map[string]any{
		"description":     "Cena",
		"amount_cents":    100,
		"payer_id":        creditorMember.ID,
		"participant_ids": []string{creditorMember.ID, debtorMember.ID},
		"split_mode":      "equal",
	}, http.StatusCreated, nil)
	return paymentRevalidationSetup{test, client, baseURL, group, creditorMember, debtorMember, creditor.Token, debtor.Token}
}

// requestPayment creates a payment request from the creditor for the debtor.
// Amounts must match the exact outstanding balance at creation time.
func requestPayment(t *testing.T, setup paymentRevalidationSetup, key string, amount int64) payments.StoredRequest {
	t.Helper()
	var request payments.StoredRequest
	doJSONHeaders(t, setup.client, http.MethodPost, setup.baseURL+"/api/v1/payment-requests", setup.creditorTok, map[string]any{
		"group_id":     setup.group.ID,
		"debtor_id":    setup.debtor.ID,
		"amount_cents": amount,
		"currency":     "MXN",
		"description":  "simulated only",
	}, map[string]string{"Idempotency-Key": key}, http.StatusCreated, &request)
	if request.Status != payments.StatusPending {
		t.Fatalf("created payment request status = %q, want %q", request.Status, payments.StatusPending)
	}
	return request
}

func settleRequested(t *testing.T, setup paymentRevalidationSetup, fromToken string, amount int64) {
	t.Helper()
	doJSON(t, setup.client, http.MethodPost, setup.baseURL+"/api/v1/groups/"+setup.group.ID+"/settlements", fromToken, map[string]any{
		"member_id":    setup.creditor.ID,
		"amount_cents": amount,
	}, http.StatusCreated, nil)
}

func partiallyComplete(t *testing.T, setup paymentRevalidationSetup, debtorToken, requestID, eventID string) {
	t.Helper()
	doJSON(t, setup.client, http.MethodPost, setup.baseURL+"/api/v1/payment-requests/"+requestID+"/simulate", debtorToken,
		map[string]string{"provider_event_id": eventID}, http.StatusCreated, nil)
}

func outstandingAnnotation(t *testing.T, setup paymentRevalidationSetup, requestID string) (int64, bool) {
	t.Helper()
	var outstanding sql.NullInt64
	if err := setup.pg.db.QueryRow(`SELECT outstanding_cents FROM payment_provider_events WHERE payment_request_id=$1`, requestID).Scan(&outstanding); err != nil {
		t.Fatal(err)
	}
	return outstanding.Int64, outstanding.Valid
}

func groupAfter(t *testing.T, setup paymentRevalidationSetup, token string) groups.Group {
	t.Helper()
	var listing struct {
		Groups []groups.Group `json:"groups"`
	}
	doJSON(t, setup.client, http.MethodGet, setup.baseURL+"/api/v1/groups", token, nil, http.StatusOK, &listing)
	for _, group := range listing.Groups {
		if group.ID == setup.group.ID {
			return group
		}
	}
	t.Fatalf("group %q not found in listing %#v", setup.group.ID, listing.Groups)
	return groups.Group{}
}

func TestPaymentCompletionAnnotatesOutstandingAtCallbackTime(t *testing.T) {
	t.Parallel()
	setup := paymentRevalidationFixture(t)
	request := requestPayment(t, setup, "revalid-exact-1", 50)
	partiallyComplete(t, setup, setup.debtorTok, request.ID, "revalid-event-exact")
	if annotated, present := outstandingAnnotation(t, setup, request.ID); !present || annotated != 50 {
		t.Fatalf("outstanding annotation = (%d, %v), want (50, true)", annotated, present)
	}
	settled := groupAfter(t, setup, setup.creditorTok)
	assertBalance(t, settled, setup.creditor.ID, 0)
	assertBalance(t, settled, setup.debtor.ID, 0)
}

// The product decision: payment amounts are never capped by the ledger a
// completion recreates. When the outstanding debt shrank between creation and
// completion the payment completes fully and the excess becomes the receiver's
// debt to the payer in the next projection.
func TestPaymentAboveOutstandingCompletesWithInvertedDebt(t *testing.T) {
	t.Parallel()
	setup := paymentRevalidationFixture(t)
	request := requestPayment(t, setup, "revalid-over-1", 50)
	// The debt shrinks to 20 before the callback arrives.
	settleRequested(t, setup, setup.debtorTok, 30)
	partiallyComplete(t, setup, setup.debtorTok, request.ID, "revalid-event-over")
	if annotated, present := outstandingAnnotation(t, setup, request.ID); !present || annotated != 20 {
		t.Fatalf("outstanding annotation = (%d, %v), want (20, true)", annotated, present)
	}
	var settled = groupAfter(t, setup, setup.creditorTok)
	assertBalance(t, settled, setup.creditor.ID, -30)
	assertBalance(t, settled, setup.debtor.ID, 30)
	forward := false
	reverse := false
	for _, relation := range settled.PaymentRelations {
		if relation.FromMemberID == setup.debtor.ID && relation.ToMemberID == setup.creditor.ID {
			forward = true
		}
		if relation.FromMemberID == setup.creditor.ID && relation.ToMemberID == setup.debtor.ID && relation.AmountCents == 30 {
			reverse = true
		}
	}
	if forward || !reverse {
		t.Fatalf("payment relations after overpayment = %#v, want one 30-centavo creditor-to-debtor obligation", settled.PaymentRelations)
	}
}

func TestPaymentAfterFullManualSettlementCompletesWithZeroOutstanding(t *testing.T) {
	t.Parallel()
	setup := paymentRevalidationFixture(t)
	request := requestPayment(t, setup, "revalid-full-1", 50)
	settleRequested(t, setup, setup.debtorTok, 50)
	partiallyComplete(t, setup, setup.debtorTok, request.ID, "revalid-event-full")
	if annotated, present := outstandingAnnotation(t, setup, request.ID); !present || annotated != 0 {
		t.Fatalf("outstanding annotation = (%d, %v), want (0, true)", annotated, present)
	}
	settled := groupAfter(t, setup, setup.creditorTok)
	assertBalance(t, settled, setup.creditor.ID, -50)
	assertBalance(t, settled, setup.debtor.ID, 50)
}
