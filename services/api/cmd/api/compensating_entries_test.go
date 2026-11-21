package main

import (
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/groups"
)

func TestCompensatingEntriesWorkflowWithPostgreSQL(t *testing.T) {
	t.Parallel()
	test := newPostgreSQLApplication(t)
	client := test.server.Client()

	ana := registerUser(t, client, test.server.URL, "Ana", "ana-rev@example.test", "+525511001100")
	beto := registerUser(t, client, test.server.URL, "Beto", "beto-rev@example.test", "+525522002200")
	carla := registerUser(t, client, test.server.URL, "Carla", "carla-rev@example.test", "+525533003300")
	outsider := registerUser(t, client, test.server.URL, "Diego", "diego-rev@example.test", "+525544004400")

	// Create a shared group with Ana (owner), Beto (member), Carla (pending invitee initially).
	var shared groups.Group
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups", ana.Token, map[string]any{
		"name":       "Casa",
		"emoji":      "🏠",
		"visibility": "shared",
		"members": []map[string]string{
			{"name": "Beto", "phone": "+525522002200"},
			{"name": "Carla", "phone": "+525533003300"},
		},
	}, http.StatusCreated, &shared)
	anaMember := findMember(t, shared, ana.User.ID)
	betoMember := findMember(t, shared, beto.User.ID)
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/group-invitations/"+shared.ID+"/response", beto.Token, map[string]bool{"accept": true}, http.StatusNoContent, nil)

	// Create a separate personal group owned by Ana to test cross-group hiding.
	var personal groups.Group
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups", ana.Token, map[string]any{
		"name":         "Personal",
		"emoji":        "🧾",
		"visibility":   "personal",
		"member_names": []string{"Amigo"},
	}, http.StatusCreated, &personal)
	personalOwner := findMember(t, personal, ana.User.ID)
	var personalFriend groups.Member
	for _, m := range personal.Members {
		if m.ID != personalOwner.ID {
			personalFriend = m
			break
		}
	}

	// Post an expense in the shared group: Ana pays 1000 split equally with Beto (Beto owes Ana 500).
	var afterExpense groups.Group
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+shared.ID+"/expenses", ana.Token, map[string]any{
		"description":     "Super",
		"amount_cents":    1000,
		"payer_id":        anaMember.ID,
		"participant_ids": []string{anaMember.ID, betoMember.ID},
		"split_mode":      "equal",
	}, http.StatusCreated, &afterExpense)
	origExpense := afterExpense.Expenses[0]
	assertBalance(t, afterExpense, anaMember.ID, 500)
	assertBalance(t, afterExpense, betoMember.ID, -500)

	// Post an expense in the personal group to test cross-group probing.
	var afterPersonalExpense groups.Group
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+personal.ID+"/expenses", ana.Token, map[string]any{
		"description":     "Cafe",
		"amount_cents":    400,
		"payer_id":        personalFriend.ID,
		"participant_ids": []string{personalOwner.ID, personalFriend.ID},
		"split_mode":      "equal",
	}, http.StatusCreated, &afterPersonalExpense)
	personalExpense := afterPersonalExpense.Expenses[0]

	// 1. Immutability: expenses and settlements cannot be updated or deleted through application commands.
	for _, tc := range []struct {
		method string
		path   string
		status int
	}{
		{http.MethodPut, "/api/v1/groups/" + shared.ID + "/expenses/" + origExpense.ID, http.StatusNotFound},
		{http.MethodPatch, "/api/v1/groups/" + shared.ID + "/expenses/" + origExpense.ID, http.StatusNotFound},
		{http.MethodDelete, "/api/v1/groups/" + shared.ID + "/expenses/" + origExpense.ID, http.StatusNotFound},
		{http.MethodDelete, "/api/v1/groups/" + shared.ID + "/expenses", http.StatusNotFound},
		{http.MethodDelete, "/api/v1/groups/" + shared.ID + "/settlements", http.StatusNotFound},
	} {
		doJSON(t, client, tc.method, test.server.URL+tc.path, ana.Token, map[string]any{"amount_cents": 1}, tc.status, nil)
	}

	// 2. Hidden records & authorization on expense reversals.
	// Outsider and pending invitee (Carla) get 404.
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+shared.ID+"/expenses/"+origExpense.ID+"/reversals", outsider.Token, map[string]any{
		"reason": "Intruso",
	}, http.StatusNotFound, nil)
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+shared.ID+"/expenses/"+origExpense.ID+"/reversals", carla.Token, map[string]any{
		"reason": "Pendiente",
	}, http.StatusNotFound, nil)
	// Cross-group expense ID passed against shared group returns 404.
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+shared.ID+"/expenses/"+personalExpense.ID+"/reversals", ana.Token, map[string]any{
		"reason": "Otro grupo",
	}, http.StatusNotFound, nil)
	// Outsider cannot reverse in personal group.
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+personal.ID+"/expenses/"+personalExpense.ID+"/reversals", beto.Token, map[string]any{
		"reason": "No autorizado",
	}, http.StatusNotFound, nil)

	// Validation: empty or overly long reason is rejected with 422.
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+shared.ID+"/expenses/"+origExpense.ID+"/reversals", beto.Token, map[string]any{
		"reason": "   ",
	}, http.StatusUnprocessableEntity, nil)
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+shared.ID+"/expenses/"+origExpense.ID+"/reversals", beto.Token, map[string]any{
		"reason": strings.Repeat("x", groups.MaxReversalReasonLength+1),
	}, http.StatusUnprocessableEntity, nil)

	// Replacement before reversal is rejected with 422.
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+shared.ID+"/expenses", ana.Token, map[string]any{
		"description":         "Reemplazo prematuro",
		"amount_cents":        800,
		"payer_id":            anaMember.ID,
		"participant_ids":     []string{anaMember.ID, betoMember.ID},
		"split_mode":          "equal",
		"replaces_expense_id": origExpense.ID,
	}, http.StatusUnprocessableEntity, nil)

	// 3. Accepted shared-group member (Beto) reverses the expense with an Idempotency-Key.
	revKey := "rev-exp-1"
	var reversedGroup groups.Group
	doJSONHeaders(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+shared.ID+"/expenses/"+origExpense.ID+"/reversals", beto.Token, map[string]any{
		"reason": "Monto capturado mal",
	}, map[string]string{"Idempotency-Key": revKey}, http.StatusCreated, &reversedGroup)

	if len(reversedGroup.Expenses) != 1 || reversedGroup.Expenses[0].ID != origExpense.ID {
		t.Fatalf("original expense must remain visible: %#v", reversedGroup.Expenses)
	}
	if len(reversedGroup.ExpenseReversals) != 1 {
		t.Fatalf("expected 1 expense reversal, got %#v", reversedGroup.ExpenseReversals)
	}
	rev := reversedGroup.ExpenseReversals[0]
	if rev.OriginalExpenseID != origExpense.ID || rev.ActorUserID != beto.User.ID || rev.ActorMemberID != betoMember.ID || rev.Reason != "Monto capturado mal" || rev.CreatedAt.IsZero() {
		t.Fatalf("unexpected reversal audit metadata: %#v", rev)
	}
	assertBalance(t, reversedGroup, anaMember.ID, 0)
	assertBalance(t, reversedGroup, betoMember.ID, 0)
	if len(reversedGroup.PaymentRelations) != 0 {
		t.Fatalf("expected zero payment relations after reversal, got %#v", reversedGroup.PaymentRelations)
	}

	// Idempotent retry replays stored 201 outcome without creating a second reversal.
	var replayed groups.Group
	doJSONHeaders(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+shared.ID+"/expenses/"+origExpense.ID+"/reversals", beto.Token, map[string]any{
		"reason": "Monto capturado mal",
	}, map[string]string{"Idempotency-Key": revKey}, http.StatusCreated, &replayed)
	if len(replayed.ExpenseReversals) != 1 || replayed.ExpenseReversals[0].ID != rev.ID {
		t.Fatalf("idempotent replay did not return same reversal: %#v", replayed.ExpenseReversals)
	}

	// Same Idempotency-Key with different reason returns 409 idempotency_key_conflict.
	var conflict apiError
	doJSONHeaders(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+shared.ID+"/expenses/"+origExpense.ID+"/reversals", beto.Token, map[string]any{
		"reason": "Otro motivo",
	}, map[string]string{"Idempotency-Key": revKey}, http.StatusConflict, &conflict)
	if conflict.Code != "idempotency_key_conflict" {
		t.Fatalf("conflict code = %q, want idempotency_key_conflict", conflict.Code)
	}

	// Duplicate reversal with a new key (or another actor) returns 409 already_reversed.
	var dupErr apiError
	doJSONHeaders(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+shared.ID+"/expenses/"+origExpense.ID+"/reversals", ana.Token, map[string]any{
		"reason": "Segundo intento",
	}, map[string]string{"Idempotency-Key": "rev-exp-dup"}, http.StatusConflict, &dupErr)
	if dupErr.Code != "already_reversed" {
		t.Fatalf("duplicate reversal code = %q, want already_reversed", dupErr.Code)
	}

	// 4. Replacement expense is a separate immutable record linked to origExpense.ID.
	var withReplacement groups.Group
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+shared.ID+"/expenses", ana.Token, map[string]any{
		"description":         "Super corregido",
		"amount_cents":        800,
		"payer_id":            anaMember.ID,
		"participant_ids":     []string{anaMember.ID, betoMember.ID},
		"split_mode":          "equal",
		"replaces_expense_id": origExpense.ID,
	}, http.StatusCreated, &withReplacement)
	if len(withReplacement.Expenses) != 2 {
		t.Fatalf("expected original + replacement (2 expenses), got %d", len(withReplacement.Expenses))
	}
	var replacement groups.Expense
	for _, e := range withReplacement.Expenses {
		if e.ID != origExpense.ID {
			replacement = e
		}
	}
	if replacement.ID == "" || replacement.ReplacesExpenseID != origExpense.ID {
		t.Fatalf("replacement link missing: %#v", replacement)
	}
	assertBalance(t, withReplacement, anaMember.ID, 400)
	assertBalance(t, withReplacement, betoMember.ID, -400)

	// A second replacement for the same reversed expense is rejected with 422.
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+shared.ID+"/expenses", ana.Token, map[string]any{
		"description":         "Segundo reemplazo",
		"amount_cents":        800,
		"payer_id":            anaMember.ID,
		"participant_ids":     []string{anaMember.ID, betoMember.ID},
		"split_mode":          "equal",
		"replaces_expense_id": origExpense.ID,
	}, http.StatusUnprocessableEntity, nil)

	// 5. Partial settlements + settlement reversal + authorization + replacement settlement.
	// Beto owes Ana 400. Ana confirms two partial receipts: 150 and 100 (remaining 150).
	var afterPart1 groups.Group
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+shared.ID+"/settlements/received", ana.Token, map[string]any{
		"debtor_member_id": betoMember.ID,
		"amount_cents":     150,
	}, http.StatusCreated, &afterPart1)
	s1 := afterPart1.Settlements[0]

	var afterPart2 groups.Group
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+shared.ID+"/settlements/received", ana.Token, map[string]any{
		"debtor_member_id": betoMember.ID,
		"amount_cents":     100,
	}, http.StatusCreated, &afterPart2)
	assertBalance(t, afterPart2, anaMember.ID, 150)
	assertBalance(t, afterPart2, betoMember.ID, -150)

	// Settlements cannot be patched or deleted.
	doJSON(t, client, http.MethodDelete, test.server.URL+"/api/v1/groups/"+shared.ID+"/settlements/"+s1.ID, ana.Token, nil, http.StatusNotFound, nil)

	// Debtor (Beto, non-owner) CANNOT reverse a settlement paid to Ana -> 404.
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+shared.ID+"/settlements/"+s1.ID+"/reversals", beto.Token, map[string]any{
		"reason": "Deudor intentando revertir",
	}, http.StatusNotFound, nil)

	// Creditor (Ana) reverses s1 (150) -> remaining obligation becomes 300 (s2 of 100 remains intact).
	var afterSetRev groups.Group
	doJSONHeaders(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+shared.ID+"/settlements/"+s1.ID+"/reversals", ana.Token, map[string]any{
		"reason": "Transferencia devuelta",
	}, map[string]string{"Idempotency-Key": "rev-set-1"}, http.StatusCreated, &afterSetRev)

	if len(afterSetRev.Settlements) != 2 || len(afterSetRev.SettlementReversals) != 1 {
		t.Fatalf("expected 2 settlements and 1 reversal, got settlements=%d reversals=%d", len(afterSetRev.Settlements), len(afterSetRev.SettlementReversals))
	}
	if afterSetRev.SettlementReversals[0].OriginalSettlementID != s1.ID || afterSetRev.SettlementReversals[0].ActorUserID != ana.User.ID {
		t.Fatalf("unexpected settlement reversal: %#v", afterSetRev.SettlementReversals[0])
	}
	assertBalance(t, afterSetRev, anaMember.ID, 300)
	assertBalance(t, afterSetRev, betoMember.ID, -300)

	// Duplicate settlement reversal with new key -> 409 already_reversed.
	var dupSetErr apiError
	doJSONHeaders(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+shared.ID+"/settlements/"+s1.ID+"/reversals", ana.Token, map[string]any{
		"reason": "Repetido",
	}, map[string]string{"Idempotency-Key": "rev-set-dup"}, http.StatusConflict, &dupSetErr)
	if dupSetErr.Code != "already_reversed" {
		t.Fatalf("duplicate settlement reversal code = %q, want already_reversed", dupSetErr.Code)
	}

	// Creditor posts a separate replacement settlement of 300 linked to s1 -> balances land at 0!
	var settled groups.Group
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+shared.ID+"/settlements/received", ana.Token, map[string]any{
		"debtor_member_id":       betoMember.ID,
		"amount_cents":           300,
		"replaces_settlement_id": s1.ID,
	}, http.StatusCreated, &settled)
	if len(settled.Settlements) != 3 {
		t.Fatalf("expected 3 settlements (s1 + s2 + replacement), got %d", len(settled.Settlements))
	}
	assertBalance(t, settled, anaMember.ID, 0)
	assertBalance(t, settled, betoMember.ID, 0)
	if len(settled.PaymentRelations) != 0 {
		t.Fatalf("expected zero relations after replacement settlement, got %#v", settled.PaymentRelations)
	}

	// Verify shared-group creditor (non-owner Beto) CAN reverse a settlement where Beto is the creditor.
	var betoExpGroup groups.Group
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+shared.ID+"/expenses", beto.Token, map[string]any{
		"description":     "Pizza",
		"amount_cents":    600,
		"payer_id":        betoMember.ID,
		"participant_ids": []string{anaMember.ID, betoMember.ID},
		"split_mode":      "equal",
	}, http.StatusCreated, &betoExpGroup)
	var betoSetGroup groups.Group
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+shared.ID+"/settlements/received", beto.Token, map[string]any{
		"debtor_member_id": anaMember.ID,
		"amount_cents":     300,
	}, http.StatusCreated, &betoSetGroup)
	betoSettlement := betoSetGroup.Settlements[0]
	var betoRevGroup groups.Group
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+shared.ID+"/settlements/"+betoSettlement.ID+"/reversals", beto.Token, map[string]any{
		"reason": "Error de registro",
	}, http.StatusCreated, &betoRevGroup)
	assertBalance(t, betoRevGroup, betoMember.ID, 300)
	assertBalance(t, betoRevGroup, anaMember.ID, -300)

	// Verify personal group manual settlement reversal + replacement by owner.
	var pSettled groups.Group
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+personal.ID+"/settlements", ana.Token, map[string]any{
		"member_id":    personalFriend.ID,
		"amount_cents": 200,
	}, http.StatusCreated, &pSettled)
	pSet := pSettled.Settlements[0]
	var pRev groups.Group
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+personal.ID+"/settlements/"+pSet.ID+"/reversals", ana.Token, map[string]any{
		"reason": "Efectivo pendiente",
	}, http.StatusCreated, &pRev)
	assertBalance(t, pRev, personalOwner.ID, -200)
	assertBalance(t, pRev, personalFriend.ID, 200)
	var pReplaced groups.Group
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+personal.ID+"/settlements", ana.Token, map[string]any{
		"member_id":              personalFriend.ID,
		"amount_cents":           200,
		"replaces_settlement_id": pSet.ID,
	}, http.StatusCreated, &pReplaced)
	assertBalance(t, pReplaced, personalOwner.ID, 0)
	assertBalance(t, pReplaced, personalFriend.ID, 0)
}

func TestOfflineSyncCompensatingEntriesWithPostgreSQL(t *testing.T) {
	t.Parallel()
	test := newPostgreSQLApplication(t)
	client := test.server.Client()

	owner := registerUser(t, client, test.server.URL, "Sofía", "sofia-sync-rev@example.test", "+525566006600")
	baseTime := time.Date(2026, 11, 21, 15, 0, 0, 0, time.UTC)

	syncPayload := map[string]any{
		"groups": []map[string]any{
			{
				"id":                   "local_group_rev_1",
				"name":                 "Viaje Offline",
				"emoji":                "✈️",
				"visibility":           "personal",
				"salary_split_enabled": false,
				"members": []map[string]any{
					{"id": "me", "name": "Sofía", "phone": "", "salary_sharing": false, "active": true},
					{"id": "local_member_1", "name": "Luis", "phone": "", "salary_sharing": false, "active": true},
				},
				"expenses": []map[string]any{
					{
						"id":                "local_expense_1",
						"description":       "Hotel equivocado",
						"amount_cents":      1000,
						"payer_id":          "local_member_1",
						"payers":            []map[string]any{{"member_id": "local_member_1", "amount_cents": 1000}},
						"participant_ids":   []string{"me", "local_member_1"},
						"split_mode":        "equal",
						"shares":            map[string]int64{"me": 500, "local_member_1": 500},
						"split_overpayment": true,
						"created_at":        baseTime.Format(time.RFC3339),
					},
					{
						"id":                  "local_expense_2",
						"description":         "Hotel correcto",
						"amount_cents":        800,
						"payer_id":            "local_member_1",
						"payers":              []map[string]any{{"member_id": "local_member_1", "amount_cents": 800}},
						"participant_ids":     []string{"me", "local_member_1"},
						"split_mode":          "equal",
						"shares":              map[string]int64{"me": 400, "local_member_1": 400},
						"split_overpayment":   true,
						"replaces_expense_id": "local_expense_1",
						"created_at":          baseTime.Add(4 * time.Minute).Format(time.RFC3339),
					},
				},
				"expense_reversals": []map[string]any{
					{
						"id":                  "local_expense_reversal_1",
						"original_expense_id": "local_expense_1",
						"actor_member_id":     "me",
						"reason":              "Monto equivocado",
						"created_at":          baseTime.Add(3 * time.Minute).Format(time.RFC3339),
					},
				},
				"settlements": []map[string]any{
					{
						"id":             "local_settlement_1",
						"from_member_id": "me",
						"to_member_id":   "local_member_1",
						"amount_cents":   500,
						"created_at":     baseTime.Add(1 * time.Minute).Format(time.RFC3339),
					},
					{
						"id":                     "local_settlement_2",
						"from_member_id":         "me",
						"to_member_id":           "local_member_1",
						"amount_cents":           400,
						"replaces_settlement_id": "local_settlement_1",
						"created_at":             baseTime.Add(5 * time.Minute).Format(time.RFC3339),
					},
				},
				"settlement_reversals": []map[string]any{
					{
						"id":                     "local_settlement_reversal_1",
						"original_settlement_id": "local_settlement_1",
						"actor_member_id":        "me",
						"reason":                 "Pago con monto anterior",
						"created_at":             baseTime.Add(2 * time.Minute).Format(time.RFC3339),
					},
				},
			},
		},
	}

	// First sync commits chronologically and lands at exact zero balance.
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/offline-sync/groups", owner.Token, syncPayload, http.StatusOK, nil)

	// Retry is idempotent.
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/offline-sync/groups", owner.Token, syncPayload, http.StatusOK, nil)

	var listResp struct {
		Groups []groups.Group `json:"groups"`
	}
	doJSON(t, client, http.MethodGet, test.server.URL+"/api/v1/groups", owner.Token, nil, http.StatusOK, &listResp)
	if len(listResp.Groups) != 1 {
		t.Fatalf("expected 1 synced group, got %d", len(listResp.Groups))
	}
	synced := listResp.Groups[0]
	if len(synced.Expenses) != 2 || len(synced.ExpenseReversals) != 1 || len(synced.Settlements) != 2 || len(synced.SettlementReversals) != 1 {
		t.Fatalf("unexpected synced history counts: exp=%d erev=%d set=%d srev=%d",
			len(synced.Expenses), len(synced.ExpenseReversals), len(synced.Settlements), len(synced.SettlementReversals))
	}
	assertBalance(t, synced, owner.User.ID, 0)
	assertBalance(t, synced, "local_member_1", 0)

	// Modifying an already-synced reversal reason is rejected with 409 sync_conflict.
	tampered := syncPayload["groups"].([]map[string]any)[0]["expense_reversals"].([]map[string]any)
	tampered[0]["reason"] = "Motivo alterado"
	var conflict apiError
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/offline-sync/groups", owner.Token, syncPayload, http.StatusConflict, &conflict)
	if conflict.Code != "sync_conflict" {
		t.Fatalf("tampered reversal sync code = %q, want sync_conflict", conflict.Code)
	}
}

func TestExpenseReplacementAdjustsSettledParticipantsProportionally(t *testing.T) {
	t.Parallel()
	test := newPostgreSQLApplication(t)
	client := test.server.Client()

	ana := registerUser(t, client, test.server.URL, "Ana", "ana-prop@example.test", "+525571001100")
	beto := registerUser(t, client, test.server.URL, "Beto", "beto-prop@example.test", "+525572002200")
	carla := registerUser(t, client, test.server.URL, "Carla", "carla-prop@example.test", "+525573003300")

	var group groups.Group
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups", ana.Token, map[string]any{
		"name":       "Suscripciones",
		"emoji":      "📺",
		"visibility": "shared",
		"members": []map[string]string{
			{"name": "Beto", "phone": "+525572002200"},
			{"name": "Carla", "phone": "+525573003300"},
		},
	}, http.StatusCreated, &group)
	anaM := findMember(t, group, ana.User.ID)
	betoM := findMember(t, group, beto.User.ID)
	carlaM := findMember(t, group, carla.User.ID)
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/group-invitations/"+group.ID+"/response", beto.Token, map[string]bool{"accept": true}, http.StatusNoContent, nil)
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/group-invitations/"+group.ID+"/response", carla.Token, map[string]bool{"accept": true}, http.StatusNoContent, nil)

	// 1. Original $10.00 percentage expense (50% Ana, 30% Beto, 20% Carla).
	var g1 groups.Group
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+group.ID+"/expenses", ana.Token, map[string]any{
		"description":     "Plan",
		"amount_cents":    1000,
		"payer_id":        anaM.ID,
		"participant_ids": []string{anaM.ID, betoM.ID, carlaM.ID},
		"split_mode":      "percentage",
		"percentages": []map[string]any{
			{"member_id": anaM.ID, "percentage_bps": 5000},
			{"member_id": betoM.ID, "percentage_bps": 3000},
			{"member_id": carlaM.ID, "percentage_bps": 2000},
		},
	}, http.StatusCreated, &g1)
	exp1 := g1.Expenses[0]

	// Beto pays his full $3.00 debt; Carla has not paid yet.
	var afterPay groups.Group
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+group.ID+"/settlements/received", ana.Token, map[string]any{
		"debtor_member_id": betoM.ID,
		"amount_cents":     300,
	}, http.StatusCreated, &afterPay)
	assertBalance(t, afterPay, anaM.ID, 200)
	assertBalance(t, afterPay, betoM.ID, 0)
	assertBalance(t, afterPay, carlaM.ID, -200)

	// 2. Reverse exp1 and replace with HIGHER $15.00 expense -> Beto owes $1.50 difference, Carla owes $3.00.
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+group.ID+"/expenses/"+exp1.ID+"/reversals", ana.Token, map[string]any{
		"reason": "Monto mayor",
	}, http.StatusCreated, nil)
	var gHigher groups.Group
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+group.ID+"/expenses", ana.Token, map[string]any{
		"description":         "Plan ajustado",
		"amount_cents":        1500,
		"payer_id":            anaM.ID,
		"participant_ids":     []string{anaM.ID, betoM.ID, carlaM.ID},
		"split_mode":          "percentage",
		"replaces_expense_id": exp1.ID,
		"percentages": []map[string]any{
			{"member_id": anaM.ID, "percentage_bps": 5000},
			{"member_id": betoM.ID, "percentage_bps": 3000},
			{"member_id": carlaM.ID, "percentage_bps": 2000},
		},
	}, http.StatusCreated, &gHigher)
	assertBalance(t, gHigher, anaM.ID, 450)
	assertBalance(t, gHigher, betoM.ID, -150)
	assertBalance(t, gHigher, carlaM.ID, -300)

	var exp2 groups.Expense
	for _, e := range gHigher.Expenses {
		if e.ReplacesExpenseID == exp1.ID {
			exp2 = e
		}
	}

	// 3. Reverse exp2 and replace with LOWER $5.00 expense -> Beto gets +$1.50 credit in favor, Carla owes $1.00.
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+group.ID+"/expenses/"+exp2.ID+"/reversals", ana.Token, map[string]any{
		"reason": "Monto menor",
	}, http.StatusCreated, nil)
	var gLower groups.Group
	doJSON(t, client, http.MethodPost, test.server.URL+"/api/v1/groups/"+group.ID+"/expenses", ana.Token, map[string]any{
		"description":         "Plan con descuento",
		"amount_cents":        500,
		"payer_id":            anaM.ID,
		"participant_ids":     []string{anaM.ID, betoM.ID, carlaM.ID},
		"split_mode":          "percentage",
		"replaces_expense_id": exp2.ID,
		"percentages": []map[string]any{
			{"member_id": anaM.ID, "percentage_bps": 5000},
			{"member_id": betoM.ID, "percentage_bps": 3000},
			{"member_id": carlaM.ID, "percentage_bps": 2000},
		},
	}, http.StatusCreated, &gLower)
	assertBalance(t, gLower, anaM.ID, -50)
	assertBalance(t, gLower, betoM.ID, 150)
	assertBalance(t, gLower, carlaM.ID, -100)

	var foundCredit, foundCarlaDebt bool
	for _, rel := range gLower.PaymentRelations {
		if rel.FromMemberID == anaM.ID && rel.ToMemberID == betoM.ID && rel.AmountCents == 150 {
			foundCredit = true
		}
		if rel.FromMemberID == carlaM.ID && rel.ToMemberID == anaM.ID && rel.AmountCents == 100 {
			foundCarlaDebt = true
		}
	}
	if !foundCredit || !foundCarlaDebt {
		t.Fatalf("expected Ana->Beto 150 credit and Carla->Ana 100 debt, got %#v", gLower.PaymentRelations)
	}
}
