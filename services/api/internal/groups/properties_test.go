package groups

import (
	"fmt"
	"math"
	"math/rand"
	"os"
	"reflect"
	"strconv"
	"testing"
)

const (
	allocationPropertyIterations = 5000
	balancePropertyIterations    = 3000
)

type allocationPropertyCase struct {
	AmountCents int64
	Mode        string
	IDs         []string
	Salaries    []int64
}

func TestSplitProperties(t *testing.T) {
	seed := propertySeed(t, 14001)
	random := rand.New(rand.NewSource(seed))

	for iteration := 0; iteration < allocationPropertyIterations; iteration++ {
		input := generatedAllocationCase(random, iteration)
		if err := allocationPropertyFailure(input); err != nil {
			minimal := minimizeAllocationFailure(input, func(candidate allocationPropertyCase) bool {
				return allocationPropertyFailure(candidate) != nil
			})
			t.Fatalf("allocation property failed: seed=%d iteration=%d error=%v original=%+v minimal_case=%+v",
				seed, iteration, err, input, minimal)
		}
	}
}

func TestBalanceProperties(t *testing.T) {
	seed := propertySeed(t, 14002)
	random := rand.New(rand.NewSource(seed))

	for iteration := 0; iteration < balancePropertyIterations; iteration++ {
		group := generatedGroup(random, iteration)
		if err := balancePropertyFailure(group); err != nil {
			minimal := minimizeGroupFailure(group, func(candidate Group) bool {
				return balancePropertyFailure(candidate) != nil
			})
			t.Fatalf("balance property failed: seed=%d iteration=%d error=%v original=%+v minimal_case=%+v",
				seed, iteration, err, group, minimal)
		}
	}
}

func TestSalarySplitHandlesLargeValuesWithoutOverflow(t *testing.T) {
	group := Group{Members: []Member{
		{ID: "first", SalaryCents: math.MaxInt64},
		{ID: "second", SalaryCents: math.MaxInt64},
	}}
	shares, err := split(math.MaxInt64, []string{"first", "second"}, group, "salary")
	if err != nil {
		t.Fatalf("split large valid values: %v", err)
	}
	if shares["first"] != math.MaxInt64/2+1 || shares["second"] != math.MaxInt64/2 {
		t.Fatalf("large salary split = %+v, want deterministic one-centavo remainder", shares)
	}
}

func TestBalancesAllowsLargeIntermediateValuesWhenFinalBalancesFit(t *testing.T) {
	group := Group{
		Members: []Member{{ID: "payer"}, {ID: "participant"}},
		Expenses: []Expense{
			{AmountCents: math.MaxInt64, PayerID: "payer", ParticipantIDs: []string{"participant"}, SplitMode: "equal"},
			{AmountCents: math.MaxInt64, PayerID: "payer", ParticipantIDs: []string{"payer"}, SplitMode: "equal"},
		},
	}
	balances, err := calculateBalances(group)
	if err != nil {
		t.Fatalf("calculate large valid balances: %v", err)
	}
	if balances["payer"] != math.MaxInt64 || balances["participant"] != -math.MaxInt64 {
		t.Fatalf("large balances = %+v, want exact int64 limits", balances)
	}
}

func TestFinancialCalculationsRejectInvalidAndOverflowingInputs(t *testing.T) {
	validGroup := Group{Members: []Member{{ID: "a", SalaryCents: 1}, {ID: "b", SalaryCents: 2}}}
	tests := []struct {
		name   string
		amount int64
		ids    []string
		group  Group
		mode   string
	}{
		{name: "zero amount", amount: 0, ids: []string{"a"}, group: validGroup, mode: "equal"},
		{name: "negative amount", amount: -1, ids: []string{"a"}, group: validGroup, mode: "equal"},
		{name: "no participants", amount: 1, group: validGroup, mode: "equal"},
		{name: "duplicate participant", amount: 1, ids: []string{"a", "a"}, group: validGroup, mode: "equal"},
		{name: "unknown participant", amount: 1, ids: []string{"missing"}, group: validGroup, mode: "equal"},
		{name: "unknown mode", amount: 1, ids: []string{"a"}, group: validGroup, mode: "percentage"},
		{name: "missing salary", amount: 1, ids: []string{"a"}, group: Group{Members: []Member{{ID: "a"}}}, mode: "salary"},
		{name: "duplicate member", amount: 1, ids: []string{"a"}, group: Group{Members: []Member{{ID: "a"}, {ID: "a"}}}, mode: "equal"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if _, err := split(test.amount, test.ids, test.group, test.mode); err != ErrInvalid {
				t.Fatalf("split error = %v, want ErrInvalid", err)
			}
		})
	}

	overflowing := Group{
		Members: []Member{{ID: "payer"}, {ID: "participant"}},
		Expenses: []Expense{
			{AmountCents: math.MaxInt64, PayerID: "payer", ParticipantIDs: []string{"participant"}, SplitMode: "equal"},
			{AmountCents: 1, PayerID: "payer", ParticipantIDs: []string{"participant"}, SplitMode: "equal"},
		},
	}
	if _, err := calculateBalances(overflowing); err != ErrInvalid {
		t.Fatalf("overflowing balances error = %v, want ErrInvalid", err)
	}
	if balances := Balances(overflowing); len(balances) != 0 {
		t.Fatalf("public balance calculation must fail closed, got %+v", balances)
	}
}

func TestAllocationFailureMinimizer(t *testing.T) {
	input := allocationPropertyCase{
		AmountCents: 100,
		Mode:        "salary",
		IDs:         []string{"member-0", "member-1", "member-2"},
		Salaries:    []int64{100, 200, 300},
	}
	minimal := minimizeAllocationFailure(input, func(candidate allocationPropertyCase) bool {
		return candidate.AmountCents >= 10 && len(candidate.IDs) >= 2 && candidate.Salaries[0] >= 3
	})
	if minimal.AmountCents != 10 || len(minimal.IDs) != 2 || minimal.Salaries[0] != 3 {
		t.Fatalf("unexpected minimal case: %+v", minimal)
	}
}

func propertySeed(t *testing.T, fallback int64) int64 {
	t.Helper()
	raw := os.Getenv("VAQUITA_PROPERTY_SEED")
	if raw == "" {
		t.Logf("property seed: %d (override with VAQUITA_PROPERTY_SEED)", fallback)
		return fallback
	}
	seed, err := strconv.ParseInt(raw, 10, 64)
	if err != nil {
		t.Fatalf("parse VAQUITA_PROPERTY_SEED: %v", err)
	}
	t.Logf("property seed: %d (from VAQUITA_PROPERTY_SEED)", seed)
	return seed
}

func generatedAllocationCase(random *rand.Rand, iteration int) allocationPropertyCase {
	participantCount := random.Intn(12) + 1
	input := allocationPropertyCase{
		AmountCents: random.Int63n(1_000_000_000_000) + 1,
		Mode:        "equal",
		IDs:         make([]string, participantCount),
		Salaries:    make([]int64, participantCount),
	}
	if iteration%2 == 1 {
		input.Mode = "salary"
	}
	if iteration%19 == 0 {
		input.AmountCents = 1
	} else if iteration%17 == 0 {
		input.AmountCents = math.MaxInt64 - int64(random.Intn(100_000))
	}
	for index := range participantCount {
		input.IDs[index] = fmt.Sprintf("member-%d", index)
		input.Salaries[index] = random.Int63n(10_000_000_000) + 1
		if iteration%23 == 0 && index == 0 {
			input.Salaries[index] = math.MaxInt64
		}
	}
	return input
}

func allocationPropertyFailure(input allocationPropertyCase) error {
	group := groupForAllocation(input)
	shares, err := split(input.AmountCents, input.IDs, group, input.Mode)
	if err != nil {
		return fmt.Errorf("split valid input: %w", err)
	}
	if len(shares) != len(input.IDs) {
		return fmt.Errorf("share count = %d, want %d", len(shares), len(input.IDs))
	}

	var total int64
	minimum, maximum := int64(math.MaxInt64), int64(0)
	for _, id := range input.IDs {
		share, exists := shares[id]
		if !exists {
			return fmt.Errorf("missing share for %s", id)
		}
		if share < 0 {
			return fmt.Errorf("negative share for %s: %d", id, share)
		}
		total, err = addCentavos(total, share)
		if err != nil {
			return fmt.Errorf("sum shares: %w", err)
		}
		minimum = min(minimum, share)
		maximum = max(maximum, share)
	}
	if total != input.AmountCents {
		return fmt.Errorf("share total = %d, want %d", total, input.AmountCents)
	}
	if input.Mode == "equal" && maximum-minimum > 1 {
		return fmt.Errorf("equal split differs by more than one centavo: min=%d max=%d", minimum, maximum)
	}

	again, err := split(input.AmountCents, input.IDs, group, input.Mode)
	if err != nil {
		return fmt.Errorf("repeat split: %w", err)
	}
	if !reflect.DeepEqual(shares, again) {
		return fmt.Errorf("split is not deterministic: first=%+v second=%+v", shares, again)
	}
	return nil
}

func groupForAllocation(input allocationPropertyCase) Group {
	members := make([]Member, len(input.IDs))
	for index, id := range input.IDs {
		members[index] = Member{ID: id, SalaryCents: input.Salaries[index]}
	}
	return Group{Members: members}
}

func balancePropertyFailure(group Group) error {
	withoutSettlements := group
	withoutSettlements.Settlements = nil
	before, err := calculateBalances(withoutSettlements)
	if err != nil {
		return fmt.Errorf("calculate balances before settlements: %w", err)
	}
	if err := requireZeroSum(before); err != nil {
		return fmt.Errorf("before settlements: %w", err)
	}

	after, err := calculateBalances(group)
	if err != nil {
		return fmt.Errorf("calculate balances after settlements: %w", err)
	}
	if err := requireZeroSum(after); err != nil {
		return fmt.Errorf("after settlements: %w", err)
	}

	expected := copyBalances(before)
	for _, settlement := range group.Settlements {
		expected[settlement.FromMemberID] += settlement.AmountCents
		expected[settlement.ToMemberID] -= settlement.AmountCents
	}
	if !reflect.DeepEqual(after, expected) {
		return fmt.Errorf("settlement result = %+v, want %+v", after, expected)
	}
	if public := Balances(group); !reflect.DeepEqual(public, after) {
		return fmt.Errorf("public balance result = %+v, want %+v", public, after)
	}
	return nil
}

func generatedGroup(random *rand.Rand, iteration int) Group {
	memberCount := random.Intn(7) + 2
	group := Group{Members: make([]Member, memberCount)}
	for index := range memberCount {
		salary := random.Int63n(10_000_000_000) + 1
		if iteration%29 == 0 && index == 0 {
			salary = math.MaxInt64
		}
		group.Members[index] = Member{ID: fmt.Sprintf("member-%d", index), SalaryCents: salary}
	}

	expenseCount := random.Intn(20) + 1
	for range expenseCount {
		participantCount := random.Intn(memberCount) + 1
		permutation := random.Perm(memberCount)
		participantIDs := make([]string, participantCount)
		for index, memberIndex := range permutation[:participantCount] {
			participantIDs[index] = group.Members[memberIndex].ID
		}
		mode := "equal"
		if random.Intn(2) == 1 {
			mode = "salary"
		}
		group.Expenses = append(group.Expenses, Expense{
			AmountCents:    random.Int63n(1_000_000_000) + 1,
			PayerID:        group.Members[random.Intn(memberCount)].ID,
			ParticipantIDs: participantIDs,
			SplitMode:      mode,
		})
	}

	settlementCount := random.Intn(20)
	for range settlementCount {
		from := random.Intn(memberCount)
		to := random.Intn(memberCount - 1)
		if to >= from {
			to++
		}
		group.Settlements = append(group.Settlements, Settlement{
			FromMemberID: group.Members[from].ID,
			ToMemberID:   group.Members[to].ID,
			AmountCents:  random.Int63n(1_000_000) + 1,
		})
	}
	return group
}

func requireZeroSum(balances map[string]int64) error {
	var total int64
	for _, balance := range balances {
		var err error
		total, err = addCentavos(total, balance)
		if err != nil {
			return fmt.Errorf("sum balances: %w", err)
		}
	}
	if total != 0 {
		return fmt.Errorf("balance total = %d, want 0", total)
	}
	return nil
}

func copyBalances(source map[string]int64) map[string]int64 {
	copy := make(map[string]int64, len(source))
	for id, balance := range source {
		copy[id] = balance
	}
	return copy
}

func minimizeAllocationFailure(input allocationPropertyCase, fails func(allocationPropertyCase) bool) allocationPropertyCase {
	minimal := cloneAllocationCase(input)
	for len(minimal.IDs) > 1 {
		candidate := cloneAllocationCase(minimal)
		candidate.IDs = candidate.IDs[:len(candidate.IDs)-1]
		candidate.Salaries = candidate.Salaries[:len(candidate.Salaries)-1]
		if !fails(candidate) {
			break
		}
		minimal = candidate
	}

	minimal.AmountCents = minimizePositiveInt64(minimal.AmountCents, func(value int64) bool {
		candidate := cloneAllocationCase(minimal)
		candidate.AmountCents = value
		return fails(candidate)
	})
	for index := range minimal.Salaries {
		minimal.Salaries[index] = minimizePositiveInt64(minimal.Salaries[index], func(value int64) bool {
			candidate := cloneAllocationCase(minimal)
			candidate.Salaries[index] = value
			return fails(candidate)
		})
	}
	return minimal
}

func minimizeGroupFailure(input Group, fails func(Group) bool) Group {
	minimal := cloneGroup(input)
	for len(minimal.Settlements) > 0 {
		candidate := cloneGroup(minimal)
		candidate.Settlements = candidate.Settlements[:len(candidate.Settlements)-1]
		if !fails(candidate) {
			break
		}
		minimal = candidate
	}
	for len(minimal.Expenses) > 0 {
		candidate := cloneGroup(minimal)
		candidate.Expenses = candidate.Expenses[:len(candidate.Expenses)-1]
		if !fails(candidate) {
			break
		}
		minimal = candidate
	}
	return minimal
}

func minimizePositiveInt64(value int64, fails func(int64) bool) int64 {
	low, high := int64(1), value
	for low < high {
		middle := low + (high-low)/2
		if fails(middle) {
			high = middle
		} else {
			low = middle + 1
		}
	}
	return low
}

func cloneAllocationCase(input allocationPropertyCase) allocationPropertyCase {
	clone := input
	clone.IDs = append([]string(nil), input.IDs...)
	clone.Salaries = append([]int64(nil), input.Salaries...)
	return clone
}

func cloneGroup(input Group) Group {
	clone := input
	clone.Members = append([]Member(nil), input.Members...)
	clone.Expenses = append([]Expense(nil), input.Expenses...)
	clone.Settlements = append([]Settlement(nil), input.Settlements...)
	return clone
}
