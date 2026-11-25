package main

import (
	"context"
	"net/http"
	"net/url"
	"testing"
	"time"

	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/groups"
	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/payments"
)

func TestPaymentRequestsListGetPaginationAndScoping(t *testing.T) {
	t.Parallel()
	test := newPostgreSQLApplication(t)
	client := test.server.Client()

	ana := registerUser(t, client, test.server.URL, "Ana", "ana-prlist@example.test", "+525581001100")
	beto := registerUser(t, client, test.server.URL, "Beto", "beto-prlist@example.test", "+525582002200")
	carla := registerUser(t, client, test.server.URL, "Carla", "carla-prlist@example.test", "+525583003300")
	outsider := registerUser(t, client, test.server.URL, "Diego", "diego-prlist@example.test", "+525584004400")

	var shared groups.Group
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups", ana.Token, map[string]any{
		"name":       "Depa",
		"emoji":      "🏠",
		"visibility": "shared",
		"members": []map[string]string{
			{"name": "Beto", "phone": "+525582002200"},
			{"name": "Carla", "phone": "+525583003300"},
		},
	}, http.StatusCreated, &shared)
	anaM := findMember(t, shared, ana.User.ID)
	betoM := findMember(t, shared, beto.User.ID)
	carlaM := findMember(t, shared, carla.User.ID)
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/group-invitations/"+shared.ID+"/response", beto.Token, map[string]bool{"accept": true}, http.StatusNoContent, nil)
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/group-invitations/"+shared.ID+"/response", carla.Token, map[string]bool{"accept": true}, http.StatusNoContent, nil)

	// Ana pays 900 equally across Ana, Beto, Carla -> Beto owes Ana 300, Carla owes Ana 300.
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+shared.ID+"/expenses", ana.Token, map[string]any{
		"description":     "Luz",
		"amount_cents":    900,
		"payer_id":        anaM.ID,
		"participant_ids": []string{anaM.ID, betoM.ID, carlaM.ID},
		"split_mode":      "equal",
	}, http.StatusCreated, nil)

	// Ana creates payment request #1 to Beto with localized Spanish description.
	var prBeto payments.StoredRequest
	doJSONHeaders(t, client, http.MethodPost, test.server.URL+"/api/v1/payment-requests", ana.Token, map[string]any{
		"group_id":     shared.ID,
		"debtor_id":    betoM.ID,
		"amount_cents": 300,
		"currency":     "MXN",
		"description":  "Liquidación de saldo del grupo",
	}, map[string]string{"Idempotency-Key": "pr-list-beto-1"}, http.StatusCreated, &prBeto)
	if prBeto.Description != "Liquidación de saldo del grupo" {
		t.Fatalf("created description = %q", prBeto.Description)
	}

	// Ana creates payment request #2 to Carla.
	var prCarla payments.StoredRequest
	doJSONHeaders(t, client, http.MethodPost, test.server.URL+"/api/v1/payment-requests", ana.Token, map[string]any{
		"group_id":     shared.ID,
		"debtor_id":    carlaM.ID,
		"amount_cents": 300,
		"currency":     "MXN",
		"description":  "Pago de luz",
	}, map[string]string{"Idempotency-Key": "pr-list-carla-1"}, http.StatusCreated, &prCarla)

	// 1. Authorization & scoping:
	// Carla (third member of the same group) sees ONLY her own request, never Ana->Beto's!
	var carlaList payments.ListPage
	doJSON(t, client, http.MethodGet, test.server.URL+"/api/v1/payment-requests", carla.Token, nil, http.StatusOK, &carlaList)
	if len(carlaList.Requests) != 1 || carlaList.Requests[0].ID != prCarla.ID || carlaList.Requests[0].Role != payments.OrientationDebtor {
		t.Fatalf("carla list = %#v, want only prCarla as debtor", carlaList.Requests)
	}
	// Carla cannot read Ana->Beto's request directly -> 404.
	doJSON(t, client, http.MethodGet, test.server.URL+"/api/v1/payment-requests/"+prBeto.ID, carla.Token, nil, http.StatusNotFound, nil)
	// Outsider gets empty list, 404 on hidden group_id, and 404 on direct GET.
	var outsiderList payments.ListPage
	doJSON(t, client, http.MethodGet, test.server.URL+"/api/v1/payment-requests", outsider.Token, nil, http.StatusOK, &outsiderList)
	if len(outsiderList.Requests) != 0 {
		t.Fatalf("outsider list = %#v, want empty", outsiderList.Requests)
	}
	doJSON(t, client, http.MethodGet, test.server.URL+"/api/v1/payment-requests?group_id="+shared.ID, outsider.Token, nil, http.StatusNotFound, nil)
	doJSON(t, client, http.MethodGet, test.server.URL+"/api/v1/payment-requests/"+prBeto.ID, outsider.Token, nil, http.StatusNotFound, nil)

	// 2. Direct GET returns enriched metadata for both creditor and debtor.
	var betoView payments.StoredRequest
	doJSON(t, client, http.MethodGet, test.server.URL+"/api/v1/payment-requests/"+prBeto.ID, beto.Token, nil, http.StatusOK, &betoView)
	if betoView.Role != payments.OrientationDebtor || betoView.GroupName != "Depa" || betoView.CreditorName != "Ana" || betoView.DebtorName != "Beto" || betoView.Description != "Liquidación de saldo del grupo" {
		t.Fatalf("unexpected betoView: %#v", betoView)
	}

	// 3. Cursor pagination for Ana (2 requests as creditor): limit=1 yields page 1 + cursor -> page 2.
	var page1 payments.ListPage
	doJSON(t, client, http.MethodGet, test.server.URL+"/api/v1/payment-requests?orientation=creditor&status=PENDING&limit=1", ana.Token, nil, http.StatusOK, &page1)
	if len(page1.Requests) != 1 || page1.NextCursor == "" {
		t.Fatalf("page1 = %#v, want 1 item and next_cursor", page1)
	}
	var page2 payments.ListPage
	doJSON(t, client, http.MethodGet, test.server.URL+"/api/v1/payment-requests?orientation=creditor&status=PENDING&limit=1&cursor="+url.QueryEscape(page1.NextCursor), ana.Token, nil, http.StatusOK, &page2)
	if len(page2.Requests) != 1 || page2.NextCursor != "" || page2.Requests[0].ID == page1.Requests[0].ID {
		t.Fatalf("page2 = %#v, want distinct second item and empty next_cursor", page2)
	}
	// Ana as debtor has 0 requests.
	var anaDebtor payments.ListPage
	doJSON(t, client, http.MethodGet, test.server.URL+"/api/v1/payment-requests?orientation=debtor", ana.Token, nil, http.StatusOK, &anaDebtor)
	if len(anaDebtor.Requests) != 0 {
		t.Fatalf("ana debtor list = %#v, want empty", anaDebtor.Requests)
	}

	// 4. Filter validation errors return 422.
	for _, qs := range []string{"status=UNKNOWN", "orientation=other", "limit=0", "limit=101", "limit=abc", "cursor=not-valid"} {
		doJSON(t, client, http.MethodGet, test.server.URL+"/api/v1/payment-requests?"+qs, ana.Token, nil, http.StatusUnprocessableEntity, nil)
	}

	// 5. Complete Beto's simulated payment -> transitions to PAID, appears under status=PAID.
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/payment-requests/"+prBeto.ID+"/simulate", beto.Token, map[string]string{
		"provider_event_id": "pe_beto_complete_1",
	}, http.StatusCreated, nil)
	var paidList payments.ListPage
	doJSON(t, client, http.MethodGet, test.server.URL+"/api/v1/payment-requests?status=PAID&group_id="+shared.ID, beto.Token, nil, http.StatusOK, &paidList)
	if len(paidList.Requests) != 1 || paidList.Requests[0].ID != prBeto.ID || paidList.Requests[0].PaidAt == nil || paidList.Requests[0].SettlementID == "" {
		t.Fatalf("paidList = %#v, want prBeto PAID with paid_at and settlement_id", paidList.Requests)
	}

	// 6. Expired pending request is surfaced as EXPIRED even before reconciliation marks the row.
	if _, err := test.db.ExecContext(context.Background(), `UPDATE payment_requests SET expires_at=$2 WHERE id=$1`, prCarla.ID, time.Now().UTC().Add(-time.Minute)); err != nil {
		t.Fatal(err)
	}
	var expiredView payments.StoredRequest
	doJSON(t, client, http.MethodGet, test.server.URL+"/api/v1/payment-requests/"+prCarla.ID, carla.Token, nil, http.StatusOK, &expiredView)
	if expiredView.Status != payments.StatusExpired {
		t.Fatalf("expiredView.Status = %q, want EXPIRED", expiredView.Status)
	}
	var expiredList payments.ListPage
	doJSON(t, client, http.MethodGet, test.server.URL+"/api/v1/payment-requests?status=EXPIRED", carla.Token, nil, http.StatusOK, &expiredList)
	if len(expiredList.Requests) != 1 || expiredList.Requests[0].ID != prCarla.ID {
		t.Fatalf("expiredList = %#v, want prCarla", expiredList.Requests)
	}
	var pendingList payments.ListPage
	doJSON(t, client, http.MethodGet, test.server.URL+"/api/v1/payment-requests?status=PENDING", carla.Token, nil, http.StatusOK, &pendingList)
	if len(pendingList.Requests) != 0 {
		t.Fatalf("pendingList = %#v, want empty after expiry", pendingList.Requests)
	}
}
