package groups

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"time"
)

func (r *Repository) AddExpense(c context.Context, u, gid string, in AddExpenseInput) (Group, error) {
	g, e := r.Get(c, u, gid)
	if e != nil {
		return g, e
	}
	if e = prepareExpense(g, &in); e != nil {
		return g, e
	}
	id, e := newID("expense")
	if e != nil {
		return g, e
	}
	t, e := r.db.BeginTx(c, nil)
	if e != nil {
		return g, e
	}
	defer t.Rollback()
	if e = insertExpense(c, t, gid, id, in, time.Time{}); e != nil {
		return g, e
	}
	if e = t.Commit(); e != nil {
		return g, e
	}
	return r.Get(c, u, gid)
}

func prepareExpense(g Group, in *AddExpenseInput) error {
	in.Description = strings.TrimSpace(in.Description)
	if in.Description == "" || in.AmountCents <= 0 || len(in.ParticipantIDs) == 0 {
		return ErrInvalid
	}
	if in.SplitMode == "" {
		in.SplitMode = "equal"
	}
	if in.SplitOverpayment == nil {
		defaultSplitOverpayment := true
		in.SplitOverpayment = &defaultSplitOverpayment
	}
	if in.SplitMode != "equal" && in.SplitMode != "salary" && in.SplitMode != "exact" || in.SplitMode == "salary" && (!g.SalarySplitEnabled || !g.SalarySplitAvailable) {
		return ErrInvalid
	}
	ms := map[string]Member{}
	for _, m := range g.Members {
		if m.Active {
			ms[m.ID] = m
		}
	}
	// payer_id remains accepted for backward-compatible clients. New clients
	// send ordered payer contributions instead.
	if len(in.Payers) == 0 {
		in.Payers = []ExpensePayer{{MemberID: in.PayerID, AmountCents: in.AmountCents}}
	}
	var paid int64
	payerSeen := map[string]bool{}
	for _, payer := range in.Payers {
		if _, ok := ms[payer.MemberID]; !ok || payerSeen[payer.MemberID] || payer.AmountCents <= 0 {
			return ErrInvalid
		}
		var err error
		paid, err = addCentavos(paid, payer.AmountCents)
		if err != nil {
			return ErrInvalid
		}
		payerSeen[payer.MemberID] = true
	}
	if paid < in.AmountCents {
		return ErrInvalid
	}
	// Retain a meaningful legacy field for older readers.
	in.PayerID = in.Payers[0].MemberID
	seen := map[string]bool{}
	for _, id := range in.ParticipantIDs {
		m, ok := ms[id]
		if !ok || seen[id] || in.SplitMode == "salary" && !m.SalarySharing {
			return ErrInvalid
		}
		seen[id] = true
	}
	if in.SplitMode == "exact" {
		if _, err := validateExactShares(in.Shares, in.ParticipantIDs, in.AmountCents); err != nil {
			return ErrInvalid
		}
	} else if len(in.Shares) != 0 {
		return ErrInvalid
	}
	return nil
}

func insertExpense(c context.Context, t *sql.Tx, gid, id string, in AddExpenseInput, createdAt time.Time) error {
	var e error
	var paid int64
	for _, payer := range in.Payers {
		paid, e = addCentavos(paid, payer.AmountCents)
		if e != nil {
			return ErrInvalid
		}
	}
	if createdAt.IsZero() {
		_, e = t.ExecContext(c, `INSERT INTO expenses(id,group_id,description,amount_cents,payer_id,split_mode,split_overpayment)VALUES($1,$2,$3,$4,$5,$6,$7)`, id, gid, in.Description, in.AmountCents, in.PayerID, in.SplitMode, *in.SplitOverpayment)
	} else {
		_, e = t.ExecContext(c, `INSERT INTO expenses(id,group_id,description,amount_cents,payer_id,split_mode,split_overpayment,created_at)VALUES($1,$2,$3,$4,$5,$6,$7,$8)`, id, gid, in.Description, in.AmountCents, in.PayerID, in.SplitMode, *in.SplitOverpayment, createdAt)
	}
	if e != nil {
		return e
	}
	for p, m := range in.ParticipantIDs {
		if _, e = t.ExecContext(c, `INSERT INTO expense_participants(expense_id,member_id,position)VALUES($1,$2,$3)`, id, m, p); e != nil {
			return e
		}
	}
	for p, payer := range in.Payers {
		if _, e = t.ExecContext(c, `INSERT INTO expense_payers(expense_id,member_id,position,amount_cents)VALUES($1,$2,$3,$4)`, id, payer.MemberID, p, payer.AmountCents); e != nil {
			return e
		}
	}
	if !*in.SplitOverpayment && paid > in.AmountCents {
		retained, err := retainedOverpayments(Expense{
			AmountCents:      in.AmountCents,
			Payers:           in.Payers,
			SplitOverpayment: false,
		})
		if err != nil {
			return ErrInvalid
		}
		for index, payer := range retained {
			if _, err = t.ExecContext(c, `INSERT INTO expense_retained_overpayments(expense_id,member_id,position,amount_cents)VALUES($1,$2,$3,$4)`, id, payer.MemberID, index, payer.AmountCents); err != nil {
				return err
			}
		}
	}
	for p, share := range in.Shares {
		if _, e = t.ExecContext(c, `INSERT INTO expense_shares(expense_id,member_id,position,amount_cents)VALUES($1,$2,$3,$4)`, id, share.MemberID, p, share.AmountCents); e != nil {
			return e
		}
	}
	return nil
}
func (r *Repository) AddSettlement(c context.Context, u, g, id string, amountCents *int64) (Group, error) {
	t, e := r.db.BeginTx(c, nil)
	if e != nil {
		return Group{}, e
	}
	defer t.Rollback()
	// Serialize settlement writes per group so two concurrent payments can
	// never both validate against the same outstanding balance.
	if e = lockGroup(c, t, g); e != nil {
		return Group{}, e
	}
	var selfID string
	if e = t.QueryRowContext(c, `SELECT member_id FROM group_members WHERE group_id=$1 AND user_id=$2 AND removed_at IS NULL AND accepted AND declined_at IS NULL`, g, u).Scan(&selfID); e != nil {
		if errors.Is(e, sql.ErrNoRows) {
			return Group{}, ErrNotFound
		}
		return Group{}, e
	}
	if id == selfID {
		return Group{}, ErrInvalid
	}
	// Read the ledger inside the same transaction that records the payment,
	// so the outstanding amount is protected by the lock above.
	x := Group{ID: g}
	if e = load(c, &x, t); e != nil {
		return Group{}, e
	}
	var outstanding int64
	for _, relation := range x.PaymentRelations {
		if relation.FromMemberID == selfID && relation.ToMemberID == id {
			outstanding = relation.AmountCents
			break
		}
	}
	var amount int64
	if amountCents == nil {
		amount = outstanding
	} else {
		amount = *amountCents
		if amount < 0 {
			return Group{}, ErrInvalid
		}
		if amount > outstanding {
			return Group{}, ErrOverpayment
		}
	}
	if amount == 0 {
		return Group{}, ErrInvalid
	}
	sid, e := newID("settlement")
	if e != nil {
		return Group{}, e
	}
	_, e = t.ExecContext(c, `INSERT INTO settlements(id,group_id,from_member_id,to_member_id,amount_cents)VALUES($1,$2,$3,$4,$5)`, sid, g, selfID, id, amount)
	if e != nil {
		return Group{}, e
	}
	if e = t.Commit(); e != nil {
		return Group{}, e
	}
	return r.Get(c, u, g)
}

// lockGroup serializes concurrent writers for one group for the whole
// transaction, so every concurrent payment validates against committed state.
func lockGroup(c context.Context, q queryer, groupID string) error {
	// pg_advisory_xact_lock returns void; scan the NULL column to finish the
	// statement and let the lock hold until the transaction ends.
	var locked any
	return q.QueryRowContext(c, `SELECT pg_advisory_xact_lock(hashtextextended($1,0))`, groupID).Scan(&locked)
}

// ValidatePaymentRequest ties the simulated-provider boundary to the ledger.
// A creditor can request only the exact amount a debtor owes them in the
// group's deterministic settlement projection.
func (r *Repository) ValidatePaymentRequest(c context.Context, userID, groupID, debtorID string, amountCents int64) error {
	g, err := r.Get(c, userID, groupID)
	if err != nil {
		return err
	}
	return ValidatePaymentRequestData(g, userID, debtorID, amountCents)
}

// ValidatePaymentRequestData contains the ledger rule independently of
// storage, so the financial authorization invariant has fast regression tests.

func ValidatePaymentRequestData(g Group, userID, debtorID string, amountCents int64) error {
	if amountCents <= 0 {
		return ErrInvalid
	}
	var requesterID string
	for _, member := range g.Members {
		if member.UserID == userID && member.Active && member.Accepted {
			requesterID = member.ID
			break
		}
	}
	if requesterID == "" {
		return ErrInvalid
	}
	for _, relation := range PaymentRelations(g) {
		if relation.FromMemberID == debtorID && relation.ToMemberID == requesterID && relation.AmountCents == amountCents {
			return nil
		}
	}
	return ErrInvalid
}
