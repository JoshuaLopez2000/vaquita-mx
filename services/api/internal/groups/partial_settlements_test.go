package groups

import "testing"

func partialSettlementLedger(expenseCents int64, payments []int64) (map[string]int64, []PaymentRelation, bool) {
	group := Group{
		Members: []Member{
			{ID: "ana", Active: true, Accepted: true},
			{ID: "diego", Active: true, Accepted: true},
		},
		Expenses: []Expense{{AmountCents: expenseCents, PayerID: "ana", ParticipantIDs: []string{"ana", "diego"}}},
	}
	for _, amount := range payments {
		group.Settlements = append(group.Settlements, Settlement{FromMemberID: "diego", ToMemberID: "ana", AmountCents: amount})
	}
	balances := Balances(group)
	return balances, PaymentRelations(group), len(balances) != 0
}

// A 99-centavo expense splits exactly (50 / 49) with the spare centavo going
// to the first participant, so Diego uniformly owes 49. Repeated irregular
// partial payments, including a final one-centavo remainder, must land the
// ledger deterministically on zero.
func TestPartialSettlementsReduceBalancesToZero(t *testing.T) {
	balances, relations, ok := partialSettlementLedger(99, nil)
	if !ok {
		t.Fatalf("ledger rejected the expense: %#v", balances)
	}
	if len(relations) != 1 || relations[0] != (PaymentRelation{FromMemberID: "diego", ToMemberID: "ana", AmountCents: 49}) {
		t.Fatalf("initial relations = %#v, want a 49-centavo obligation to Ana", relations)
	}
	for _, payments := range [][]int64{
		{40, 8, 1},
		{1, 1, 1, 10, 30, 6},
		{49},
	} {
		balances, relations, ok := partialSettlementLedger(99, payments)
		if !ok {
			t.Fatalf("ledger rejected payments %#v: balances=%#v", payments, balances)
		}
		if len(relations) != 0 || balances["ana"] != 0 || balances["diego"] != 0 {
			t.Fatalf("payments %#v settled to balances=%#v relations=%#v, want zero", payments, balances, relations)
		}
	}
}

// After every recorded partial payment the derived relation must show exactly
// the remaining obligation, so the next payment can never overpay.
func TestPartialSettlementsLeaveExactRemainingObligations(t *testing.T) {
	payments := []int64{20, 25, 3, 1}
	var settled int64
	for index, amount := range payments {
		settled += amount
		want := int64(49) - settled
		balances, relations, ok := partialSettlementLedger(99, payments[:index+1])
		if !ok {
			t.Fatalf("ledger rejected payments %#v: balances=%#v", payments[:index+1], balances)
		}
		if want > 0 {
			if len(relations) != 1 || relations[0].AmountCents != want {
				t.Fatalf("after %d centavos relations = %#v, want %d", settled, relations, want)
			}
		} else if len(relations) != 0 {
			t.Fatalf("after %d centavos relations = %#v, want none", settled, relations)
		}
		if balances["ana"] != want || balances["diego"] != -want {
			t.Fatalf("after %d centavos balances = %#v, want +/-%d", settled, balances, want)
		}
	}
}
