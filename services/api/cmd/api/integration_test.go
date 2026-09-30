package main

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
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

	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups", "", map[string]any{
		"name":         "Sin sesion",
		"member_names": []string{"Invitado"},
	}, http.StatusUnauthorized, nil)

	owner := registerUser(t, client, test.server.URL, "Ana", "ana@example.test", "+525511112222")
	member := registerUser(t, client, test.server.URL, "Beto", "beto@example.test", "+525522223333")
	ownerLogin := loginUser(t, client, test.server.URL, "ana@example.test")
	memberLogin := loginUser(t, client, test.server.URL, "beto@example.test")
	if ownerLogin.User.ID != owner.User.ID || memberLogin.User.ID != member.User.ID {
		t.Fatalf("login returned different users: owner=%q member=%q", ownerLogin.User.ID, memberLogin.User.ID)
	}

	var group groups.Group
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups", ownerLogin.Token, map[string]any{
		"name":       "Viaje",
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
		"description":     "Cena",
		"amount_cents":    1001,
		"payer_id":        ownerMember.ID,
		"participant_ids": []string{ownerMember.ID, invitedMember.ID},
		"split_mode":      "equal",
	}, http.StatusCreated, &withExpense)
	assertBalance(t, withExpense, ownerMember.ID, 500)
	assertBalance(t, withExpense, invitedMember.ID, -500)
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
	var participantCount int
	if err := test.db.QueryRow(`SELECT amount_cents FROM expenses WHERE id=$1`, withExpense.Expenses[0].ID).Scan(&expenseAmount); err != nil {
		t.Fatalf("read persisted expense: %v", err)
	}
	if err := test.db.QueryRow(`SELECT count(*) FROM expense_participants WHERE expense_id=$1`, withExpense.Expenses[0].ID).Scan(&participantCount); err != nil {
		t.Fatalf("read persisted participants: %v", err)
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
	if len(settled.Settlements) != 1 || settled.Settlements[0].AmountCents != 500 {
		t.Fatalf("unexpected settlement response: %#v", settled.Settlements)
	}

	var settlementAmount int64
	var fromMember, toMember string
	if err := test.db.QueryRow(`SELECT amount_cents,from_member_id,to_member_id FROM settlements WHERE group_id=$1`, group.ID).Scan(&settlementAmount, &fromMember, &toMember); err != nil {
		t.Fatalf("read persisted settlement: %v", err)
	}
	if settlementAmount != 500 || fromMember != invitedMember.ID || toMember != ownerMember.ID {
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

func TestAPIDatabaseFailureReturnsSafeError(t *testing.T) {
	t.Parallel()
	test := newPostgreSQLApplication(t)
	if _, err := test.db.Exec(`DROP TABLE users CASCADE`); err != nil {
		t.Fatalf("force representative SQL failure: %v", err)
	}
	var response map[string]string
	doJSON(t, test.server.Client(), http.MethodPost, test.server.URL+"/api/v1/auth/register", "", map[string]any{
		"name":         "Ana",
		"email":        "ana@example.test",
		"phone":        "+525511112222",
		"password":     "password1",
		"salary_cents": 100,
	}, http.StatusInternalServerError, &response)
	if response["error"] != "internal error" {
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
	app := application{auth: authRepository, groups: groupRepository, payments: payments.SimulatedProvider{}}
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
	if session.Token == "" || session.User.ID == "" {
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
	if session.Token == "" || session.User.ID == "" {
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
	if output != nil && len(bytes.TrimSpace(contents)) > 0 {
		if err := json.Unmarshal(contents, output); err != nil {
			t.Fatalf("decode %s %s response %q: %v", method, endpoint, contents, err)
		}
	}
}
