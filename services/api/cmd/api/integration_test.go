package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/auth"
	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/database"
	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/groups"
	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/payments"
)

var apiSchemaSequence atomic.Uint64

func TestAPIWorkflowWithPostgreSQL(t *testing.T) {
	t.Parallel()
	test := newPostgreSQLApplication(t)
	client := test.server.Client()

	var authenticationError apiError
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups", "", map[string]any{
		"name":         "Sin sesion",
		"member_names": []string{"Invitado"},
	}, http.StatusUnauthorized, &authenticationError)
	if authenticationError.Code != "authentication_required" {
		t.Fatalf("authentication error = %#v", authenticationError)
	}

	owner := registerUser(t, client, test.server.URL, "Ana", "ana@example.test", "+525511112222")
	var conflictError apiError
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/auth/register", "", map[string]any{
		"name": "Ana", "email": "ana@example.test", "phone": "+525511112222", "password": "password1", "salary_cents": 100,
	}, http.StatusConflict, &conflictError)
	if conflictError.Code != "email_already_registered" || conflictError.Fields["email"] != "already_registered" {
		t.Fatalf("conflict error = %#v", conflictError)
	}
	var validationError apiError
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/auth/register", "", map[string]any{
		"name": "", "email": "not-an-email", "phone": "invalid", "password": "short", "salary_cents": -1,
	}, http.StatusUnprocessableEntity, &validationError)
	if validationError.Code != "validation_failed" {
		t.Fatalf("validation error = %#v", validationError)
	}
	member := registerUser(t, client, test.server.URL, "Beto", "beto@example.test", "+525522223333")
	ownerLogin := loginUser(t, client, test.server.URL, "ana@example.test")
	memberLogin := loginUser(t, client, test.server.URL, "beto@example.test")
	if ownerLogin.User.ID != owner.User.ID || memberLogin.User.ID != member.User.ID {
		t.Fatalf("login returned different users: owner=%q member=%q", ownerLogin.User.ID, memberLogin.User.ID)
	}
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups", ownerLogin.Token, map[string]any{
		"name":       "Without icon",
		"visibility": "personal",
	}, http.StatusUnprocessableEntity, nil)

	var group groups.Group
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups", ownerLogin.Token, map[string]any{
		"name":       "Viaje",
		"emoji":      "✈️",
		"visibility": "shared",
		"members": []map[string]string{{
			"name":  "Beto",
			"phone": "+525522223333",
		}},
	}, http.StatusCreated, &group)
	if len(group.Members) != 2 {
		t.Fatalf("created group members = %d, want 2", len(group.Members))
	}
	ownerMember := findMember(t, group, owner.User.ID)
	invitedMember := findMember(t, group, member.User.ID)
	if ownerMember.Role != groups.RoleOwner || invitedMember.Role != groups.RoleMember {
		t.Fatalf("unexpected persisted roles: owner=%q member=%q", ownerMember.Role, invitedMember.Role)
	}

	// A pending invitee cannot read the group through a protected mutation.
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+group.ID+"/expenses", memberLogin.Token, map[string]any{
		"description":     "No autorizado",
		"amount_cents":    100,
		"payer_id":        invitedMember.ID,
		"participant_ids": []string{invitedMember.ID},
	}, http.StatusNotFound, nil)

	var invitationList struct {
		Invitations []groups.Invitation `json:"invitations"`
	}
	doJSON(t, client, http.MethodGet, test.server.URL+"/api/v1/group-invitations", memberLogin.Token, nil, http.StatusOK, &invitationList)
	if len(invitationList.Invitations) != 1 || invitationList.Invitations[0].Group.ID != group.ID {
		t.Fatalf("unexpected invitations: %#v", invitationList.Invitations)
	}
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/group-invitations/"+group.ID+"/response", memberLogin.Token, map[string]bool{"accept": true}, http.StatusNoContent, nil)

	// An accepted member can see the shared group but cannot change owner-only settings.
	doJSON(t, client, http.MethodPatch, test.server.URL+"/api/v1/groups/"+group.ID, memberLogin.Token, map[string]string{"name": "Cambio no autorizado"}, http.StatusNotFound, nil)

	var withExpense groups.Group
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+group.ID+"/expenses", ownerLogin.Token, map[string]any{
		"description":  "Cena",
		"amount_cents": 1001,
		"payer_id":     ownerMember.ID,
		"payers": []map[string]any{
			{"member_id": ownerMember.ID, "amount_cents": 700},
			{"member_id": invitedMember.ID, "amount_cents": 301},
		},
		"participant_ids": []string{ownerMember.ID, invitedMember.ID},
		"split_mode":      "equal",
	}, http.StatusCreated, &withExpense)
	assertBalance(t, withExpense, ownerMember.ID, 199)
	assertBalance(t, withExpense, invitedMember.ID, -199)
	if len(withExpense.Expenses) != 1 || withExpense.Expenses[0].AmountCents != 1001 {
		t.Fatalf("unexpected persisted expense response: %#v", withExpense.Expenses)
	}
	if got := withExpense.Expenses[0].Shares[ownerMember.ID]; got != 501 {
		t.Fatalf("owner share = %d, want 501", got)
	}
	if got := withExpense.Expenses[0].Shares[invitedMember.ID]; got != 500 {
		t.Fatalf("member share = %d, want 500", got)
	}

	var expenseAmount int64
	var participantCount, payerCount int
	if err := test.db.QueryRow(`SELECT amount_cents FROM expenses WHERE id=$1`, withExpense.Expenses[0].ID).Scan(&expenseAmount); err != nil {
		t.Fatalf("read persisted expense: %v", err)
	}
	if err := test.db.QueryRow(`SELECT count(*) FROM expense_participants WHERE expense_id=$1`, withExpense.Expenses[0].ID).Scan(&participantCount); err != nil {
		t.Fatalf("read persisted participants: %v", err)
	}
	if err := test.db.QueryRow(`SELECT count(*) FROM expense_payers WHERE expense_id=$1`, withExpense.Expenses[0].ID).Scan(&payerCount); err != nil {
		t.Fatalf("read persisted payers: %v", err)
	}
	if payerCount != 2 {
		t.Fatalf("persisted payer count = %d, want 2", payerCount)
	}
	if expenseAmount != 1001 || participantCount != 2 {
		t.Fatalf("persisted expense amount=%d participants=%d", expenseAmount, participantCount)
	}

	var settled groups.Group
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+group.ID+"/settlements", memberLogin.Token, map[string]string{
		"member_id": ownerMember.ID,
	}, http.StatusCreated, &settled)
	assertBalance(t, settled, ownerMember.ID, 0)
	assertBalance(t, settled, invitedMember.ID, 0)
	if len(settled.Settlements) != 1 || settled.Settlements[0].AmountCents != 199 {
		t.Fatalf("unexpected settlement response: %#v", settled.Settlements)
	}

	var settlementAmount int64
	var fromMember, toMember string
	if err := test.db.QueryRow(`SELECT amount_cents,from_member_id,to_member_id FROM settlements WHERE group_id=$1`, group.ID).Scan(&settlementAmount, &fromMember, &toMember); err != nil {
		t.Fatalf("read persisted settlement: %v", err)
	}
	if settlementAmount != 199 || fromMember != invitedMember.ID || toMember != ownerMember.ID {
		t.Fatalf("persisted settlement amount=%d from=%q to=%q", settlementAmount, fromMember, toMember)
	}

	var ownerGroups struct {
		Groups []groups.Group `json:"groups"`
	}
	doJSON(t, client, http.MethodGet, test.server.URL+"/api/v1/groups", ownerLogin.Token, nil, http.StatusOK, &ownerGroups)
	if len(ownerGroups.Groups) != 1 || ownerGroups.Groups[0].Name != "Viaje" {
		t.Fatalf("unexpected groups after settlement: %#v", ownerGroups.Groups)
	}
	assertBalance(t, ownerGroups.Groups[0], ownerMember.ID, 0)
	assertBalance(t, ownerGroups.Groups[0], invitedMember.ID, 0)
}

func TestSimulatedPaymentRequestsAreDurableAndIdempotent(t *testing.T) {
	t.Parallel()
	test := newPostgreSQLApplication(t)
	client, baseURL := test.server.Client(), test.server.URL
	creditor := registerUser(t, client, baseURL, "Ana", "payment-ana@example.test", "+525588880001")
	debtor := registerUser(t, client, baseURL, "Beto", "payment-beto@example.test", "+525588880002")
	var group groups.Group
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/groups", creditor.Token, map[string]any{
		"name": "Pago durable", "emoji": "P", "visibility": "shared",
		"members": []map[string]string{{"name": "Beto", "phone": "+525588880002"}},
	}, http.StatusCreated, &group)
	creditorMember, debtorMember := findMember(t, group, creditor.User.ID), findMember(t, group, debtor.User.ID)
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/group-invitations/"+group.ID+"/response", debtor.Token, map[string]bool{"accept": true}, http.StatusNoContent, nil)
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/groups/"+group.ID+"/expenses", creditor.Token, map[string]any{
		"description": "Cena", "amount_cents": 100, "payer_id": creditorMember.ID,
		"participant_ids": []string{creditorMember.ID, debtorMember.ID}, "split_mode": "equal",
	}, http.StatusCreated, nil)
	payload := map[string]any{"group_id": group.ID, "debtor_id": debtorMember.ID, "amount_cents": 50, "currency": "MXN", "description": "simulated only"}
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/payment-requests", creditor.Token, payload, http.StatusBadRequest, nil)
	var request payments.StoredRequest
	doJSONHeaders(t, client, http.MethodPost, baseURL+"/api/v1/payment-requests", creditor.Token, payload, map[string]string{"Idempotency-Key": "payment-request-1"}, http.StatusCreated, &request)
	if request.Status != payments.StatusPending || request.ID == "" || request.PaymentURL == "" {
		t.Fatalf("created payment request = %#v", request)
	}
	var retried payments.StoredRequest
	doJSONHeaders(t, client, http.MethodPost, baseURL+"/api/v1/payment-requests", creditor.Token, payload, map[string]string{"Idempotency-Key": "payment-request-1"}, http.StatusOK, &retried)
	if retried.ID != request.ID {
		t.Fatalf("retry request id = %q, want %q", retried.ID, request.ID)
	}
	conflict := map[string]any{"group_id": group.ID, "debtor_id": debtorMember.ID, "amount_cents": 49, "currency": "MXN"}
	var conflictError apiError
	doJSONHeaders(t, client, http.MethodPost, baseURL+"/api/v1/payment-requests", creditor.Token, conflict, map[string]string{"Idempotency-Key": "payment-request-1"}, http.StatusConflict, &conflictError)
	if conflictError.Code != "idempotency_key_conflict" {
		t.Fatalf("idempotency conflict = %#v", conflictError)
	}
	var persistedRequests int
	if err := test.db.QueryRow(`SELECT count(*) FROM payment_requests`).Scan(&persistedRequests); err != nil || persistedRequests != 1 {
		t.Fatalf("payment request count = %d, err=%v", persistedRequests, err)
	}

	complete := func() int {
		body, err := json.Marshal(map[string]string{"provider_event_id": "demo-event-1"})
		if err != nil {
			t.Fatal(err)
		}
		req, err := http.NewRequest(http.MethodPost, baseURL+"/api/v1/payment-requests/"+request.ID+"/simulate", bytes.NewReader(body))
		if err != nil {
			t.Fatal(err)
		}
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Bearer "+debtor.Token)
		response, err := client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()
		return response.StatusCode
	}
	statuses := make(chan int, 2)
	var calls sync.WaitGroup
	for range 2 {
		calls.Add(1)
		go func() { defer calls.Done(); statuses <- complete() }()
	}
	calls.Wait()
	close(statuses)
	gotStatuses := map[int]int{}
	for status := range statuses {
		gotStatuses[status]++
	}
	if gotStatuses[http.StatusCreated] != 1 || gotStatuses[http.StatusOK] != 1 {
		t.Fatalf("concurrent callback statuses = %#v", gotStatuses)
	}
	var settlementCount, eventCount int
	if err := test.db.QueryRow(`SELECT count(*) FROM settlements WHERE group_id=$1`, group.ID).Scan(&settlementCount); err != nil {
		t.Fatal(err)
	}
	if err := test.db.QueryRow(`SELECT count(*) FROM payment_provider_events WHERE payment_request_id=$1`, request.ID).Scan(&eventCount); err != nil {
		t.Fatal(err)
	}
	if settlementCount != 1 || eventCount != 1 {
		t.Fatalf("settlements=%d events=%d, want one each", settlementCount, eventCount)
	}
}

func TestGroupAuthorizationMatrixWithPostgreSQL(t *testing.T) {
	t.Parallel()
	test := newPostgreSQLApplication(t)
	client := test.server.Client()
	baseURL := test.server.URL

	owner := registerUser(t, client, baseURL, "Owner", "owner@example.test", "+525510000001")
	member := registerUser(t, client, baseURL, "Member", "member@example.test", "+525510000002")
	pending := registerUser(t, client, baseURL, "Pending", "pending@example.test", "+525510000003")
	removed := registerUser(t, client, baseURL, "Removed", "removed@example.test", "+525510000004")
	declined := registerUser(t, client, baseURL, "Declined", "declined@example.test", "+525510000005")
	candidate := registerUser(t, client, baseURL, "Candidate", "candidate@example.test", "+525510000006")

	var group groups.Group
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/groups", owner.Token, map[string]any{
		"name":       "Authorization matrix",
		"emoji":      "🔐",
		"visibility": "shared",
		"members": []map[string]string{
			{"name": "Member", "phone": "+525510000002"},
			{"name": "Pending", "phone": "+525510000003"},
			{"name": "Removed", "phone": "+525510000004"},
			{"name": "Declined", "phone": "+525510000005"},
		},
	}, http.StatusCreated, &group)

	ownerMember := findMember(t, group, owner.User.ID)
	acceptedMember := findMember(t, group, member.User.ID)
	pendingMember := findMember(t, group, pending.User.ID)
	removedMember := findMember(t, group, removed.User.ID)
	declinedMember := findMember(t, group, declined.User.ID)
	for _, membership := range group.Members {
		want := groups.RoleMember
		if membership.ID == ownerMember.ID {
			want = groups.RoleOwner
		}
		if membership.Role != want {
			t.Fatalf("member %q role = %q, want %q", membership.ID, membership.Role, want)
		}
	}

	acceptInvitation := func(session auth.Session) {
		t.Helper()
		doJSON(t, client, http.MethodPost, baseURL+"/api/v1/group-invitations/"+group.ID+"/response", session.Token, map[string]bool{"accept": true}, http.StatusNoContent, nil)
	}
	acceptInvitation(member)
	acceptInvitation(removed)
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/group-invitations/"+group.ID+"/response", declined.Token, map[string]bool{"accept": false}, http.StatusNoContent, nil)
	doJSON(t, client, http.MethodDelete, baseURL+"/api/v1/groups/"+group.ID+"/members/"+removedMember.ID, owner.Token, nil, http.StatusNoContent, nil)

	// Owner-only settings return the same response for a known-but-hidden group
	// and an unknown group, preventing resource enumeration.
	doJSON(t, client, http.MethodPatch, baseURL+"/api/v1/groups/"+group.ID, owner.Token, map[string]string{"name": "Owner updated"}, http.StatusOK, &group)
	var hiddenError, missingError apiError
	doJSON(t, client, http.MethodPatch, baseURL+"/api/v1/groups/"+group.ID, member.Token, map[string]string{"name": "Forbidden"}, http.StatusNotFound, &hiddenError)
	doJSON(t, client, http.MethodPatch, baseURL+"/api/v1/groups/group_missing", member.Token, map[string]string{"name": "Forbidden"}, http.StatusNotFound, &missingError)
	if hiddenError.Code != "resource_not_found" || hiddenError.Code != missingError.Code || hiddenError.Message != missingError.Message {
		t.Fatalf("authorization response enumerates groups: hidden=%#v missing=%#v", hiddenError, missingError)
	}
	for name, session := range map[string]auth.Session{"pending": pending, "removed": removed, "declined": declined} {
		t.Run("settings_denied_"+name, func(t *testing.T) {
			doJSON(t, client, http.MethodPatch, baseURL+"/api/v1/groups/"+group.ID, session.Token, map[string]string{"name": "Forbidden"}, http.StatusNotFound, nil)
		})
	}

	// Membership identity is owner-managed; salary consent belongs only to the
	// affected authenticated user.
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/groups/"+group.ID+"/members", owner.Token, map[string]string{"name": "Candidate", "phone": "+525510000006"}, http.StatusCreated, &group)
	candidateMember := findMember(t, group, candidate.User.ID)
	doJSON(t, client, http.MethodPatch, baseURL+"/api/v1/groups/"+group.ID+"/members/"+candidateMember.ID, owner.Token, map[string]string{"name": "Candidate edited"}, http.StatusOK, nil)
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/groups/"+group.ID+"/members", member.Token, map[string]string{"name": "Forbidden", "phone": "+525510000006"}, http.StatusNotFound, nil)
	doJSON(t, client, http.MethodPatch, baseURL+"/api/v1/groups/"+group.ID+"/members/"+acceptedMember.ID, member.Token, map[string]string{"name": "Forbidden"}, http.StatusNotFound, nil)
	doJSON(t, client, http.MethodDelete, baseURL+"/api/v1/groups/"+group.ID+"/members/"+candidateMember.ID, member.Token, nil, http.StatusNotFound, nil)
	doJSON(t, client, http.MethodPatch, baseURL+"/api/v1/groups/"+group.ID+"/members/"+acceptedMember.ID, owner.Token, map[string]bool{"salary_sharing": true}, http.StatusNotFound, nil)
	doJSON(t, client, http.MethodPatch, baseURL+"/api/v1/groups/"+group.ID+"/members/"+ownerMember.ID, owner.Token, map[string]bool{"salary_sharing": true}, http.StatusOK, nil)
	doJSON(t, client, http.MethodPatch, baseURL+"/api/v1/groups/"+group.ID+"/members/"+acceptedMember.ID, member.Token, map[string]bool{"salary_sharing": true}, http.StatusOK, nil)
	for name, denied := range map[string]struct {
		session auth.Session
		member  groups.Member
	}{
		"pending":  {pending, pendingMember},
		"removed":  {removed, removedMember},
		"declined": {declined, declinedMember},
	} {
		t.Run("membership_denied_"+name, func(t *testing.T) {
			doJSON(t, client, http.MethodPost, baseURL+"/api/v1/groups/"+group.ID+"/members", denied.session.Token, map[string]string{"name": "Forbidden", "phone": "+525510000006"}, http.StatusNotFound, nil)
			doJSON(t, client, http.MethodPatch, baseURL+"/api/v1/groups/"+group.ID+"/members/"+denied.member.ID, denied.session.Token, map[string]bool{"salary_sharing": true}, http.StatusNotFound, nil)
			doJSON(t, client, http.MethodDelete, baseURL+"/api/v1/groups/"+group.ID+"/members/"+candidateMember.ID, denied.session.Token, nil, http.StatusNotFound, nil)
		})
	}
	doJSON(t, client, http.MethodDelete, baseURL+"/api/v1/groups/"+group.ID+"/members/"+ownerMember.ID, owner.Token, nil, http.StatusUnprocessableEntity, nil)
	doJSON(t, client, http.MethodDelete, baseURL+"/api/v1/groups/"+group.ID+"/members/"+candidateMember.ID, owner.Token, nil, http.StatusNoContent, nil)

	createExpense := func(session auth.Session, payerID, description string, wantStatus int) groups.Group {
		t.Helper()
		var result groups.Group
		doJSON(t, client, http.MethodPost, baseURL+"/api/v1/groups/"+group.ID+"/expenses", session.Token, map[string]any{
			"description":     description,
			"amount_cents":    100,
			"payer_id":        payerID,
			"participant_ids": []string{ownerMember.ID, acceptedMember.ID},
			"split_mode":      "equal",
		}, wantStatus, &result)
		return result
	}
	ownerExpenseGroup := createExpense(owner, ownerMember.ID, "Owner expense", http.StatusCreated)
	if len(ownerExpenseGroup.Expenses) != 1 {
		t.Fatalf("owner expense was not created: %#v", ownerExpenseGroup)
	}
	paymentRequest := map[string]any{
		"group_id":     group.ID,
		"debtor_id":    acceptedMember.ID,
		"amount_cents": int64(50),
		"currency":     "MXN",
	}
	doJSONHeaders(t, client, http.MethodPost, baseURL+"/api/v1/payment-requests", owner.Token, paymentRequest, map[string]string{"Idempotency-Key": "owner-payment-request"}, http.StatusCreated, nil)
	doJSONHeaders(t, client, http.MethodPost, baseURL+"/api/v1/payment-requests", member.Token, paymentRequest, map[string]string{"Idempotency-Key": "member-payment-request"}, http.StatusUnprocessableEntity, nil)
	createExpense(member, acceptedMember.ID, "Member expense", http.StatusCreated)
	for name, denied := range map[string]struct {
		session auth.Session
		payerID string
	}{
		"pending":  {pending, pendingMember.ID},
		"removed":  {removed, removedMember.ID},
		"declined": {declined, declinedMember.ID},
	} {
		t.Run("expense_denied_"+name, func(t *testing.T) {
			createExpense(denied.session, denied.payerID, "Forbidden", http.StatusNotFound)
		})
	}

	for name, session := range map[string]auth.Session{"pending": pending, "removed": removed, "declined": declined} {
		t.Run("payment_request_denied_"+name, func(t *testing.T) {
			doJSONHeaders(t, client, http.MethodPost, baseURL+"/api/v1/payment-requests", session.Token, paymentRequest, map[string]string{"Idempotency-Key": "denied-" + name}, http.StatusNotFound, nil)
		})
	}

	// The two equal expenses cancel each other, so add one owner-paid expense
	// before exercising member settlement and one member-paid expense before
	// exercising owner settlement.
	createExpense(owner, ownerMember.ID, "Member settles", http.StatusCreated)
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/groups/"+group.ID+"/settlements", member.Token, map[string]string{"member_id": ownerMember.ID}, http.StatusCreated, nil)
	createExpense(member, acceptedMember.ID, "Owner settles", http.StatusCreated)
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/groups/"+group.ID+"/settlements", owner.Token, map[string]string{"member_id": acceptedMember.ID}, http.StatusCreated, nil)
	for name, session := range map[string]auth.Session{"pending": pending, "removed": removed, "declined": declined} {
		t.Run("settlement_denied_"+name, func(t *testing.T) {
			doJSON(t, client, http.MethodPost, baseURL+"/api/v1/groups/"+group.ID+"/settlements", session.Token, map[string]string{"member_id": ownerMember.ID}, http.StatusNotFound, nil)
		})
	}

	// Only the still-pending invitee can respond. Accepted, removed, and
	// declined users all receive the same not-found response.
	for name, session := range map[string]auth.Session{"owner": owner, "member": member, "removed": removed, "declined": declined} {
		t.Run("invitation_response_denied_"+name, func(t *testing.T) {
			doJSON(t, client, http.MethodPost, baseURL+"/api/v1/group-invitations/"+group.ID+"/response", session.Token, map[string]bool{"accept": true}, http.StatusNotFound, nil)
		})
	}
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/group-invitations/"+group.ID+"/response", pending.Token, map[string]bool{"accept": false}, http.StatusNoContent, nil)

	for name, session := range map[string]auth.Session{"pending": pending, "removed": removed, "declined": declined} {
		t.Run("hidden_from_group_list_"+name, func(t *testing.T) {
			var list struct {
				Groups []groups.Group `json:"groups"`
			}
			doJSON(t, client, http.MethodGet, baseURL+"/api/v1/groups", session.Token, nil, http.StatusOK, &list)
			if len(list.Groups) != 0 {
				t.Fatalf("%s user can still list hidden group: %#v", name, list.Groups)
			}
		})
	}
}

func TestSessionLifecycleWithPostgreSQL(t *testing.T) {
	t.Parallel()
	test := newPostgreSQLApplication(t)
	client := test.server.Client()
	baseURL := test.server.URL

	initial := registerUser(t, client, baseURL, "Session User", "sessions@example.test", "+525510000099")
	if initial.RefreshToken == "" || initial.AccessExpiresAt.IsZero() || initial.RefreshExpiresAt.IsZero() {
		t.Fatalf("registration returned incomplete rotating session: %#v", initial)
	}
	var rawTokenRows int
	if err := test.db.QueryRow(`SELECT
      (SELECT count(*) FROM sessions WHERE token_hash=$1) +
      (SELECT count(*) FROM refresh_tokens WHERE token_hash=$2)`, initial.Token, initial.RefreshToken).Scan(&rawTokenRows); err != nil {
		t.Fatalf("inspect stored token hashes: %v", err)
	}
	if rawTokenRows != 0 {
		t.Fatal("a raw access or refresh token was persisted")
	}
	if lifetime := initial.AccessExpiresAt.Sub(time.Now()); lifetime <= 0 || lifetime > auth.AccessTokenLifetime+time.Minute {
		t.Fatalf("access token lifetime = %v", lifetime)
	}
	if lifetime := initial.RefreshExpiresAt.Sub(time.Now()); lifetime <= 0 || lifetime > auth.RefreshTokenLifetime+time.Minute {
		t.Fatalf("refresh token lifetime = %v", lifetime)
	}

	accessDigest := sha256.Sum256([]byte(initial.Token))
	if _, err := test.db.Exec(`UPDATE sessions SET expires_at=now()-interval '1 second' WHERE token_hash=$1`, hex.EncodeToString(accessDigest[:])); err != nil {
		t.Fatalf("expire access token: %v", err)
	}
	doJSON(t, client, http.MethodGet, baseURL+"/api/v1/groups", initial.Token, nil, http.StatusUnauthorized, nil)

	var rotated auth.Session
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/auth/refresh", "", map[string]string{"refresh_token": initial.RefreshToken}, http.StatusOK, &rotated)
	if rotated.Token == initial.Token || rotated.RefreshToken == initial.RefreshToken || rotated.User.ID != initial.User.ID {
		t.Fatalf("refresh did not rotate the session: initial=%#v rotated=%#v", initial, rotated)
	}
	doJSON(t, client, http.MethodGet, baseURL+"/api/v1/groups", rotated.Token, nil, http.StatusOK, nil)

	// Reusing the consumed token revokes the whole family, including tokens
	// returned by the successful rotation.
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/auth/refresh", "", map[string]string{"refresh_token": initial.RefreshToken}, http.StatusUnauthorized, nil)
	doJSON(t, client, http.MethodGet, baseURL+"/api/v1/groups", rotated.Token, nil, http.StatusUnauthorized, nil)
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/auth/refresh", "", map[string]string{"refresh_token": rotated.RefreshToken}, http.StatusUnauthorized, nil)

	current := loginUser(t, client, baseURL, "sessions@example.test")
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/auth/sign-out", current.Token, nil, http.StatusNoContent, nil)
	doJSON(t, client, http.MethodGet, baseURL+"/api/v1/groups", current.Token, nil, http.StatusUnauthorized, nil)
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/auth/refresh", "", map[string]string{"refresh_token": current.RefreshToken}, http.StatusUnauthorized, nil)

	deviceOne := loginUser(t, client, baseURL, "sessions@example.test")
	deviceTwo := loginUser(t, client, baseURL, "sessions@example.test")
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/auth/sign-out-all", deviceOne.Token, nil, http.StatusNoContent, nil)
	for name, session := range map[string]auth.Session{"device_one": deviceOne, "device_two": deviceTwo} {
		t.Run("all_devices_revoked_"+name, func(t *testing.T) {
			doJSON(t, client, http.MethodGet, baseURL+"/api/v1/groups", session.Token, nil, http.StatusUnauthorized, nil)
			doJSON(t, client, http.MethodPost, baseURL+"/api/v1/auth/refresh", "", map[string]string{"refresh_token": session.RefreshToken}, http.StatusUnauthorized, nil)
		})
	}

	expiredRefresh := loginUser(t, client, baseURL, "sessions@example.test")
	refreshDigest := sha256.Sum256([]byte(expiredRefresh.RefreshToken))
	if _, err := test.db.Exec(`UPDATE refresh_tokens SET expires_at=now()-interval '1 second' WHERE token_hash=$1`, hex.EncodeToString(refreshDigest[:])); err != nil {
		t.Fatalf("expire refresh token: %v", err)
	}
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/auth/refresh", "", map[string]string{"refresh_token": expiredRefresh.RefreshToken}, http.StatusUnauthorized, nil)
	doJSON(t, client, http.MethodGet, baseURL+"/api/v1/groups", expiredRefresh.Token, nil, http.StatusUnauthorized, nil)

	concurrent := loginUser(t, client, baseURL, "sessions@example.test")
	type refreshResult struct {
		status  int
		session auth.Session
		err     error
	}
	start := make(chan struct{})
	results := make(chan refreshResult, 2)
	var requests sync.WaitGroup
	for range 2 {
		requests.Add(1)
		go func() {
			defer requests.Done()
			<-start
			body, _ := json.Marshal(map[string]string{"refresh_token": concurrent.RefreshToken})
			response, err := client.Post(baseURL+"/api/v1/auth/refresh", "application/json", bytes.NewReader(body))
			result := refreshResult{err: err}
			if err == nil {
				result.status = response.StatusCode
				if response.StatusCode == http.StatusOK {
					result.err = json.NewDecoder(response.Body).Decode(&result.session)
				}
				_ = response.Body.Close()
			}
			results <- result
		}()
	}
	close(start)
	requests.Wait()
	close(results)
	statuses := map[int]int{}
	var winner auth.Session
	for result := range results {
		if result.err != nil {
			t.Fatalf("concurrent refresh: %v", result.err)
		}
		statuses[result.status]++
		if result.status == http.StatusOK {
			winner = result.session
		}
	}
	if statuses[http.StatusOK] != 1 || statuses[http.StatusUnauthorized] != 1 {
		t.Fatalf("concurrent refresh statuses = %#v, want one 200 and one 401", statuses)
	}
	doJSON(t, client, http.MethodGet, baseURL+"/api/v1/groups", winner.Token, nil, http.StatusUnauthorized, nil)
}

func TestAPIDatabaseFailureReturnsSafeError(t *testing.T) {
	t.Parallel()
	test := newPostgreSQLApplication(t)
	if _, err := test.db.Exec(`DROP TABLE users CASCADE`); err != nil {
		t.Fatalf("force representative SQL failure: %v", err)
	}
	var response apiError
	doJSON(t, test.server.Client(), http.MethodPost, test.server.URL+"/api/v1/auth/register", "", map[string]any{
		"name":         "Ana",
		"email":        "ana@example.test",
		"phone":        "+525511112222",
		"password":     "password1",
		"salary_cents": 100,
	}, http.StatusInternalServerError, &response)
	if response.Code != "internal_error" || response.Message != "internal error" || response.Error != response.Message {
		t.Fatalf("database failure response = %#v", response)
	}
}

type postgresApplication struct {
	db     *sql.DB
	server *httptest.Server
}

func newPostgreSQLApplication(t *testing.T) postgresApplication {
	t.Helper()
	databaseURL := os.Getenv("TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}
	admin, err := database.Open(databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	t.Cleanup(cancel)
	if err := admin.PingContext(ctx); err != nil {
		_ = admin.Close()
		t.Fatalf("connect to integration database: %v", err)
	}
	schema := fmt.Sprintf("api_test_%d_%d", time.Now().UnixNano(), apiSchemaSequence.Add(1))
	if _, err := admin.ExecContext(ctx, `CREATE SCHEMA "`+schema+`"`); err != nil {
		_ = admin.Close()
		t.Fatalf("create integration schema: %v", err)
	}
	t.Cleanup(func() {
		cleanupContext, cleanupCancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cleanupCancel()
		if _, err := admin.ExecContext(cleanupContext, `DROP SCHEMA "`+schema+`" CASCADE`); err != nil {
			t.Errorf("drop integration schema %s: %v", schema, err)
		}
		_ = admin.Close()
	})
	scopedURL, err := url.Parse(databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	query := scopedURL.Query()
	query.Set("search_path", schema)
	scopedURL.RawQuery = query.Encode()

	db, err := database.Open(scopedURL.String())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Close() })
	if _, err := database.Migrate(ctx, db); err != nil {
		t.Fatalf("apply integration migrations: %v", err)
	}
	groupRepository, err := groups.Open(ctx, scopedURL.String())
	if err != nil {
		t.Fatalf("open group repository: %v", err)
	}
	t.Cleanup(func() { _ = groupRepository.Close() })
	authRepository, err := auth.Open(scopedURL.String())
	if err != nil {
		t.Fatalf("open auth repository: %v", err)
	}
	t.Cleanup(func() { _ = authRepository.Close() })
	paymentRepository, err := payments.Open(ctx, scopedURL.String())
	if err != nil {
		t.Fatalf("open payment repository: %v", err)
	}
	t.Cleanup(func() { _ = paymentRepository.Close() })
	app := application{auth: authRepository, groups: groupRepository, payments: payments.SimulatedProvider{}, requests: paymentRepository}
	server := httptest.NewServer(app.routes("*"))
	t.Cleanup(server.Close)
	return postgresApplication{db: db, server: server}
}

func registerUser(t *testing.T, client *http.Client, baseURL, name, email, phone string) auth.Session {
	t.Helper()
	var session auth.Session
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/auth/register", "", map[string]any{
		"name":         name,
		"email":        email,
		"phone":        phone,
		"password":     "password1",
		"salary_cents": 100000,
	}, http.StatusCreated, &session)
	if session.Token == "" || session.RefreshToken == "" || session.User.ID == "" {
		t.Fatalf("registration returned incomplete session: %#v", session)
	}
	return session
}

func loginUser(t *testing.T, client *http.Client, baseURL, email string) auth.Session {
	t.Helper()
	var session auth.Session
	doJSON(t, client, http.MethodPost, baseURL+"/api/v1/auth/login", "", map[string]string{
		"email":    email,
		"password": "password1",
	}, http.StatusOK, &session)
	if session.Token == "" || session.RefreshToken == "" || session.User.ID == "" {
		t.Fatalf("login returned incomplete session: %#v", session)
	}
	return session
}

func findMember(t *testing.T, group groups.Group, userID string) groups.Member {
	t.Helper()
	for _, member := range group.Members {
		if member.UserID == userID || member.ID == userID {
			return member
		}
	}
	t.Fatalf("group member for user %q not found in %#v", userID, group.Members)
	return groups.Member{}
}

func assertBalance(t *testing.T, group groups.Group, memberID string, want int64) {
	t.Helper()
	if got := group.Balances[memberID]; got != want {
		t.Fatalf("balance for %q = %d, want %d; balances=%#v", memberID, got, want, group.Balances)
	}
}

func doJSON(t *testing.T, client *http.Client, method, endpoint, token string, input any, wantStatus int, output any) {
	doJSONHeaders(t, client, method, endpoint, token, input, nil, wantStatus, output)
}

func doJSONHeaders(t *testing.T, client *http.Client, method, endpoint, token string, input any, headers map[string]string, wantStatus int, output any) {
	t.Helper()
	var body io.Reader
	if input != nil {
		encoded, err := json.Marshal(input)
		if err != nil {
			t.Fatal(err)
		}
		body = bytes.NewReader(encoded)
	}
	request, err := http.NewRequestWithContext(context.Background(), method, endpoint, body)
	if err != nil {
		t.Fatal(err)
	}
	if input != nil {
		request.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		request.Header.Set("Authorization", "Bearer "+token)
	}
	for name, value := range headers {
		request.Header.Set(name, value)
	}
	response, err := client.Do(request)
	if err != nil {
		t.Fatalf("%s %s: %v", method, endpoint, err)
	}
	defer response.Body.Close()
	contents, err := io.ReadAll(response.Body)
	if err != nil {
		t.Fatal(err)
	}
	if response.StatusCode != wantStatus {
		t.Fatalf("%s %s status = %d, want %d; body=%s", method, endpoint, response.StatusCode, wantStatus, strings.TrimSpace(string(contents)))
	}
	correlationID := response.Header.Get(correlationHeader)
	if !validCorrelationID(correlationID) {
		t.Fatalf("%s %s returned invalid correlation ID %q", method, endpoint, correlationID)
	}
	if output != nil && len(bytes.TrimSpace(contents)) > 0 {
		if err := json.Unmarshal(contents, output); err != nil {
			t.Fatalf("decode %s %s response %q: %v", method, endpoint, contents, err)
		}
	}
}
