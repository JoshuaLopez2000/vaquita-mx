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
