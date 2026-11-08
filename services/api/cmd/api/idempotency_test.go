package main

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"sync"
	"testing"

	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/auth"
	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/groups"
)

// tryPost sends one command outside the test goroutine so concurrent retries
// can share one intent key. Failures surface through the returned error.
func tryPost(client *http.Client, endpoint, token, key string, payload any) (int, []byte, error) {
	encoded, err := json.Marshal(payload)
	if err != nil {
		return 0, nil, err
	}
	request, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewReader(encoded))
	if err != nil {
		return 0, nil, err
	}
	request.Header.Set("Content-Type", "application/json")
	if token != "" {
		request.Header.Set("Authorization", "Bearer "+token)
	}
	if key != "" {
		request.Header.Set("Idempotency-Key", key)
	}
	response, err := client.Do(request)
	if err != nil {
		return 0, nil, err
	}
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	return response.StatusCode, body, err
}

// postCommand is the test-goroutine wrapper around tryPost.
func postCommand(t *testing.T, client *http.Client, endpoint, token, key string, payload any, wantStatus int, output any) {
	t.Helper()
	status, contents, err := tryPost(client, endpoint, token, key, payload)
	if err != nil {
		t.Fatalf("%s: %v", endpoint, err)
	}
	if status != wantStatus {
		t.Fatalf("%s status = %d, want %d; body=%s", endpoint, status, wantStatus, strings.TrimSpace(string(contents)))
	}
	if output != nil && len(bytes.TrimSpace(contents)) > 0 {
		if err := json.Unmarshal(contents, output); err != nil {
			t.Fatalf("decode %s response %q: %v", endpoint, contents, err)
		}
	}
}

func expensePayload(payer, participant string, amountCents int64) map[string]any {
	return map[string]any{
		"description":     "Cena",
		"amount_cents":    amountCents,
		"payer_id":        payer,
		"split_mode":      "equal",
		"participant_ids": []string{payer, participant},
	}
}

type idempotencyFixture struct {
	test         postgresApplication
	client       *http.Client
	baseURL      string
	group        groups.Group
	ownerMember  groups.Member
	debtorMember groups.Member
	ownerToken   string
	debtorToken  string
}

func createIdempotencyFixture(t *testing.T) idempotencyFixture {
	t.Helper()
	test := newPostgreSQLApplication(t)
	client, baseURL := test.server.Client(), test.server.URL
	owner := registerUser(t, client, baseURL, "Ana", "idem-ana@example.test", "+525522221001")
	debtor := registerUser(t, client, baseURL, "Beto", "idem-beto@example.test", "+525522221002")
	var group groups.Group
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/groups", owner.Token, map[string]any{
		"name": "Idem", "emoji": "I", "visibility": "shared",
		"members": []map[string]string{{"name": "Beto", "phone": "+525522221002"}},
	}, http.StatusCreated, &group)
	ownerMember, debtorMember := findMember(t, group, owner.User.ID), findMember(t, group, debtor.User.ID)
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/group-invitations/"+group.ID+"/response", debtor.Token, map[string]bool{"accept": true}, http.StatusNoContent, nil)
	return idempotencyFixture{test: test, client: client, baseURL: baseURL, group: group, ownerMember: ownerMember, debtorMember: debtorMember, ownerToken: owner.Token, debtorToken: debtor.Token}
}

func (f idempotencyFixture) countRows(t *testing.T, query string, args ...any) int {
	t.Helper()
	var count int
	if err := f.test.db.QueryRow(query, args...).Scan(&count); err != nil {
		t.Fatal(err)
	}
	return count
}

func (f idempotencyFixture) settlementCount(t *testing.T) int {
	t.Helper()
	return f.countRows(t, `SELECT COUNT(*) FROM settlements WHERE group_id=$1`, f.group.ID)
}

func TestCommandIdempotencyReplaysStoredOutcomes(t *testing.T) {
	t.Parallel()
	f := createIdempotencyFixture(t)
	client, groupURL := f.client, f.baseURL+"/api/v1/groups/"+f.group.ID

	// An identical expense retry replays the stored response without writing.
	var expenseIntents []groups.Group
	for range 2 {
		var group groups.Group
		postCommand(t, client, groupURL+"/expenses", f.ownerToken, "expense-intent", expensePayload(f.ownerMember.ID, f.debtorMember.ID, 600), http.StatusCreated, &group)
		expenseIntents = append(expenseIntents, group)
	}
	if expenseIntents[0].ID != expenseIntents[1].ID || len(expenseIntents[1].Expenses) != 1 || expenseIntents[1].Expenses[0].ID != expenseIntents[0].Expenses[0].ID {
		t.Fatalf("replayed expense response %#v, want the stored response %#v", expenseIntents[1], expenseIntents[0])
	}

	// Without a key the previous behavior stands: a retry is a new intent.
	doJSON(t, client, http.MethodPost, groupURL+"/expenses", f.ownerToken, expensePayload(f.ownerMember.ID, f.debtorMember.ID, 100), http.StatusCreated, nil)
	if count := f.countRows(t, `SELECT COUNT(*) FROM expenses WHERE group_id=$1`, f.group.ID); count != 2 {
		t.Fatalf("expense rows after replay and new intent = %d, want 2", count)
	}
	// State so far: owner is owed 350, debtor owes 350.
	var partial, partialReplay groups.Group
	postCommand(t, client, groupURL+"/settlements/received", f.ownerToken, "settlement-intent", map[string]any{"debtor_member_id": f.debtorMember.ID, "amount_cents": 100}, http.StatusCreated, &partial)
	assertBalance(t, partial, f.ownerMember.ID, 250)
	postCommand(t, client, groupURL+"/settlements/received", f.ownerToken, "settlement-intent", map[string]any{"debtor_member_id": f.debtorMember.ID, "amount_cents": 100}, http.StatusCreated, &partialReplay)
	assertBalance(t, partialReplay, f.ownerMember.ID, 250)
	assertBalance(t, partialReplay, f.debtorMember.ID, -250)
	if len(partialReplay.Settlements) != 1 || partialReplay.Settlements[0].ID != partial.Settlements[0].ID {
		t.Fatalf("replayed settlement %#v, want %#v", partialReplay.Settlements, partial.Settlements)
	}
	if count := f.settlementCount(t); count != 1 {
		t.Fatalf("settlement rows after replay = %d, want 1", count)
	}

	// Settle the remainder; the stored outcome reconstructs even after the
	// ledger changed underneath it.
	var full, fullReplay, freshFull groups.Group
	postCommand(t, client, groupURL+"/settlements/received", f.ownerToken, "settlement-full-intent", map[string]any{"debtor_member_id": f.debtorMember.ID}, http.StatusCreated, &full)
	assertBalance(t, full, f.ownerMember.ID, 0)
	doJSON(t, client, http.MethodPost, groupURL+"/expenses", f.ownerToken, expensePayload(f.ownerMember.ID, f.debtorMember.ID, 400), http.StatusCreated, nil)
	if count := f.settlementCount(t); count != 2 {
		t.Fatalf("settlement rows before replay = %d, want 2", count)
	}
	postCommand(t, client, groupURL+"/settlements/received", f.ownerToken, "settlement-full-intent", map[string]any{"debtor_member_id": f.debtorMember.ID}, http.StatusCreated, &fullReplay)
	assertBalance(t, fullReplay, f.ownerMember.ID, 0)
	assertBalance(t, fullReplay, f.debtorMember.ID, 0)
	if len(fullReplay.Settlements) != len(full.Settlements) {
		t.Fatalf("replayed settlement history has %d rows, want the stored %d", len(fullReplay.Settlements), len(full.Settlements))
	}
	if count := f.settlementCount(t); count != 2 {
		t.Fatalf("replay wrote settlement rows; rows = %d, want 2", count)
	}
	// A fresh request without a key revalidates against the current ledger.
	doJSON(t, client, http.MethodPost, groupURL+"/settlements/received", f.ownerToken, map[string]any{"debtor_member_id": f.debtorMember.ID}, http.StatusCreated, &freshFull)
	assertBalance(t, freshFull, f.ownerMember.ID, 0)
	assertBalance(t, freshFull, f.debtorMember.ID, 0)
	if count := f.settlementCount(t); count != 3 {
		t.Fatalf("settlement rows after fresh intent = %d, want 3", count)
	}

	// Declining an invitation replays success instead of turning into 404.
	diana := registerUser(t, client, f.baseURL, "Diana", "idem-diana@example.test", "+525522221004")
	var declineGroup groups.Group
	doJSON(t, client, http.MethodPost, f.baseURL+"/api/v1/groups", f.ownerToken, map[string]any{
		"name": "Decline", "emoji": "D", "visibility": "shared",
		"members": []map[string]string{{"name": "Diana", "phone": "+525522221004"}},
	}, http.StatusCreated, &declineGroup)
	declineURL := f.baseURL + "/api/v1/group-invitations/" + declineGroup.ID + "/response"
	var declineCount int
	if err := f.test.db.QueryRow(`SELECT COUNT(*) FROM group_members WHERE group_id=$1 AND user_id=$2 AND declined_at IS NULL AND removed_at IS NULL`, declineGroup.ID, diana.User.ID).Scan(&declineCount); err != nil {
		t.Fatal(err)
	}
	if declineCount != 1 {
		t.Fatalf("pending invitation rows = %d, want 1", declineCount)
	}
	postCommand(t, client, declineURL, diana.Token, "decline-intent", map[string]bool{"accept": false}, http.StatusNoContent, nil)
	postCommand(t, client, declineURL, diana.Token, "decline-intent", map[string]bool{"accept": false}, http.StatusNoContent, nil)
	doJSON(t, client, http.MethodPost, declineURL, diana.Token, map[string]bool{"accept": false}, http.StatusNotFound, nil)
	if declined := f.countRows(t, `SELECT COUNT(*) FROM group_members WHERE group_id=$1 AND user_id=$2 AND declined_at IS NOT NULL AND removed_at IS NULL`, declineGroup.ID, diana.User.ID); declined != 1 {
		t.Fatalf("declined membership rows = %d, want 1", declined)
	}

	// Contacts save with the same key and payload replays the saved list.
	contactsURL := f.baseURL + "/api/v1/contacts"
	requestContacts := map[string]any{"contacts": []map[string]string{
		{"name": "Beto", "phone": "+525522221002"},
		{"name": "Carlota", "phone": "+525522221003"},
	}}
	type contactsResponse struct {
		Contacts []auth.Contact `json:"contacts"`
	}
	var firstContacts, replayContacts, lastContacts contactsResponse
	postCommand(t, client, contactsURL, f.ownerToken, "contacts-intent", requestContacts, http.StatusOK, &firstContacts)
	postCommand(t, client, contactsURL, f.ownerToken, "contacts-intent", requestContacts, http.StatusOK, &replayContacts)
	doJSON(t, client, http.MethodPost, contactsURL, f.ownerToken, requestContacts, http.StatusOK, &lastContacts)
	if len(firstContacts.Contacts) != 2 || len(replayContacts.Contacts) != 2 || len(lastContacts.Contacts) != 2 {
		t.Fatalf("contact lists %#v %#v %#v, want two contacts each", firstContacts.Contacts, replayContacts.Contacts, lastContacts.Contacts)
	}
	if contacts := f.countRows(t, `SELECT COUNT(*) FROM contacts WHERE owner_id=$1`, f.ownerMember.UserID); contacts != 2 {
		t.Fatalf("contact rows = %d, want 2", contacts)
	}

	// Group creation and member addition replay their stored responses too.
	var ownGroup, ownGroupReplay groups.Group
	ownGroupPayload := map[string]any{"name": "Propio", "emoji": "P", "member_names": []string{"Solo"}}
	postCommand(t, client, f.baseURL+"/api/v1/groups", f.debtorToken, "group-intent", ownGroupPayload, http.StatusCreated, &ownGroup)
	postCommand(t, client, f.baseURL+"/api/v1/groups", f.debtorToken, "group-intent", ownGroupPayload, http.StatusCreated, &ownGroupReplay)
	if ownGroup.ID != ownGroupReplay.ID || len(ownGroup.Members) != 2 {
		t.Fatalf("group creation replay %#v, want %#v", ownGroupReplay, ownGroup)
	}
	var addMemberPlans []groups.Group
	addMemberPayload := map[string]any{"name": "Diana", "phone": "+525522221004"}
	for range 2 {
		var group groups.Group
		postCommand(t, client, groupURL+"/members", f.ownerToken, "member-intent", addMemberPayload, http.StatusCreated, &group)
		addMemberPlans = append(addMemberPlans, group)
	}
	if len(addMemberPlans[0].Members) != 3 || len(addMemberPlans[1].Members) != 3 {
		t.Fatalf("member addition replay member counts %d and %d, want 3", len(addMemberPlans[0].Members), len(addMemberPlans[1].Members))
	}
	if active := f.countRows(t, `SELECT COUNT(*) FROM group_members WHERE group_id=$1 AND removed_at IS NULL`, f.group.ID); active != 3 {
		t.Fatalf("stored group memberships = %d, want 3", active)
	}
}

func TestCommandIdempotencyConflictsAndScoping(t *testing.T) {
	t.Parallel()
	f := createIdempotencyFixture(t)
	client, groupURL := f.client, f.baseURL+"/api/v1/groups/"+f.group.ID
	payload := expensePayload(f.ownerMember.ID, f.debtorMember.ID, 600)

	var first groups.Group
	postCommand(t, client, groupURL+"/expenses", f.ownerToken, "family-intent", payload, http.StatusCreated, &first)

	// Same user, operation, and scope, different payload: conflict, no row.
	var conflictError apiError
	doJSONHeaders(t, client, http.MethodPost, groupURL+"/expenses", f.ownerToken, expensePayload(f.ownerMember.ID, f.debtorMember.ID, 900), map[string]string{"Idempotency-Key": "family-intent"}, http.StatusConflict, &conflictError)
	if conflictError.Code != "idempotency_key_conflict" {
		t.Fatalf("conflict error = %#v", conflictError)
	}
	if count := f.countRows(t, `SELECT COUNT(*) FROM expenses WHERE group_id=$1`, f.group.ID); count != 1 {
		t.Fatalf("expense rows after conflict = %d, want 1", count)
	}

	// The same key and payload under another group is a different scope.
	var personal groups.Group
	doJSON(t, client, http.MethodPost, f.baseURL+"/api/v1/groups", f.ownerToken, map[string]any{"name": "Personal", "emoji": "P"}, http.StatusCreated, &personal)
	postCommand(t, client, f.baseURL+"/api/v1/groups/"+personal.ID+"/expenses", f.ownerToken, "family-intent", map[string]any{
		"description": "Solo", "amount_cents": int64(600), "payer_id": f.ownerMember.ID,
		"split_mode": "equal", "participant_ids": []string{f.ownerMember.ID},
	}, http.StatusCreated, nil)
	if count := f.countRows(t, `SELECT COUNT(*) FROM expenses WHERE group_id=$1`, personal.ID); count != 1 {
		t.Fatalf("second-scope expense rows = %d, want 1", count)
	}

	// The same key under another user is also independent.
	var debtorExpense groups.Group
	postCommand(t, client, groupURL+"/expenses", f.debtorToken, "family-intent", map[string]any{
		"description": "Solo", "amount_cents": int64(600), "payer_id": f.debtorMember.ID,
		"split_mode": "equal", "participant_ids": []string{f.debtorMember.ID},
	}, http.StatusCreated, &debtorExpense)
	if len(debtorExpense.Expenses) != 2 {
		t.Fatalf("group expenses after independent user intent = %d, want 2", len(debtorExpense.Expenses))
	}

	// An overlong key is rejected up front.
	overlong := strings.Repeat("x", 129)
	var invalidError apiError
	doJSONHeaders(t, client, http.MethodPost, groupURL+"/expenses", f.ownerToken, expensePayload(f.ownerMember.ID, f.debtorMember.ID, 700), map[string]string{"Idempotency-Key": overlong}, http.StatusBadRequest, &invalidError)
	if invalidError.Code != "idempotency_key_invalid" {
		t.Fatalf("invalid key error = %#v", invalidError)
	}

	// A rejected attempt stores nothing: the same key claims a valid intent.
	var overpaymentError apiError
	doJSONHeaders(t, client, http.MethodPost, groupURL+"/settlements/received", f.ownerToken, map[string]any{"debtor_member_id": f.debtorMember.ID, "amount_cents": 5000}, map[string]string{"Idempotency-Key": "failed-first"}, http.StatusUnprocessableEntity, &overpaymentError)
	if overpaymentError.Code != "validation_failed" {
		t.Fatalf("overpayment error = %#v", overpaymentError)
	}
	var validSettlement groups.Group
	postCommand(t, client, groupURL+"/settlements/received", f.ownerToken, "failed-first", map[string]any{"debtor_member_id": f.debtorMember.ID, "amount_cents": 100}, http.StatusCreated, &validSettlement)
	if count := f.countRows(t, `SELECT COUNT(*) FROM settlements WHERE group_id=$1`, f.group.ID); count != 1 {
		t.Fatalf("settlement rows after failed first attempt = %d, want 1", count)
	}
}

func TestCommandIdempotencyConcurrentRetryCreatesOneRow(t *testing.T) {
	t.Parallel()
	f := createIdempotencyFixture(t)
	groupURL := f.baseURL + "/api/v1/groups/" + f.group.ID + "/expenses"
	payload := expensePayload(f.ownerMember.ID, f.debtorMember.ID, 600)

	const attempts = 6
	type postResult struct {
		status int
		body   []byte
		err    error
	}
	posts := make([]postResult, attempts)
	var wg sync.WaitGroup
	for i := range posts {
		wg.Add(1)
		go func(index int) {
			defer wg.Done()
			status, body, err := tryPost(f.client, groupURL, f.ownerToken, "concurrent-intent", payload)
			posts[index] = postResult{status: status, body: body, err: err}
		}(i)
	}
	wg.Wait()

	expenseIDs := map[string]bool{}
	for _, post := range posts {
		if post.err != nil {
			t.Fatalf("concurrent retry failed: %v", post.err)
		}
		if post.status != http.StatusCreated {
			t.Fatalf("concurrent retry status = %d, want 201; body=%s", post.status, strings.TrimSpace(string(post.body)))
		}
		var group groups.Group
		if err := json.Unmarshal(post.body, &group); err != nil {
			t.Fatalf("decode concurrent retry response: %v", err)
		}
		if len(group.Expenses) != 1 {
			t.Fatalf("concurrent retry expense count = %d, want 1", len(group.Expenses))
		}
		expenseIDs[group.Expenses[0].ID] = true
		assertBalance(t, group, f.ownerMember.ID, 300)
		assertBalance(t, group, f.debtorMember.ID, -300)
	}
	if len(expenseIDs) != 1 {
		t.Fatalf("concurrent retries produced %d distinct expenses, want 1", len(expenseIDs))
	}
	if count := f.countRows(t, `SELECT COUNT(*) FROM expenses WHERE group_id=$1`, f.group.ID); count != 1 {
		t.Fatalf("expense rows after concurrent retries = %d, want 1", count)
	}
}
