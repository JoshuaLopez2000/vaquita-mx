package groups

import (
	"math"
	"math/big"
	"math/rand"
	"reflect"
	"testing"
)

func TestAllocateByPercentageTable(t *testing.T) {
	tests := []struct {
		name        string
		total       int64
		ids         []string
		percentages map[string]int
		want        map[string]int64
	}{
		{
			name:        "50/30/20 exact split",
			total:       10000,
			ids:         []string{"ana", "beto", "carla"},
			percentages: map[string]int{"ana": 5000, "beto": 3000, "carla": 2000},
			want:        map[string]int64{"ana": 5000, "beto": 3000, "carla": 2000},
		},
		{
			name:        "repeating third favors largest percentage regardless of position",
			total:       100,
			ids:         []string{"ana", "beto", "carla"},
			percentages: map[string]int{"ana": 3333, "beto": 3333, "carla": 3334},
			want:        map[string]int64{"ana": 33, "beto": 33, "carla": 34},
		},
		{
			name:        "repeating third on 1000 cents distributes two remainders deterministically",
			total:       1000,
			ids:         []string{"ana", "beto", "carla"},
			percentages: map[string]int{"ana": 3334, "beto": 3333, "carla": 3333},
			want:        map[string]int64{"ana": 334, "beto": 333, "carla": 333},
		},
		{
			name:        "one-cent total goes to largest percentage",
			total:       1,
			ids:         []string{"ana", "beto"},
			percentages: map[string]int{"ana": 1000, "beto": 9000},
			want:        map[string]int64{"ana": 0, "beto": 1},
		},
		{
			name:        "one-cent total tie breaks by participant order",
			total:       1,
			ids:         []string{"ana", "beto"},
			percentages: map[string]int{"ana": 5000, "beto": 5000},
			want:        map[string]int64{"ana": 1, "beto": 0},
		},
		{
			name:        "one-cent total reversed participant order flips tie winner",
			total:       1,
			ids:         []string{"beto", "ana"},
			percentages: map[string]int{"ana": 5000, "beto": 5000},
			want:        map[string]int64{"beto": 1, "ana": 0},
		},
		{
			name:        "four-way tie breaks in stored participant order",
			total:       5,
			ids:         []string{"d", "b", "a", "c"},
			percentages: map[string]int{"d": 2500, "b": 2500, "a": 2500, "c": 2500},
			want:        map[string]int64{"d": 2, "b": 1, "a": 1, "c": 1},
		},
		{
			name:        "single participant receives full total",
			total:       1,
			ids:         []string{"ana"},
			percentages: map[string]int{"ana": 10000},
			want:        map[string]int64{"ana": 1},
		},
		{
			name:        "large max int64 total allocates without overflow",
			total:       math.MaxInt64,
			ids:         []string{"ana", "beto"},
			percentages: map[string]int{"ana": 5000, "beto": 5000},
			want:        map[string]int64{"ana": math.MaxInt64/2 + 1, "beto": math.MaxInt64 / 2},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got, err := allocateByPercentage(test.total, test.ids, test.percentages)
			if err != nil {
				t.Fatalf("allocateByPercentage returned unexpected error: %v", err)
			}
			if !reflect.DeepEqual(got, test.want) {
				t.Fatalf("allocateByPercentage = %#v, want %#v", got, test.want)
			}
		})
	}
}

func TestValidatePercentagesRejectsInvalidInputs(t *testing.T) {
	ids := []string{"ana", "beto"}
	invalid := []struct {
		name        string
		ids         []string
		percentages []ExpensePercentage
	}{
		{
			name:        "sum below 100 percent",
			ids:         ids,
			percentages: []ExpensePercentage{{MemberID: "ana", PercentageBps: 5000}, {MemberID: "beto", PercentageBps: 4999}},
		},
		{
			name:        "sum above 100 percent",
			ids:         ids,
			percentages: []ExpensePercentage{{MemberID: "ana", PercentageBps: 5001}, {MemberID: "beto", PercentageBps: 5000}},
		},
		{
			name:        "zero percentage rejected",
			ids:         ids,
			percentages: []ExpensePercentage{{MemberID: "ana", PercentageBps: 10000}, {MemberID: "beto", PercentageBps: 0}},
		},
		{
			name:        "negative percentage rejected",
			ids:         ids,
			percentages: []ExpensePercentage{{MemberID: "ana", PercentageBps: 10100}, {MemberID: "beto", PercentageBps: -100}},
		},
		{
			name:        "duplicate member rejected",
			ids:         ids,
			percentages: []ExpensePercentage{{MemberID: "ana", PercentageBps: 5000}, {MemberID: "ana", PercentageBps: 5000}},
		},
		{
			name:        "missing participant rejected",
			ids:         ids,
			percentages: []ExpensePercentage{{MemberID: "ana", PercentageBps: 10000}},
		},
		{
			name:        "unknown participant rejected",
			ids:         ids,
			percentages: []ExpensePercentage{{MemberID: "ana", PercentageBps: 5000}, {MemberID: "carla", PercentageBps: 5000}},
		},
		{
			name:        "empty participants rejected",
			ids:         nil,
			percentages: nil,
		},
	}

	for _, test := range invalid {
		t.Run(test.name, func(t *testing.T) {
			if _, err := validatePercentages(test.percentages, test.ids); err != ErrInvalid {
				t.Fatalf("validatePercentages error = %v, want ErrInvalid", err)
			}
		})
	}
}

func TestPrepareExpenseComputesAndValidatesPercentageShares(t *testing.T) {
	group := Group{
		Members: []Member{
			{ID: "ana", Active: true, Accepted: true},
			{ID: "beto", Active: true, Accepted: true},
			{ID: "carla", Active: true, Accepted: true},
		},
	}

	splitTip := true
	input := AddExpenseInput{
		Description:      "Cena",
		AmountCents:      1000,
		Payers:           []ExpensePayer{{MemberID: "ana", AmountCents: 1100}},
		ParticipantIDs:   []string{"ana", "beto", "carla"},
		SplitMode:        "percentage",
		SplitOverpayment: &splitTip,
		Percentages: []ExpensePercentage{
			{MemberID: "ana", PercentageBps: 5000},
			{MemberID: "beto", PercentageBps: 3000},
			{MemberID: "carla", PercentageBps: 2000},
		},
	}
	if err := prepareExpense(group, &input); err != nil {
		t.Fatalf("prepareExpense failed: %v", err)
	}
	want := []ExpenseShare{
		{MemberID: "ana", AmountCents: 550},
		{MemberID: "beto", AmountCents: 330},
		{MemberID: "carla", AmountCents: 220},
	}
	if !reflect.DeepEqual(input.Shares, want) {
		t.Fatalf("prepared percentage shares = %#v, want %#v", input.Shares, want)
	}

	// Rejects client-supplied shares on a percentage expense.
	badMixed := AddExpenseInput{
		Description:    "Bad",
		AmountCents:    1000,
		PayerID:        "ana",
		ParticipantIDs: []string{"ana", "beto"},
		SplitMode:      "percentage",
		Shares:         []ExpenseShare{{MemberID: "ana", AmountCents: 500}, {MemberID: "beto", AmountCents: 500}},
		Percentages:    []ExpensePercentage{{MemberID: "ana", PercentageBps: 5000}, {MemberID: "beto", PercentageBps: 5000}},
	}
	if err := prepareExpense(group, &badMixed); err != ErrInvalid {
		t.Fatalf("mixed shares+percentages error = %v, want ErrInvalid", err)
	}

	// Rejects percentages supplied on an equal expense.
	badEqual := AddExpenseInput{
		Description:    "Bad",
		AmountCents:    1000,
		PayerID:        "ana",
		ParticipantIDs: []string{"ana", "beto"},
		SplitMode:      "equal",
		Percentages:    []ExpensePercentage{{MemberID: "ana", PercentageBps: 5000}, {MemberID: "beto", PercentageBps: 5000}},
	}
	if err := prepareExpense(group, &badEqual); err != ErrInvalid {
		t.Fatalf("percentages on equal mode error = %v, want ErrInvalid", err)
	}
}

func TestPercentageOverpaymentKeepsSharesMonotonic(t *testing.T) {
	// Weights 44% / 44% / 12% exhibit the Hamilton Alabama paradox between
	// total=3 (1,1,1) and total=4 (2,2,0). Allocating consumption and
	// overpayment separately keeps every member's overpayment non-negative.
	ids := []string{"a", "b", "c"}
	percentages := map[string]int{"a": 4400, "b": 4400, "c": 1200}

	consumption, err := allocateByPercentage(3, ids, percentages)
	if err != nil {
		t.Fatalf("consumption allocation failed: %v", err)
	}
	finalShares, err := computePercentageFinalShares(3, 4, true, ids, percentages)
	if err != nil {
		t.Fatalf("final share computation failed: %v", err)
	}
	var sum int64
	for _, share := range finalShares {
		if share.AmountCents < consumption[share.MemberID] {
			t.Fatalf("final share %d < consumption %d for %s", share.AmountCents, consumption[share.MemberID], share.MemberID)
		}
		sum += share.AmountCents
	}
	if sum != 4 {
		t.Fatalf("final shares sum = %d, want 4", sum)
	}
}

func TestBalancesUseStoredFinalPercentageShares(t *testing.T) {
	// Stored ExplicitShares drive ledger balances directly even if
	// Percentages is omitted on the loaded ledger model.
	group := Group{
		Members: []Member{
			{ID: "ana", Active: true, Accepted: true},
			{ID: "beto", Active: true, Accepted: true},
			{ID: "carla", Active: true, Accepted: true},
		},
		Expenses: []Expense{{
			ID:               "exp-1",
			AmountCents:      1000,
			PayerID:          "ana",
			Payers:           []ExpensePayer{{MemberID: "ana", AmountCents: 1000}},
			ParticipantIDs:   []string{"ana", "beto", "carla"},
			SplitMode:        "percentage",
			SplitOverpayment: true,
			ExplicitShares: []ExpenseShare{
				{MemberID: "ana", AmountCents: 334},
				{MemberID: "beto", AmountCents: 333},
				{MemberID: "carla", AmountCents: 333},
			},
		}},
	}
	balances := Balances(group)
	if balances["ana"] != 666 || balances["beto"] != -333 || balances["carla"] != -333 {
		t.Fatalf("percentage balances = %#v, want ana=666 beto=-333 carla=-333", balances)
	}
}

func TestPercentageAllocationProperties(t *testing.T) {
	seed := propertySeed(t, 19001)
	random := rand.New(rand.NewSource(seed))
	denom := big.NewInt(PercentageBasisPointsTotal)

	for iteration := 0; iteration < allocationPropertyIterations; iteration++ {
		count := 1 + random.Intn(8)
		ids := make([]string, count)
		percentages := make(map[string]int, count)
		remaining := PercentageBasisPointsTotal
		for i := 0; i < count; i++ {
			ids[i] = memberIDForTest(i)
			if i == count-1 {
				percentages[ids[i]] = remaining
			} else {
				maxBps := remaining - (count - 1 - i)
				bps := 1
				if maxBps > 1 {
					bps = 1 + random.Intn(maxBps)
				}
				percentages[ids[i]] = bps
				remaining -= bps
			}
		}
		var total int64
		switch iteration % 5 {
		case 0:
			total = 1
		case 1:
			total = int64(1 + random.Intn(50))
		case 2:
			total = int64(1 + random.Intn(1000000))
		case 3:
			total = math.MaxInt64 - int64(random.Intn(1000))
		default:
			total = 1 + random.Int63n(10_000_000_00)
		}

		shares, err := allocateByPercentage(total, ids, percentages)
		if err != nil {
			t.Fatalf("seed=%d iteration=%d unexpected error: %v", seed, iteration, err)
		}
		repeat, err := allocateByPercentage(total, ids, percentages)
		if err != nil || !reflect.DeepEqual(shares, repeat) {
			t.Fatalf("seed=%d iteration=%d non-deterministic allocation: %v vs %v", seed, iteration, shares, repeat)
		}

		sum := new(big.Int)
		totalBig := big.NewInt(total)
		for _, id := range ids {
			share := shares[id]
			if share < 0 {
				t.Fatalf("seed=%d iteration=%d negative share %d", seed, iteration, share)
			}
			product := new(big.Int).Mul(totalBig, big.NewInt(int64(percentages[id])))
			floor, rem := new(big.Int).QuoRem(product, denom, new(big.Int))
			ceil := new(big.Int).Set(floor)
			if rem.Sign() > 0 {
				ceil.Add(ceil, big.NewInt(1))
			}
			shareBig := big.NewInt(share)
			if shareBig.Cmp(floor) < 0 || shareBig.Cmp(ceil) > 0 {
				t.Fatalf("seed=%d iteration=%d share %d outside [%s, %s]", seed, iteration, share, floor, ceil)
			}
			sum.Add(sum, shareBig)
		}
		if sum.Cmp(totalBig) != 0 {
			t.Fatalf("seed=%d iteration=%d sum=%s want=%s", seed, iteration, sum, totalBig)
		}
	}
}

func memberIDForTest(index int) string {
	return "m" + string(rune('a'+index))
}
