package groups

import (
	"math"
	"math/big"
)

func Balances(g Group) map[string]int64 {
	b, err := calculateBalances(g)
	if err != nil {
		return map[string]int64{}
	}
	return b
}

// PaymentRelations is the bilateral debt projection. Expenses create direct
// participant-to-payer obligations; settlements reduce only the recorded
// payer/debtor pair. Unlike a global netting plan, a payment by one member
// cannot reroute or erase another member's debt.
func PaymentRelations(g Group) []PaymentRelation {
	relations, err := bilateralRelations(g)
	if err != nil {
		return []PaymentRelation{}
	}
	return relations
}

func bilateralRelations(g Group) ([]PaymentRelation, error) {
	members := map[string]Member{}
	for _, member := range g.Members {
		if member.ID == "" {
			return nil, ErrInvalid
		}
		if _, exists := members[member.ID]; exists {
			return nil, ErrInvalid
		}
		members[member.ID] = member
	}
	type edge struct{ from, to string }
	edges := map[edge]*big.Int{}
	add := func(from, to string, amount int64) error {
		if from == to || amount == 0 {
			return nil
		}
		if _, exists := members[from]; !exists {
			return ErrInvalid
		}
		if _, exists := members[to]; !exists {
			return ErrInvalid
		}
		key := edge{from, to}
		if edges[key] == nil {
			edges[key] = new(big.Int)
		}
		edges[key].Add(edges[key], big.NewInt(amount))
		return nil
	}
	for _, expense := range g.Expenses {
		if expense.AmountCents <= 0 {
			return nil, ErrInvalid
		}
		if _, err := ledgerPayers(expense, nil); err != nil {
			return nil, err
		}
		allocatedAmount, err := expenseAllocatedAmount(expense)
		if err != nil {
			return nil, err
		}
		shares, err := sharesForExpense(expense, g, allocatedAmount)
		if err != nil {
			return nil, err
		}
		obligations, err := expenseObligations(expense, shares)
		if err != nil {
			return nil, err
		}
		for _, obligation := range obligations {
			if err := add(obligation.from, obligation.to, obligation.amount); err != nil {
				return nil, err
			}
		}
	}
	for _, settlement := range g.Settlements {
		if settlement.AmountCents <= 0 {
			return nil, ErrInvalid
		}
		if err := add(settlement.FromMemberID, settlement.ToMemberID, -settlement.AmountCents); err != nil {
			return nil, err
		}
	}
	relations := []PaymentRelation{}
	for fromIndex, from := range g.Members {
		if !from.Active || !from.Accepted {
			continue
		}
		for _, to := range g.Members[fromIndex+1:] {
			if !to.Active || !to.Accepted {
				continue
			}
			amount := new(big.Int)
			if forward := edges[edge{from.ID, to.ID}]; forward != nil {
				amount.Set(forward)
			}
			if reverse := edges[edge{to.ID, from.ID}]; reverse != nil {
				amount.Sub(amount, reverse)
			}
			if amount.Sign() == 0 {
				continue
			}
			if !amount.IsInt64() {
				return nil, ErrInvalid
			}
			if amount.Sign() > 0 {
				relations = append(relations, PaymentRelation{FromMemberID: from.ID, ToMemberID: to.ID, AmountCents: amount.Int64()})
			} else {
				amount.Neg(amount)
				if !amount.IsInt64() {
					return nil, ErrInvalid
				}
				relations = append(relations, PaymentRelation{FromMemberID: to.ID, ToMemberID: from.ID, AmountCents: amount.Int64()})
			}
		}
	}
	return relations, nil
}

func calculateBalances(g Group) (map[string]int64, error) {
	exact := map[string]*big.Int{}
	for _, m := range g.Members {
		if m.ID == "" {
			return nil, ErrInvalid
		}
		if _, exists := exact[m.ID]; exists {
			return nil, ErrInvalid
		}
		exact[m.ID] = new(big.Int)
	}
	for _, e := range g.Expenses {
		if e.AmountCents <= 0 {
			return nil, ErrInvalid
		}
		credited, err := ledgerPayers(e, nil)
		if err != nil {
			return nil, err
		}
		for _, payer := range credited {
			if _, exists := exact[payer.MemberID]; !exists || payer.AmountCents <= 0 {
				return nil, ErrInvalid
			}
			exact[payer.MemberID].Add(exact[payer.MemberID], big.NewInt(payer.AmountCents))
		}
		allocatedAmount, err := expenseAllocatedAmount(e)
		if err != nil {
			return nil, err
		}
		shares, err := sharesForExpense(e, g, allocatedAmount)
		if err != nil {
			return nil, err
		}
		for id, v := range shares {
			exact[id].Sub(exact[id], big.NewInt(v))
		}
	}
	for _, s := range g.Settlements {
		if s.AmountCents <= 0 || s.FromMemberID == s.ToMemberID {
			return nil, ErrInvalid
		}
		if _, exists := exact[s.FromMemberID]; !exists {
			return nil, ErrInvalid
		}
		if _, exists := exact[s.ToMemberID]; !exists {
			return nil, ErrInvalid
		}
		exact[s.FromMemberID].Add(exact[s.FromMemberID], big.NewInt(s.AmountCents))
		exact[s.ToMemberID].Sub(exact[s.ToMemberID], big.NewInt(s.AmountCents))
	}

	b := make(map[string]int64, len(exact))
	for id, balance := range exact {
		if !balance.IsInt64() {
			return nil, ErrInvalid
		}
		b[id] = balance.Int64()
	}
	return b, nil
}

// ledgerPayers excludes retained overpayment from balances while preserving it
// in the immutable payer contributions for later statistics.
func ledgerPayers(e Expense, payers []ExpensePayer) ([]ExpensePayer, error) {
	if payers == nil {
		var err error
		payers, err = normalizedPayers(e)
		if err != nil {
			return nil, err
		}
	}
	if e.SplitOverpayment {
		return payers, nil
	}
	var paid int64
	for _, payer := range payers {
		var err error
		paid, err = addCentavos(paid, payer.AmountCents)
		if err != nil {
			return nil, err
		}
	}
	if paid < e.AmountCents {
		return nil, ErrInvalid
	}
	if paid == e.AmountCents {
		return payers, nil
	}
	result := make([]ExpensePayer, len(payers))
	used := int64(0)
	for i, payer := range payers {
		v := new(big.Int).Quo(new(big.Int).Mul(big.NewInt(e.AmountCents), big.NewInt(payer.AmountCents)), big.NewInt(paid))
		if !v.IsInt64() {
			return nil, ErrInvalid
		}
		result[i] = ExpensePayer{MemberID: payer.MemberID, AmountCents: v.Int64()}
		var err error
		used, err = addCentavos(used, result[i].AmountCents)
		if err != nil {
			return nil, err
		}
	}
	for i := range result {
		if used == e.AmountCents {
			break
		}
		result[i].AmountCents++
		used++
	}
	return result, nil
}

func retainedOverpayments(e Expense) ([]ExpensePayer, error) {
	if e.SplitOverpayment {
		return nil, nil
	}
	payers, err := normalizedPayers(e)
	if err != nil {
		return nil, err
	}
	credited, err := ledgerPayers(e, payers)
	if err != nil {
		return nil, err
	}
	retained := make([]ExpensePayer, 0, len(payers))
	for index, payer := range payers {
		amount := payer.AmountCents - credited[index].AmountCents
		if amount > 0 {
			retained = append(retained, ExpensePayer{MemberID: payer.MemberID, AmountCents: amount})
		}
	}
	return retained, nil
}

type obligation struct {
	from, to string
	amount   int64
}

// expenseObligations pairs participant shares with payer contributions in their
// stored order. It conserves every centavo and makes the bilateral ledger
// deterministic even when a participant also paid part of the expense.
func expenseObligations(e Expense, shares map[string]int64) ([]obligation, error) {
	payers, err := ledgerPayers(e, nil)
	if err != nil {
		return nil, err
	}
	remaining := make([]ExpensePayer, len(payers))
	copy(remaining, payers)
	result := []obligation{}
	payerIndex := 0
	for _, participantID := range e.ParticipantIDs {
		owed := shares[participantID]
		for owed > 0 && payerIndex < len(remaining) {
			amount := owed
			if remaining[payerIndex].AmountCents < amount {
				amount = remaining[payerIndex].AmountCents
			}
			result = append(result, obligation{participantID, remaining[payerIndex].MemberID, amount})
			owed -= amount
			remaining[payerIndex].AmountCents -= amount
			if remaining[payerIndex].AmountCents == 0 {
				payerIndex++
			}
		}
	}
	return result, nil
}

func normalizedPayers(e Expense) ([]ExpensePayer, error) {
	payers := e.Payers
	if len(payers) == 0 {
		payers = []ExpensePayer{{MemberID: e.PayerID, AmountCents: e.AmountCents}}
	}
	seen := map[string]bool{}
	var total int64
	for _, payer := range payers {
		if payer.MemberID == "" || payer.AmountCents <= 0 || seen[payer.MemberID] {
			return nil, ErrInvalid
		}
		var err error
		total, err = addCentavos(total, payer.AmountCents)
		if err != nil {
			return nil, ErrInvalid
		}
		seen[payer.MemberID] = true
	}
	if total < e.AmountCents {
		return nil, ErrInvalid
	}
	return payers, nil
}

// expenseAllocatedAmount is the amount participants share. Contributions above
// the entered expense total are additional group spending, never lost cents.
func expenseAllocatedAmount(e Expense) (int64, error) {
	payers, err := normalizedPayers(e)
	if err != nil {
		return 0, err
	}
	var total int64
	for _, payer := range payers {
		total, err = addCentavos(total, payer.AmountCents)
		if err != nil {
			return 0, err
		}
	}
	return total, nil
}

func split(a int64, ids []string, g Group, mode string) (map[string]int64, error) {
	if a <= 0 || len(ids) == 0 || mode != "" && mode != "equal" && mode != "salary" {
		return nil, ErrInvalid
	}
	if mode == "" {
		mode = "equal"
	}

	o := map[string]int64{}
	m := map[string]Member{}
	for _, x := range g.Members {
		if x.ID == "" {
			return nil, ErrInvalid
		}
		if _, duplicate := m[x.ID]; duplicate {
			return nil, ErrInvalid
		}
		m[x.ID] = x
	}
	total := new(big.Int)
	w := map[string]*big.Int{}
	for _, id := range ids {
		member, exists := m[id]
		if !exists {
			return nil, ErrInvalid
		}
		if _, duplicate := w[id]; duplicate {
			return nil, ErrInvalid
		}
		weight := int64(1)
		if mode == "salary" {
			if member.SalaryCents <= 0 {
				return nil, ErrInvalid
			}
			weight = member.SalaryCents
		}
		w[id] = big.NewInt(weight)
		total.Add(total, w[id])
	}

	var used int64
	for _, id := range ids {
		product := new(big.Int).Mul(big.NewInt(a), w[id])
		share := new(big.Int).Quo(product, total)
		if !share.IsInt64() {
			return nil, ErrInvalid
		}
		o[id] = share.Int64()
		var err error
		used, err = addCentavos(used, o[id])
		if err != nil {
			return nil, err
		}
	}
	for _, id := range ids {
		if used == a {
			break
		}
		o[id]++
		used++
	}
	return o, nil
}

func validateExactShares(shares []ExpenseShare, ids []string, total int64) (map[string]int64, error) {
	if total <= 0 || len(shares) != len(ids) || len(ids) == 0 {
		return nil, ErrInvalid
	}
	wanted := make(map[string]bool, len(ids))
	for _, id := range ids {
		if id == "" || wanted[id] {
			return nil, ErrInvalid
		}
		wanted[id] = true
	}
	result := make(map[string]int64, len(shares))
	var allocated int64
	for _, share := range shares {
		if !wanted[share.MemberID] || share.AmountCents < 0 {
			return nil, ErrInvalid
		}
		if _, duplicate := result[share.MemberID]; duplicate {
			return nil, ErrInvalid
		}
		var err error
		allocated, err = addCentavos(allocated, share.AmountCents)
		if err != nil {
			return nil, ErrInvalid
		}
		result[share.MemberID] = share.AmountCents
	}
	if allocated != total {
		return nil, ErrInvalid
	}
	return result, nil
}

func sharesForExpense(e Expense, g Group, total int64) (map[string]int64, error) {
	if !e.SplitOverpayment {
		total = e.AmountCents
	}
	if e.SplitMode == "exact" {
		shares, err := validateExactShares(e.ExplicitShares, e.ParticipantIDs, e.AmountCents)
		if err != nil || total < e.AmountCents {
			return nil, ErrInvalid
		}
		extra := total - e.AmountCents
		if extra == 0 {
			return shares, nil
		}
		eligible := make([]string, 0, len(e.ParticipantIDs))
		var weight int64
		for _, id := range e.ParticipantIDs {
			if shares[id] > 0 {
				eligible = append(eligible, id)
				weight, err = addCentavos(weight, shares[id])
				if err != nil {
					return nil, err
				}
			}
		}
		if len(eligible) == 0 || weight == 0 {
			return nil, ErrInvalid
		}
		used := int64(0)
		for _, id := range eligible {
			product := new(big.Int).Mul(big.NewInt(extra), big.NewInt(shares[id]))
			portion := new(big.Int).Quo(product, big.NewInt(weight))
			if !portion.IsInt64() {
				return nil, ErrInvalid
			}
			var addErr error
			shares[id], addErr = addCentavos(shares[id], portion.Int64())
			if addErr != nil {
				return nil, addErr
			}
			used, addErr = addCentavos(used, portion.Int64())
			if addErr != nil {
				return nil, addErr
			}
		}
		for _, id := range eligible {
			if used == extra {
				break
			}
			shares[id]++
			used++
		}
		return shares, nil
	}
	return split(total, e.ParticipantIDs, g, e.SplitMode)
}

func addCentavos(current, delta int64) (int64, error) {
	if (delta > 0 && current > math.MaxInt64-delta) || (delta < 0 && current < math.MinInt64-delta) {
		return 0, ErrInvalid
	}
	return current + delta, nil
}
