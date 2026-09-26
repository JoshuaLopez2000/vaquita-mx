package groups

import "testing"

func TestBalancesAllocatesEveryCent(t *testing.T) {
	group := Group{
		Members: []Member{{ID: "me"}, {ID: "ana"}, {ID: "diego"}},
		Expenses: []Expense{{
			AmountCents:    100,
			PayerID:        "me",
			ParticipantIDs: []string{"me", "ana", "diego"},
		}},
	}

	balances := Balances(group)
	if balances["me"] != 66 || balances["ana"] != -33 || balances["diego"] != -33 {
		t.Fatalf("unexpected balances: %#v", balances)
	}
	if balances["me"]+balances["ana"]+balances["diego"] != 0 {
		t.Fatalf("balances do not sum to zero: %#v", balances)
	}
}

func TestBalancesAppliesSettlement(t *testing.T) {
	group := Group{
		Members: []Member{{ID: "me"}, {ID: "ana"}},
		Expenses: []Expense{{
			AmountCents:    1000,
			PayerID:        "me",
			ParticipantIDs: []string{"me", "ana"},
		}},
		Settlements: []Settlement{{
			FromMemberID: "ana",
			ToMemberID:   "me",
			AmountCents:  500,
		}},
	}

	balances := Balances(group)
	if balances["me"] != 0 || balances["ana"] != 0 {
		t.Fatalf("unexpected settled balances: %#v", balances)
	}
}

func TestBalancesSplitsBySalary(t *testing.T) {
	group := Group{
		Members:  []Member{{ID: "me", SalaryCents: 1000}, {ID: "ana", SalaryCents: 3000}},
		Expenses: []Expense{{AmountCents: 400, PayerID: "me", ParticipantIDs: []string{"me", "ana"}, SplitMode: "salary"}},
	}
	balances := Balances(group)
	if balances["me"] != 300 || balances["ana"] != -300 {
		t.Fatalf("expected 25/75 salary split, got %#v", balances)
	}
}

func TestValidatePaymentRequestDataRequiresPayerAndExactShare(t *testing.T) {
	group := Group{
		Members: []Member{
			{ID: "payer", UserID: "user-payer", Active: true, Accepted: true},
			{ID: "debtor", UserID: "user-debtor", Active: true, Accepted: true},
		},
		Expenses: []Expense{{
			ID:             "expense-1",
			AmountCents:    101,
			PayerID:        "payer",
			ParticipantIDs: []string{"payer", "debtor"},
			SplitMode:      "equal",
		}},
	}

	if err := ValidatePaymentRequestData(group, "user-payer", "expense-1", "debtor", 50); err != nil {
		t.Fatalf("payer's exact participant share was rejected: %v", err)
	}
	if err := ValidatePaymentRequestData(group, "user-debtor", "expense-1", "debtor", 50); err != ErrInvalid {
		t.Fatalf("debtor creating request error = %v, want ErrInvalid", err)
	}
	if err := ValidatePaymentRequestData(group, "user-payer", "expense-1", "debtor", 51); err != ErrInvalid {
		t.Fatalf("wrong amount error = %v, want ErrInvalid", err)
	}
}
