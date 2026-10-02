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

func TestValidatePaymentRequestDataRequiresExactCreditorDebtorRelation(t *testing.T) {
	group := Group{
		Members: []Member{
			{ID: "ana", UserID: "user-ana", Active: true, Accepted: true},
			{ID: "diego", UserID: "user-diego", Active: true, Accepted: true},
			{ID: "sofia", UserID: "user-sofia", Active: true, Accepted: true},
		},
		Expenses: []Expense{
			{AmountCents: 300, PayerID: "ana", ParticipantIDs: []string{"ana", "diego", "sofia"}},
			{AmountCents: 300, PayerID: "diego", ParticipantIDs: []string{"ana", "diego", "sofia"}},
		},
	}

	// Diego is the creditor for 100 centavos even though he did not pay every
	// expense in the group; Sofia's net debt is routed to him deterministically.
	if err := ValidatePaymentRequestData(group, "user-diego", "sofia", 100); err != nil {
		t.Fatalf("creditor's pairwise request was rejected: %v", err)
	}
	if err := ValidatePaymentRequestData(group, "user-ana", "diego", 100); err != ErrInvalid {
		t.Fatalf("unrelated creditor request error = %v, want ErrInvalid", err)
	}
	if err := ValidatePaymentRequestData(group, "user-diego", "sofia", 99); err != ErrInvalid {
		t.Fatalf("wrong amount error = %v, want ErrInvalid", err)
	}
}

func TestPaymentRelationsAllocateEveryCentDeterministically(t *testing.T) {
	group := Group{
		Members:  []Member{{ID: "ana", Active: true, Accepted: true}, {ID: "diego", Active: true, Accepted: true}, {ID: "sofia", Active: true, Accepted: true}},
		Expenses: []Expense{{AmountCents: 100, PayerID: "ana", ParticipantIDs: []string{"ana", "diego", "sofia"}}},
	}
	relations := PaymentRelations(group)
	if len(relations) != 2 || relations[0] != (PaymentRelation{FromMemberID: "diego", ToMemberID: "ana", AmountCents: 33}) || relations[1] != (PaymentRelation{FromMemberID: "sofia", ToMemberID: "ana", AmountCents: 33}) {
		t.Fatalf("relations = %#v", relations)
	}
}
