package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"sync"
	"testing"

	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/groups"
)

type partialSettlementSetup struct {
	pg           postgresApplication
	client       *http.Client
	baseURL      string
	group        groups.Group
	ownerMember  groups.Member
	debtorMember groups.Member
	debtorToken  string
}

// partialSettlementFixture builds one owner, one invited debtor, and a
// single 100-centavo expense the debtor owes the owner entirely (50/50).
func partialSettlementFixture(t *testing.T) partialSettlementSetup {
	t.Helper()
	test := newPostgreSQLApplication(t)
	client, baseURL := test.server.Client(), test.server.URL
	owner := registerUser(t, client, baseURL, "Ana", "partial-ana@example.test", "+525511130001")
	debtor := registerUser(t, client, baseURL, "Beto", "partial-beto@example.test", "+525511130002")
	var group groups.Group
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/groups", owner.Token, map[string]any{
		"name": "Parciales", "emoji": "P", "visibility": "shared",
		"members": []map[string]string{{"name": "Beto", "phone": "+525511130002"}},
	}, http.StatusCreated, &group)
	ownerMember, debtorMember := findMember(t, group, owner.User.ID), findMember(t, group, debtor.User.ID)
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/group-invitations/"+group.ID+"/response", debtor.Token, map[string]bool{"accept": true}, http.StatusNoContent, nil)
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/groups/"+group.ID+"/expenses", owner.Token, map[string]any{
		"description":     "Cena",
		"amount_cents":    100,
		"payer_id":        ownerMember.ID,
		"participant_ids": []string{ownerMember.ID, debtorMember.ID},
		"split_mode":      "equal",
	}, http.StatusCreated, nil)
	return partialSettlementSetup{test, client, baseURL, group, ownerMember, debtorMember, debtor.Token}
}

// settle posts one settlement command exactly as encoded and returns the raw
// outcome, without the helper's status assertion — concurrent tests need to
// classify non-deterministic statuses themselves.
func settle(setup partialSettlementSetup, amount any) (int, string) {
	payload := map[string]any{"member_id": setup.ownerMember.ID}
	if amount != nil {
		payload["amount_cents"] = amount
	}
	encoded, err := json.Marshal(payload)
	if err != nil {
		return 0, err.Error()
	}
	request, err := http.NewRequestWithContext(context.Background(), http.MethodPost, setup.baseURL+"/api/v1/groups/"+setup.group.ID+"/settlements", bytes.NewReader(encoded))
	if err != nil {
		return 0, err.Error()
	}
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Authorization", "Bearer "+setup.debtorToken)
	response, err := setup.client.Do(request)
	if err != nil {
		return 0, err.Error()
	}
	defer response.Body.Close()
	contents, err := io.ReadAll(response.Body)
	if err != nil {
		return 0, err.Error()
	}
	return response.StatusCode, strings.TrimSpace(string(contents))
}

func TestPartialSettlementsRecordExactAmountsAndRejectExcess(t *testing.T) {
	t.Parallel()
	setup := partialSettlementFixture(t)
	groupURL := setup.baseURL + "/api/v1/groups/" + setup.group.ID + "/settlements"

	// A partial payment records exactly the requested centavos.
	var partial groups.Group
	doJSON(t, setup.client, http.MethodPost, groupURL, setup.debtorToken, map[string]any{
		"member_id": setup.ownerMember.ID, "amount_cents": 30,
	}, http.StatusCreated, &partial)
	assertBalance(t, partial, setup.ownerMember.ID, 20)
	assertBalance(t, partial, setup.debtorMember.ID, -20)
	if len(partial.Settlements) != 1 || partial.Settlements[0].AmountCents != 30 {
		t.Fatalf("partial settlements = %#v, want one 30-centavo row", partial.Settlements)
	}

	// Overpayment, explicit zero, and negative amounts are all refused; the
	// non-integer body never reaches the command at all.
	var overpayment apiError
	doJSON(t, setup.client, http.MethodPost, groupURL, setup.debtorToken, map[string]any{
		"member_id": setup.ownerMember.ID, "amount_cents": 21,
	}, http.StatusUnprocessableEntity, &overpayment)
	if overpayment.Message != "amount exceeds the outstanding balance" {
		t.Fatalf("overpayment error = %#v", overpayment)
	}
	var invalid apiError
	doJSON(t, setup.client, http.MethodPost, groupURL, setup.debtorToken, map[string]any{
		"member_id": setup.ownerMember.ID, "amount_cents": 0,
	}, http.StatusUnprocessableEntity, &invalid)
	if invalid.Message != "member has no balance to settle" {
		t.Fatalf("zero-centavo error = %#v", invalid)
	}
	doJSON(t, setup.client, http.MethodPost, groupURL, setup.debtorToken, map[string]any{
		"member_id": setup.ownerMember.ID, "amount_cents": -1,
	}, http.StatusUnprocessableEntity, nil)
	doJSON(t, setup.client, http.MethodPost, groupURL, setup.debtorToken, map[string]any{
		"member_id": setup.ownerMember.ID, "amount_cents": 1.5,
	}, http.StatusBadRequest, nil)

	var settledRows int
	if err := setup.pg.db.QueryRow(`SELECT count(*) FROM settlements WHERE group_id=$1`, setup.group.ID).Scan(&settledRows); err != nil || settledRows != 1 {
		t.Fatalf("settlement rows after rejections = %d, err=%v", settledRows, err)
	}

	// The back-compatible body settles the remainder deterministically.
	var cleared groups.Group
	doJSON(t, setup.client, http.MethodPost, groupURL, setup.debtorToken, map[string]string{
		"member_id": setup.ownerMember.ID,
	}, http.StatusCreated, &cleared)
	assertBalance(t, cleared, setup.ownerMember.ID, 0)
	assertBalance(t, cleared, setup.debtorMember.ID, 0)
	if len(cleared.Settlements) != 2 {
		t.Fatalf("settlements = %#v, want two rows", cleared.Settlements)
	}
	var total int64
	if err := setup.pg.db.QueryRow(`SELECT COALESCE(sum(amount_cents),0) FROM settlements WHERE from_member_id=$1 AND to_member_id=$2`, setup.debtorMember.ID, setup.ownerMember.ID).Scan(&total); err != nil || total != 50 {
		t.Fatalf("settled total = %d, err=%v, want 50", total, err)
	}

	// With the obligation cleared, nothing remains to settle.
	doJSON(t, setup.client, http.MethodPost, groupURL, setup.debtorToken, map[string]any{
		"member_id": setup.ownerMember.ID, "amount_cents": 1,
	}, http.StatusUnprocessableEntity, nil)
	doJSON(t, setup.client, http.MethodPost, groupURL, setup.debtorToken, map[string]string{
		"member_id": setup.ownerMember.ID,
	}, http.StatusUnprocessableEntity, nil)
}

func TestConcurrentPartialSettlementsCannotOverpay(t *testing.T) {
	t.Parallel()
	setup := partialSettlementFixture(t)

	const attempts = 5
	type outcome struct {
		status int
		body   string
	}
	results := make([]outcome, attempts)
	var wg sync.WaitGroup
	for index := range attempts {
		wg.Add(1)
		go func(index int) {
			defer wg.Done()
			status, body := settle(setup, 50)
			results[index] = outcome{status, body}
		}(index)
	}
	wg.Wait()

	var created, rejected int
	for _, result := range results {
		switch result.status {
		case http.StatusCreated:
			created++
		case http.StatusUnprocessableEntity:
			rejected++
		default:
			t.Fatalf("unexpected concurrent settlement status %d: %s", result.status, result.body)
		}
	}
	if created != 1 || rejected != attempts-1 {
		t.Fatalf("concurrent settlements created=%d rejected=%d, want 1 and %d", created, rejected, attempts-1)
	}
	var total int64
	if err := setup.pg.db.QueryRow(`SELECT COALESCE(sum(amount_cents),0) FROM settlements WHERE group_id=$1`, setup.group.ID).Scan(&total); err != nil || total != 50 {
		t.Fatalf("concurrent settled total = %d, err=%v, want 50", total, err)
	}
}
