package main

import (
	"net/http"
	"sort"
	"testing"

	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/groups"
)

func TestSharedCreditorCanConfirmReceivedPaymentIdempotently(t *testing.T) {
	t.Parallel()
	setup := partialSettlementFixture(t)
	endpoint := setup.baseURL + "/api/v1/groups/" + setup.group.ID + "/settlements/received"
	payload := map[string]any{
		"debtor_member_id": setup.debtorMember.ID,
		"amount_cents":     30,
	}

	var partial groups.Group
	doJSONHeaders(t, setup.client, http.MethodPost, endpoint, setup.ownerToken, payload,
		map[string]string{"Idempotency-Key": "received-partial"}, http.StatusCreated, &partial)
	var replay groups.Group
	doJSONHeaders(t, setup.client, http.MethodPost, endpoint, setup.ownerToken, payload,
		map[string]string{"Idempotency-Key": "received-partial"}, http.StatusCreated, &replay)
	assertBalance(t, partial, setup.ownerMember.ID, 20)
	assertBalance(t, replay, setup.debtorMember.ID, -20)
	if len(replay.Settlements) != 1 || replay.Settlements[0].ID != partial.Settlements[0].ID {
		t.Fatalf("replayed settlements = %#v, want the stored result %#v", replay.Settlements, partial.Settlements)
	}

	var conflict apiError
	doJSONHeaders(t, setup.client, http.MethodPost, endpoint, setup.ownerToken, map[string]any{
		"debtor_member_id": setup.debtorMember.ID,
		"amount_cents":     20,
	}, map[string]string{"Idempotency-Key": "received-partial"}, http.StatusConflict, &conflict)
	if conflict.Code != "idempotency_key_conflict" {
		t.Fatalf("conflicting retry error = %#v", conflict)
	}

	// A debtor cannot use the receipt command to confirm a payment to themself.
	doJSON(t, setup.client, http.MethodPost, endpoint, setup.debtorToken, map[string]string{
		"debtor_member_id": setup.debtorMember.ID,
	}, http.StatusUnprocessableEntity, nil)

	var full groups.Group
	doJSONHeaders(t, setup.client, http.MethodPost, endpoint, setup.ownerToken, map[string]string{
		"debtor_member_id": setup.debtorMember.ID,
	}, map[string]string{"Idempotency-Key": "received-remainder"}, http.StatusCreated, &full)
	assertBalance(t, full, setup.ownerMember.ID, 0)
	assertBalance(t, full, setup.debtorMember.ID, 0)
	amounts := make([]int64, len(full.Settlements))
	for i, settlement := range full.Settlements {
		amounts[i] = settlement.AmountCents
	}
	sort.Slice(amounts, func(i, j int) bool { return amounts[i] < amounts[j] })
	if len(amounts) != 2 || amounts[0] != 20 || amounts[1] != 30 {
		t.Fatalf("full settlement amounts = %v, want the 30-centavo payment and 20-centavo remainder", amounts)
	}
}

func TestPersonalGroupOwnerCanConfirmReceivedPayment(t *testing.T) {
	t.Parallel()
	test := newPostgreSQLApplication(t)
	client, baseURL := test.server.Client(), test.server.URL
	owner := registerUser(t, client, baseURL, "Ana", "personal-received@example.test", "+525511140001")
	var group groups.Group
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/groups", owner.Token, map[string]any{
		"name": "Personal", "emoji": "P", "visibility": "personal",
		"member_names": []string{"Beto"},
	}, http.StatusCreated, &group)
	ownerMember, debtorMember := group.Members[0], group.Members[1]
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/groups/"+group.ID+"/expenses", owner.Token, map[string]any{
		"description":     "Cena",
		"amount_cents":    100,
		"payer_id":        ownerMember.ID,
		"participant_ids": []string{ownerMember.ID, debtorMember.ID},
		"split_mode":      "equal",
	}, http.StatusCreated, nil)

	var settled groups.Group
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/groups/"+group.ID+"/settlements/received", owner.Token, map[string]any{
		"debtor_member_id": debtorMember.ID,
		"amount_cents":     25,
	}, http.StatusCreated, &settled)
	assertBalance(t, settled, ownerMember.ID, 25)
	assertBalance(t, settled, debtorMember.ID, -25)
	if len(settled.Settlements) != 1 ||
		settled.Settlements[0].FromMemberID != debtorMember.ID ||
		settled.Settlements[0].ToMemberID != ownerMember.ID {
		t.Fatalf("personal group settlement = %#v, want debtor-to-owner", settled.Settlements)
	}
}
