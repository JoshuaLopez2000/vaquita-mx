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

func TestBalancesCreditsMultiplePayersExactly(t *testing.T) {
	group := Group{Members: []Member{{ID: "ana"}, {ID: "diego"}, {ID: "sofia"}}, Expenses: []Expense{{
		AmountCents: 101, PayerID: "ana", Payers: []ExpensePayer{{MemberID: "ana", AmountCents: 51}, {MemberID: "diego", AmountCents: 50}},
		ParticipantIDs: []string{"ana", "diego", "sofia"},
	}}}
	balances := Balances(group)
	if balances["ana"] != 17 || balances["diego"] != 16 || balances["sofia"] != -33 {
		t.Fatalf("multiple payer balances = %#v", balances)
	}
}

func TestBalancesKeepsExactSharesSeparateFromMultiplePayers(t *testing.T) {
	group := Group{Members: []Member{{ID: "ana"}, {ID: "diego"}}, Expenses: []Expense{{
		AmountCents: 100,
		PayerID:     "ana",
		Payers: []ExpensePayer{
			{MemberID: "ana", AmountCents: 70},
			{MemberID: "diego", AmountCents: 30},
		},
		ParticipantIDs: []string{"ana", "diego"},
		SplitMode:      "exact",
		ExplicitShares: []ExpenseShare{
			{MemberID: "ana", AmountCents: 10},
			{MemberID: "diego", AmountCents: 90},
		},
	}}}

	balances := Balances(group)
	if balances["ana"] != 60 || balances["diego"] != -60 {
		t.Fatalf("exact shares with multiple payers = %#v", balances)
	}
}

func TestExactSharesRequireEachParticipantAndEveryCentavo(t *testing.T) {
	ids := []string{"ana", "diego"}
	for _, shares := range [][]ExpenseShare{
		{{MemberID: "ana", AmountCents: 100}},
		{{MemberID: "ana", AmountCents: 50}, {MemberID: "ana", AmountCents: 50}},
		{{MemberID: "ana", AmountCents: 50}, {MemberID: "diego", AmountCents: 49}},
		{{MemberID: "ana", AmountCents: 50}, {MemberID: "diego", AmountCents: 51}},
		{{MemberID: "ana", AmountCents: -1}, {MemberID: "diego", AmountCents: 101}},
	} {
		if _, err := validateExactShares(shares, ids, 100); err != ErrInvalid {
			t.Fatalf("shares %#v error = %v, want ErrInvalid", shares, err)
		}
	}
	shares, err := validateExactShares([]ExpenseShare{{MemberID: "ana", AmountCents: 1}, {MemberID: "diego", AmountCents: 99}}, ids, 100)
	if err != nil || shares["ana"] != 1 || shares["diego"] != 99 {
		t.Fatalf("valid one-cent exact shares = %#v, %v", shares, err)
	}
}

func TestBalancesAllocateOverpaymentAcrossParticipants(t *testing.T) {
	group := Group{Members: []Member{{ID: "ana", Active: true, Accepted: true}, {ID: "diego", Active: true, Accepted: true}}, Expenses: []Expense{{
		AmountCents: 100, PayerID: "ana", Payers: []ExpensePayer{{MemberID: "ana", AmountCents: 80}, {MemberID: "diego", AmountCents: 40}},
		ParticipantIDs:   []string{"ana", "diego"},
		SplitOverpayment: true,
	}}}
	balances := Balances(group)
	if balances["ana"] != 20 || balances["diego"] != -20 {
		t.Fatalf("overpayment balances = %#v", balances)
	}
	relations := PaymentRelations(group)
	if len(relations) != 1 || relations[0] != (PaymentRelation{FromMemberID: "diego", ToMemberID: "ana", AmountCents: 20}) {
		t.Fatalf("overpayment relations = %#v", relations)
	}
}

func TestBalancesKeepUnsplitOverpaymentOutOfDebts(t *testing.T) {
	group := Group{Members: []Member{{ID: "ana", Active: true, Accepted: true}, {ID: "diego", Active: true, Accepted: true}}, Expenses: []Expense{{
		AmountCents: 400,
		PayerID:     "ana",
		Payers: []ExpensePayer{
			{MemberID: "ana", AmountCents: 300},
			{MemberID: "diego", AmountCents: 150},
		},
		ParticipantIDs: []string{"ana", "diego"},
		SplitMode:      "exact",
		ExplicitShares: []ExpenseShare{
			{MemberID: "ana", AmountCents: 100},
			{MemberID: "diego", AmountCents: 300},
		},
		SplitOverpayment: false,
	}}}

	balances := Balances(group)
	if balances["ana"] != 167 || balances["diego"] != -167 {
		t.Fatalf("unsplit overpayment balances = %#v", balances)
	}
	relations := PaymentRelations(group)
	if len(relations) != 1 || relations[0] != (PaymentRelation{FromMemberID: "diego", ToMemberID: "ana", AmountCents: 167}) {
		t.Fatalf("unsplit overpayment relations = %#v", relations)
	}
	credited, err := ledgerPayers(group.Expenses[0], nil)
	if err != nil || credited[0].AmountCents != 267 || credited[1].AmountCents != 133 {
		t.Fatalf("credited payer amounts = %#v, %v", credited, err)
	}
}

func TestBalancesKeepUnsplitOverpaymentOutOfEqualSplit(t *testing.T) {
	group := Group{Members: []Member{{ID: "ana", Active: true, Accepted: true}, {ID: "diego", Active: true, Accepted: true}}, Expenses: []Expense{{
		AmountCents:      400,
		PayerID:          "ana",
		Payers:           []ExpensePayer{{MemberID: "ana", AmountCents: 550}},
		ParticipantIDs:   []string{"ana", "diego"},
		SplitOverpayment: false,
	}}}

	balances := Balances(group)
	if balances["ana"] != 200 || balances["diego"] != -200 {
		t.Fatalf("unsplit equal balances = %#v", balances)
	}
	relations := PaymentRelations(group)
	if len(relations) != 1 || relations[0] != (PaymentRelation{FromMemberID: "diego", ToMemberID: "ana", AmountCents: 200}) {
		t.Fatalf("unsplit equal relations = %#v", relations)
	}
}

func TestBalancesRejectsInvalidMultiplePayers(t *testing.T) {
	group := Group{Members: []Member{{ID: "ana"}, {ID: "diego"}}, Expenses: []Expense{{
		AmountCents: 100, Payers: []ExpensePayer{{MemberID: "ana", AmountCents: 99}}, ParticipantIDs: []string{"ana", "diego"},
	}}}
	if balances := Balances(group); len(balances) != 0 {
		t.Fatalf("invalid expense accepted: %#v", balances)
	}
}

func TestBalancesRejectsDuplicatePayers(t *testing.T) {
	group := Group{Members: []Member{{ID: "ana"}, {ID: "diego"}}, Expenses: []Expense{{
		AmountCents: 100, Payers: []ExpensePayer{{MemberID: "ana", AmountCents: 50}, {MemberID: "ana", AmountCents: 50}}, ParticipantIDs: []string{"ana", "diego"},
	}}}
	if balances := Balances(group); len(balances) != 0 {
		t.Fatalf("duplicate payers accepted: %#v", balances)
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

func TestPaymentRelationsKeepOtherMembersDebtAfterDirectSettlement(t *testing.T) {
	group := Group{
		Members: []Member{
			{ID: "ana", Active: true, Accepted: true},
			{ID: "diego", Active: true, Accepted: true},
			{ID: "marco", Active: true, Accepted: true},
		},
		Expenses: []Expense{
			{AmountCents: 1332, PayerID: "ana", ParticipantIDs: []string{"ana", "marco"}},
			{AmountCents: 100000, PayerID: "ana", ParticipantIDs: []string{"ana", "diego"}},
		},
		Settlements: []Settlement{{FromMemberID: "diego", ToMemberID: "ana", AmountCents: 50000}},
	}
	relations := PaymentRelations(group)
	if len(relations) != 1 || relations[0] != (PaymentRelation{FromMemberID: "marco", ToMemberID: "ana", AmountCents: 666}) {
		t.Fatalf("relations after Diego pays Ana = %#v", relations)
	}
}

func TestContactStatusesUseOnlyPairwiseBalances(t *testing.T) {
	statuses := ContactStatuses([]Group{{
		Members: []Member{
			{ID: "me", UserID: "user-me", Active: true, Accepted: true},
			{ID: "ana", UserID: "user-ana", Name: "Ana", Active: true, Accepted: true},
			{ID: "diego", UserID: "user-diego", Name: "Diego", Active: true, Accepted: true},
		},
		PaymentRelations: []PaymentRelation{
			{FromMemberID: "me", ToMemberID: "ana", AmountCents: 250},
			{FromMemberID: "diego", ToMemberID: "ana", AmountCents: 9999},
		},
	}}, "user-me")
	if len(statuses) != 1 || statuses[0].Member.ID != "ana" || statuses[0].AmountCents != 250 {
		t.Fatalf("statuses = %#v, want only the 250-centavo balance with Ana", statuses)
	}
}
