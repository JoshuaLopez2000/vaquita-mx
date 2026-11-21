package groups

import (
	"math/rand"
	"strings"
	"testing"
	"time"
)

func TestExpenseReversalNegatesLedgerEffectExactlyOnce(t *testing.T) {
	now := time.Date(2026, 11, 21, 12, 0, 0, 0, time.UTC)
	base := Group{
		Members: []Member{
			{ID: "ana", Active: true, Accepted: true},
			{ID: "beto", Active: true, Accepted: true},
			{ID: "carla", Active: true, Accepted: true},
		},
		Expenses: []Expense{
			{
				ID:          "exp_1",
				Description: "Cena",
				AmountCents: 1001,
				PayerID:     "ana",
				Payers: []ExpensePayer{
					{MemberID: "ana", AmountCents: 700},
					{MemberID: "beto", AmountCents: 401},
				},
				ParticipantIDs:   []string{"ana", "beto", "carla"},
				SplitMode:        "percentage",
				Percentages:      map[string]int{"ana": 5000, "beto": 3000, "carla": 2000},
				ExplicitShares:   []ExpenseShare{{MemberID: "ana", AmountCents: 551}, {MemberID: "beto", AmountCents: 330}, {MemberID: "carla", AmountCents: 220}},
				SplitOverpayment: true,
				CreatedAt:        now,
			},
			{
				ID:               "exp_2",
				Description:      "Propina retenida",
				AmountCents:      300,
				PayerID:          "carla",
				Payers:           []ExpensePayer{{MemberID: "carla", AmountCents: 450}},
				ParticipantIDs:   []string{"ana", "beto", "carla"},
				SplitMode:        "equal",
				SplitOverpayment: false,
				CreatedAt:        now.Add(time.Minute),
			},
		},
	}

	reversed := base
	reversed.ExpenseReversals = []ExpenseReversal{
		{ID: "rev_1", OriginalExpenseID: "exp_1", ActorUserID: "u_ana", ActorMemberID: "ana", Reason: "Monto incorrecto", CreatedAt: now.Add(2 * time.Minute)},
		{ID: "rev_2", OriginalExpenseID: "exp_2", ActorUserID: "u_carla", ActorMemberID: "carla", Reason: "Duplicado", CreatedAt: now.Add(3 * time.Minute)},
	}

	balances, err := calculateBalances(reversed)
	if err != nil {
		t.Fatalf("calculateBalances returned error: %v", err)
	}
	for _, member := range reversed.Members {
		if balances[member.ID] != 0 {
			t.Fatalf("balance[%s] = %d, want 0; balances=%#v", member.ID, balances[member.ID], balances)
		}
	}
	relations, err := bilateralRelations(reversed)
	if err != nil {
		t.Fatalf("bilateralRelations returned error: %v", err)
	}
	if len(relations) != 0 {
		t.Fatalf("relations = %#v, want empty", relations)
	}
}

func TestSettlementReversalAndPartialSettlements(t *testing.T) {
	now := time.Date(2026, 11, 21, 12, 0, 0, 0, time.UTC)
	group := Group{
		Members: []Member{
			{ID: "ana", Active: true, Accepted: true},
			{ID: "diego", Active: true, Accepted: true},
		},
		Expenses: []Expense{
			{
				ID:             "exp_1",
				AmountCents:    1000,
				PayerID:        "ana",
				ParticipantIDs: []string{"ana", "diego"},
				SplitMode:      "equal",
				CreatedAt:      now,
			},
		},
		Settlements: []Settlement{
			{ID: "set_1", FromMemberID: "diego", ToMemberID: "ana", AmountCents: 200, CreatedAt: now.Add(time.Minute)},
			{ID: "set_2", FromMemberID: "diego", ToMemberID: "ana", AmountCents: 150, CreatedAt: now.Add(2 * time.Minute)},
		},
		SettlementReversals: []SettlementReversal{
			{ID: "srev_1", OriginalSettlementID: "set_1", ActorUserID: "u_ana", ActorMemberID: "ana", Reason: "Transferencia rebotada", CreatedAt: now.Add(3 * time.Minute)},
		},
	}

	balances, err := calculateBalances(group)
	if err != nil {
		t.Fatalf("calculateBalances: %v", err)
	}
	// Expense leaves Diego owing 500; set_1 (200) is reversed; set_2 (150) stays -> Diego owes 350.
	if balances["ana"] != 350 || balances["diego"] != -350 {
		t.Fatalf("balances = %#v, want ana=350 diego=-350", balances)
	}
	relations, err := bilateralRelations(group)
	if err != nil {
		t.Fatalf("bilateralRelations: %v", err)
	}
	if len(relations) != 1 || relations[0] != (PaymentRelation{FromMemberID: "diego", ToMemberID: "ana", AmountCents: 350}) {
		t.Fatalf("relations = %#v, want diego->ana 350", relations)
	}

	// Reversing the original expense while partial settlement set_2 (150) remains
	// preserves separate settlement history and yields zero-sum balances.
	group.ExpenseReversals = []ExpenseReversal{
		{ID: "erev_1", OriginalExpenseID: "exp_1", ActorUserID: "u_ana", ActorMemberID: "ana", Reason: "Gasto cancelado", CreatedAt: now.Add(4 * time.Minute)},
	}
	balances, err = calculateBalances(group)
	if err != nil {
		t.Fatalf("calculateBalances after expense reversal: %v", err)
	}
	if balances["ana"] != -150 || balances["diego"] != 150 {
		t.Fatalf("balances after expense reversal = %#v, want ana=-150 diego=150", balances)
	}
	relations, err = bilateralRelations(group)
	if err != nil {
		t.Fatalf("bilateralRelations after expense reversal: %v", err)
	}
	if len(relations) != 1 || relations[0] != (PaymentRelation{FromMemberID: "ana", ToMemberID: "diego", AmountCents: 150}) {
		t.Fatalf("relations after expense reversal = %#v, want ana->diego 150", relations)
	}
}

func TestLedgerRejectsDuplicateAndUnknownReversals(t *testing.T) {
	now := time.Date(2026, 11, 21, 12, 0, 0, 0, time.UTC)
	base := Group{
		Members: []Member{
			{ID: "ana", Active: true, Accepted: true},
			{ID: "beto", Active: true, Accepted: true},
		},
		Expenses: []Expense{
			{ID: "exp_1", AmountCents: 500, PayerID: "ana", ParticipantIDs: []string{"ana", "beto"}, CreatedAt: now},
		},
		Settlements: []Settlement{
			{ID: "set_1", FromMemberID: "beto", ToMemberID: "ana", AmountCents: 100, CreatedAt: now.Add(time.Minute)},
		},
	}

	cases := []struct {
		name  string
		group func() Group
	}{
		{
			name: "duplicate expense reversal",
			group: func() Group {
				g := base
				g.ExpenseReversals = []ExpenseReversal{
					{ID: "r1", OriginalExpenseID: "exp_1", Reason: "first"},
					{ID: "r2", OriginalExpenseID: "exp_1", Reason: "second"},
				}
				return g
			},
		},
		{
			name: "unknown expense reversal",
			group: func() Group {
				g := base
				g.ExpenseReversals = []ExpenseReversal{
					{ID: "r1", OriginalExpenseID: "exp_missing", Reason: "missing"},
				}
				return g
			},
		},
		{
			name: "duplicate settlement reversal",
			group: func() Group {
				g := base
				g.SettlementReversals = []SettlementReversal{
					{ID: "r1", OriginalSettlementID: "set_1", Reason: "first"},
					{ID: "r2", OriginalSettlementID: "set_1", Reason: "second"},
				}
				return g
			},
		},
		{
			name: "unknown settlement reversal",
			group: func() Group {
				g := base
				g.SettlementReversals = []SettlementReversal{
					{ID: "r1", OriginalSettlementID: "set_missing", Reason: "missing"},
				}
				return g
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			g := tc.group()
			if _, err := calculateBalances(g); err != ErrInvalid {
				t.Fatalf("calculateBalances err = %v, want ErrInvalid", err)
			}
			if _, err := bilateralRelations(g); err != ErrInvalid {
				t.Fatalf("bilateralRelations err = %v, want ErrInvalid", err)
			}
		})
	}
}

func TestValidateReversalReason(t *testing.T) {
	if _, err := validateReversalReason(""); err != ErrInvalid {
		t.Fatalf("empty reason err = %v, want ErrInvalid", err)
	}
	if _, err := validateReversalReason("   \t\n "); err != ErrInvalid {
		t.Fatalf("whitespace reason err = %v, want ErrInvalid", err)
	}
	if _, err := validateReversalReason(strings.Repeat("á", MaxReversalReasonLength+1)); err != ErrInvalid {
		t.Fatalf("too long reason err = %v, want ErrInvalid", err)
	}
	exactMax := strings.Repeat("á", MaxReversalReasonLength)
	got, err := validateReversalReason("  " + exactMax + "  ")
	if err != nil || got != exactMax {
		t.Fatalf("exact max reason = (%q, %v), want (%q, nil)", got, err, exactMax)
	}
}

func TestPropertyReversalsPreserveZeroSumAndEquivalence(t *testing.T) {
	rng := rand.New(rand.NewSource(212121))
	now := time.Date(2026, 11, 21, 12, 0, 0, 0, time.UTC)

	for iter := 0; iter < 500; iter++ {
		memberCount := 2 + rng.Intn(5)
		members := make([]Member, memberCount)
		memberIDs := make([]string, memberCount)
		for i := 0; i < memberCount; i++ {
			id := "m" + string(rune('a'+i))
			members[i] = Member{ID: id, Active: true, Accepted: true}
			memberIDs[i] = id
		}

		expenseCount := 1 + rng.Intn(6)
		expenses := make([]Expense, 0, expenseCount)
		activeExpenses := make([]Expense, 0, expenseCount)
		expenseReversals := make([]ExpenseReversal, 0)

		for eIdx := 0; eIdx < expenseCount; eIdx++ {
			amount := int64(1 + rng.Intn(50000))
			payer := memberIDs[rng.Intn(memberCount)]
			exp := Expense{
				ID:               "exp_" + string(rune('0'+eIdx)),
				AmountCents:      amount,
				PayerID:          payer,
				Payers:           []ExpensePayer{{MemberID: payer, AmountCents: amount + int64(rng.Intn(500))}},
				ParticipantIDs:   memberIDs,
				SplitMode:        "equal",
				SplitOverpayment: rng.Intn(2) == 0,
				CreatedAt:        now.Add(time.Duration(eIdx) * time.Minute),
			}
			expenses = append(expenses, exp)
			if rng.Intn(3) == 0 {
				expenseReversals = append(expenseReversals, ExpenseReversal{
					ID:                "erev_" + string(rune('0'+eIdx)),
					OriginalExpenseID: exp.ID,
					ActorMemberID:     payer,
					Reason:            "Correccion",
					CreatedAt:         now.Add(time.Duration(expenseCount+eIdx) * time.Minute),
				})
			} else {
				activeExpenses = append(activeExpenses, exp)
			}
		}

		settlementCount := rng.Intn(5)
		settlements := make([]Settlement, 0, settlementCount)
		activeSettlements := make([]Settlement, 0, settlementCount)
		settlementReversals := make([]SettlementReversal, 0)
		for sIdx := 0; sIdx < settlementCount; sIdx++ {
			fromIdx := rng.Intn(memberCount)
			toIdx := (fromIdx + 1 + rng.Intn(memberCount-1)) % memberCount
			s := Settlement{
				ID:           "set_" + string(rune('0'+sIdx)),
				FromMemberID: memberIDs[fromIdx],
				ToMemberID:   memberIDs[toIdx],
				AmountCents:  int64(1 + rng.Intn(10000)),
				CreatedAt:    now.Add(time.Duration(20+sIdx) * time.Minute),
			}
			settlements = append(settlements, s)
			if rng.Intn(2) == 0 {
				settlementReversals = append(settlementReversals, SettlementReversal{
					ID:                   "srev_" + string(rune('0'+sIdx)),
					OriginalSettlementID: s.ID,
					ActorMemberID:        memberIDs[toIdx],
					Reason:               "Pago revertido",
					CreatedAt:            now.Add(time.Duration(30+sIdx) * time.Minute),
				})
			} else {
				activeSettlements = append(activeSettlements, s)
			}
		}

		withReversals := Group{
			Members:             members,
			Expenses:            expenses,
			ExpenseReversals:    expenseReversals,
			Settlements:         settlements,
			SettlementReversals: settlementReversals,
		}
		withoutReversed := Group{
			Members:     members,
			Expenses:    activeExpenses,
			Settlements: activeSettlements,
		}

		gotBalances, err := calculateBalances(withReversals)
		if err != nil {
			t.Fatalf("iter %d: calculateBalances with reversals: %v", iter, err)
		}
		wantBalances, err := calculateBalances(withoutReversed)
		if err != nil {
			t.Fatalf("iter %d: calculateBalances without reversed: %v", iter, err)
		}
		var sum int64
		for _, id := range memberIDs {
			sum += gotBalances[id]
			if gotBalances[id] != wantBalances[id] {
				t.Fatalf("iter %d: balance[%s]=%d want %d", iter, id, gotBalances[id], wantBalances[id])
			}
		}
		if sum != 0 {
			t.Fatalf("iter %d: sum of balances = %d, want 0", iter, sum)
		}

		gotRelations, err := bilateralRelations(withReversals)
		if err != nil {
			t.Fatalf("iter %d: bilateralRelations with reversals: %v", iter, err)
		}
		wantRelations, err := bilateralRelations(withoutReversed)
		if err != nil {
			t.Fatalf("iter %d: bilateralRelations without reversed: %v", iter, err)
		}
		if len(gotRelations) != len(wantRelations) {
			t.Fatalf("iter %d: relations len = %d want %d; got=%#v want=%#v", iter, len(gotRelations), len(wantRelations), gotRelations, wantRelations)
		}
		for i := range gotRelations {
			if gotRelations[i] != wantRelations[i] {
				t.Fatalf("iter %d: relation[%d] = %#v want %#v", iter, i, gotRelations[i], wantRelations[i])
			}
		}
	}
}
