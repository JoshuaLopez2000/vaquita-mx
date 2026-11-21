package groups

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"time"
	"unicode/utf8"
)

func (r *Repository) AddExpense(c context.Context, u, gid string, in AddExpenseInput) (Group, error) {
	t, e := r.db.BeginTx(c, nil)
	if e != nil {
		return Group{}, e
	}
	defer t.Rollback()
	g, e := r.AddExpenseTx(c, t, u, gid, in)
	if e != nil {
		return Group{}, e
	}
	if e = t.Commit(); e != nil {
		return Group{}, e
	}
	return g, nil
}

// AddExpenseTx validates and inserts the expense inside the transaction the
// caller owns. The authorization read, the ledger validation, the insert, and
// the response projection share one snapshot, so the recorded outcome always
// matches the rows that committed.
func (r *Repository) AddExpenseTx(c context.Context, tx *sql.Tx, u, gid string, in AddExpenseInput) (Group, error) {
	in.ReplacesExpenseID = strings.TrimSpace(in.ReplacesExpenseID)
	if in.ReplacesExpenseID != "" {
		if e := lockGroup(c, tx, gid); e != nil {
			return Group{}, e
		}
	}
	g, e := getOn(c, tx, u, gid)
	if e != nil {
		return g, e
	}
	if in.ReplacesExpenseID != "" {
		if e = validateExpenseReplacement(c, tx, gid, in.ReplacesExpenseID); e != nil {
			return Group{}, e
		}
	}
	if e = prepareExpense(g, &in); e != nil {
		return g, e
	}
	id, e := newID("expense")
	if e != nil {
		return Group{}, e
	}
	if e = insertExpense(c, tx, gid, id, in, time.Time{}); e != nil {
		return Group{}, e
	}
	return getOn(c, tx, u, gid)
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
	if in.SplitMode != "equal" && in.SplitMode != "salary" && in.SplitMode != "exact" && in.SplitMode != "percentage" || in.SplitMode == "salary" && (!g.SalarySplitEnabled || !g.SalarySplitAvailable) {
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
	switch in.SplitMode {
	case "exact":
		if len(in.Percentages) != 0 {
			return ErrInvalid
		}
		if _, err := validateExactShares(in.Shares, in.ParticipantIDs, in.AmountCents); err != nil {
			return ErrInvalid
		}
	case "percentage":
		if len(in.Shares) != 0 {
			return ErrInvalid
		}
		percentages, err := validatePercentages(in.Percentages, in.ParticipantIDs)
		if err != nil {
			return ErrInvalid
		}
		computedShares, err := computePercentageFinalShares(in.AmountCents, paid, *in.SplitOverpayment, in.ParticipantIDs, percentages)
		if err != nil {
			return ErrInvalid
		}
		in.Shares = computedShares
	default:
		if len(in.Shares) != 0 || len(in.Percentages) != 0 {
			return ErrInvalid
		}
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
	var replacesExpense sql.NullString
	if trimmed := strings.TrimSpace(in.ReplacesExpenseID); trimmed != "" {
		replacesExpense = sql.NullString{String: trimmed, Valid: true}
	}
	if createdAt.IsZero() {
		_, e = t.ExecContext(c, `INSERT INTO expenses(id,group_id,description,amount_cents,payer_id,split_mode,split_overpayment,replaces_expense_id)VALUES($1,$2,$3,$4,$5,$6,$7,$8)`, id, gid, in.Description, in.AmountCents, in.PayerID, in.SplitMode, *in.SplitOverpayment, replacesExpense)
	} else {
		_, e = t.ExecContext(c, `INSERT INTO expenses(id,group_id,description,amount_cents,payer_id,split_mode,split_overpayment,replaces_expense_id,created_at)VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`, id, gid, in.Description, in.AmountCents, in.PayerID, in.SplitMode, *in.SplitOverpayment, replacesExpense, createdAt)
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
	percentageByMember := make(map[string]int, len(in.Percentages))
	if in.SplitMode == "percentage" {
		for _, entry := range in.Percentages {
			percentageByMember[entry.MemberID] = entry.PercentageBps
		}
	}
	for p, share := range in.Shares {
		var percentageBps sql.NullInt64
		if bps, ok := percentageByMember[share.MemberID]; ok {
			if bps <= 0 || bps > PercentageBasisPointsTotal {
				return ErrInvalid
			}
			percentageBps = sql.NullInt64{Int64: int64(bps), Valid: true}
		}
		if _, e = t.ExecContext(c, `INSERT INTO expense_shares(expense_id,member_id,position,amount_cents,percentage_bps)VALUES($1,$2,$3,$4,$5)`, id, share.MemberID, p, share.AmountCents, percentageBps); e != nil {
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
	group, e := r.AddSettlementTx(c, t, u, g, id, amountCents, "")
	if e != nil {
		return Group{}, e
	}
	if e = t.Commit(); e != nil {
		return Group{}, e
	}
	return group, nil
}

// AddSettlementTx writes the settlement inside the transaction the caller
// owns. It serializes through the group lock and reads the ledger in the
// same transaction that records the payment, so a concurrent partial payment
// can never overpay.
func (r *Repository) AddSettlementTx(c context.Context, tx *sql.Tx, u, g, id string, amountCents *int64, replacesSettlementID string) (Group, error) {
	// Serialize settlement writes per group so two concurrent payments can
	// never both validate against the same outstanding balance.
	if e := lockGroup(c, tx, g); e != nil {
		return Group{}, e
	}
	var selfID, role, visibility string
	if e := tx.QueryRowContext(c, `
SELECT m.member_id,m.role,g.visibility
FROM group_members m JOIN expense_groups g ON g.id=m.group_id
WHERE m.group_id=$1 AND m.user_id=$2 AND m.removed_at IS NULL
  AND m.accepted AND m.declined_at IS NULL`, g, u).Scan(&selfID, &role, &visibility); e != nil {
		if errors.Is(e, sql.ErrNoRows) {
			return Group{}, ErrNotFound
		}
		return Group{}, e
	}
	if visibility == "shared" || role != RoleOwner {
		return Group{}, ErrNotFound
	}
	replacesSettlementID = strings.TrimSpace(replacesSettlementID)
	if replacesSettlementID != "" {
		if e := validateSettlementReplacement(c, tx, g, replacesSettlementID); e != nil {
			return Group{}, e
		}
	}
	if id == selfID {
		return Group{}, ErrInvalid
	}
	// Read the ledger inside the same transaction that records the payment,
	// so the outstanding amount is protected by the lock above.
	x := Group{ID: g}
	if e := load(c, &x, tx); e != nil {
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
	var replacesSettlement sql.NullString
	if replacesSettlementID != "" {
		replacesSettlement = sql.NullString{String: replacesSettlementID, Valid: true}
	}
	if _, e = tx.ExecContext(c, `INSERT INTO settlements(id,group_id,from_member_id,to_member_id,amount_cents,replaces_settlement_id)VALUES($1,$2,$3,$4,$5,$6)`, sid, g, selfID, id, amount, replacesSettlement); e != nil {
		return Group{}, e
	}
	return getOn(c, tx, u, g)
}

// ConfirmReceivedSettlementTx records a receipt from debtorID to the
// authenticated member. Shared-group members can only confirm money owed to
// themselves; the owner controls bilateral settlements in personal groups.
func (r *Repository) ConfirmReceivedSettlementTx(c context.Context, tx *sql.Tx, u, g, debtorID string, amountCents *int64, replacesSettlementID string) (Group, error) {
	if e := lockGroup(c, tx, g); e != nil {
		return Group{}, e
	}
	var creditorID, role, visibility string
	e := tx.QueryRowContext(c, `
SELECT x.member_id,x.role,g.visibility
FROM group_members x JOIN expense_groups g ON g.id=x.group_id
WHERE x.group_id=$1 AND x.user_id=$2 AND x.removed_at IS NULL
  AND x.accepted AND x.declined_at IS NULL`,
		g, u).Scan(&creditorID, &role, &visibility)
	if errors.Is(e, sql.ErrNoRows) {
		return Group{}, ErrNotFound
	}
	if e != nil {
		return Group{}, e
	}
	if visibility == "personal" && role != RoleOwner {
		return Group{}, ErrNotFound
	}
	replacesSettlementID = strings.TrimSpace(replacesSettlementID)
	if replacesSettlementID != "" {
		if e := validateSettlementReplacement(c, tx, g, replacesSettlementID); e != nil {
			return Group{}, e
		}
	}
	if debtorID == creditorID {
		return Group{}, ErrInvalid
	}

	x := Group{ID: g}
	if e := load(c, &x, tx); e != nil {
		return Group{}, e
	}
	var outstanding int64
	for _, relation := range x.PaymentRelations {
		if relation.FromMemberID == debtorID && relation.ToMemberID == creditorID {
			outstanding = relation.AmountCents
			break
		}
	}
	amount := outstanding
	if amountCents != nil {
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
	var replacesSettlement sql.NullString
	if replacesSettlementID != "" {
		replacesSettlement = sql.NullString{String: replacesSettlementID, Valid: true}
	}
	if _, e = tx.ExecContext(c, `INSERT INTO settlements(id,group_id,from_member_id,to_member_id,amount_cents,replaces_settlement_id)VALUES($1,$2,$3,$4,$5,$6)`, sid, g, debtorID, creditorID, amount, replacesSettlement); e != nil {
		return Group{}, e
	}
	return getOn(c, tx, u, g)
}

func (r *Repository) ReverseExpense(c context.Context, userID, groupID, expenseID string, in ReverseRecordInput) (Group, error) {
	tx, err := r.db.BeginTx(c, nil)
	if err != nil {
		return Group{}, err
	}
	defer tx.Rollback()
	group, err := r.ReverseExpenseTx(c, tx, userID, groupID, expenseID, in)
	if err != nil {
		return Group{}, err
	}
	if err = tx.Commit(); err != nil {
		return Group{}, err
	}
	return group, nil
}

// ReverseExpenseTx records one immutable compensating reversal for an expense
// inside the caller's transaction. Personal groups restrict reversals to the
// owner; shared groups allow any active accepted member. Hidden groups or
// cross-group expense IDs always return ErrNotFound.
func (r *Repository) ReverseExpenseTx(c context.Context, tx *sql.Tx, userID, groupID, expenseID string, in ReverseRecordInput) (Group, error) {
	if err := lockGroup(c, tx, groupID); err != nil {
		return Group{}, err
	}
	var actorMemberID, role, visibility string
	err := tx.QueryRowContext(c, `
SELECT m.member_id,m.role,g.visibility
FROM group_members m JOIN expense_groups g ON g.id=m.group_id
WHERE m.group_id=$1 AND m.user_id=$2 AND m.removed_at IS NULL
  AND m.accepted AND m.declined_at IS NULL`, groupID, userID).Scan(&actorMemberID, &role, &visibility)
	if errors.Is(err, sql.ErrNoRows) {
		return Group{}, ErrNotFound
	}
	if err != nil {
		return Group{}, err
	}
	if visibility == "personal" && role != RoleOwner {
		return Group{}, ErrNotFound
	}
	var exists bool
	if err = tx.QueryRowContext(c, `SELECT EXISTS(SELECT 1 FROM expenses WHERE id=$1 AND group_id=$2)`, expenseID, groupID).Scan(&exists); err != nil {
		return Group{}, err
	}
	if !exists {
		return Group{}, ErrNotFound
	}
	reason, err := validateReversalReason(in.Reason)
	if err != nil {
		return Group{}, err
	}
	var alreadyReversed bool
	if err = tx.QueryRowContext(c, `SELECT EXISTS(SELECT 1 FROM expense_reversals WHERE original_expense_id=$1)`, expenseID).Scan(&alreadyReversed); err != nil {
		return Group{}, err
	}
	if alreadyReversed {
		return Group{}, ErrAlreadyReversed
	}
	reversalID, err := newID("expense_reversal")
	if err != nil {
		return Group{}, err
	}
	if _, err = tx.ExecContext(c, `INSERT INTO expense_reversals(id,group_id,original_expense_id,actor_user_id,actor_member_id,reason)VALUES($1,$2,$3,$4,$5,$6)`, reversalID, groupID, expenseID, userID, actorMemberID, reason); err != nil {
		return Group{}, err
	}
	return getOn(c, tx, userID, groupID)
}

func (r *Repository) ReverseSettlement(c context.Context, userID, groupID, settlementID string, in ReverseRecordInput) (Group, error) {
	tx, err := r.db.BeginTx(c, nil)
	if err != nil {
		return Group{}, err
	}
	defer tx.Rollback()
	group, err := r.ReverseSettlementTx(c, tx, userID, groupID, settlementID, in)
	if err != nil {
		return Group{}, err
	}
	if err = tx.Commit(); err != nil {
		return Group{}, err
	}
	return group, nil
}

// ReverseSettlementTx records one immutable compensating reversal for a
// settlement inside the caller's transaction. Personal groups restrict
// reversals to the owner; shared groups allow the owner or the settlement's
// creditor (to_member_id). Hidden groups or unauthorized targets return
// ErrNotFound.
func (r *Repository) ReverseSettlementTx(c context.Context, tx *sql.Tx, userID, groupID, settlementID string, in ReverseRecordInput) (Group, error) {
	if err := lockGroup(c, tx, groupID); err != nil {
		return Group{}, err
	}
	var actorMemberID, role, visibility string
	err := tx.QueryRowContext(c, `
SELECT m.member_id,m.role,g.visibility
FROM group_members m JOIN expense_groups g ON g.id=m.group_id
WHERE m.group_id=$1 AND m.user_id=$2 AND m.removed_at IS NULL
  AND m.accepted AND m.declined_at IS NULL`, groupID, userID).Scan(&actorMemberID, &role, &visibility)
	if errors.Is(err, sql.ErrNoRows) {
		return Group{}, ErrNotFound
	}
	if err != nil {
		return Group{}, err
	}
	if visibility == "personal" && role != RoleOwner {
		return Group{}, ErrNotFound
	}
	var toMemberID string
	err = tx.QueryRowContext(c, `SELECT to_member_id FROM settlements WHERE id=$1 AND group_id=$2`, settlementID, groupID).Scan(&toMemberID)
	if errors.Is(err, sql.ErrNoRows) {
		return Group{}, ErrNotFound
	}
	if err != nil {
		return Group{}, err
	}
	if visibility == "shared" && role != RoleOwner && toMemberID != actorMemberID {
		return Group{}, ErrNotFound
	}
	reason, err := validateReversalReason(in.Reason)
	if err != nil {
		return Group{}, err
	}
	var alreadyReversed bool
	if err = tx.QueryRowContext(c, `SELECT EXISTS(SELECT 1 FROM settlement_reversals WHERE original_settlement_id=$1)`, settlementID).Scan(&alreadyReversed); err != nil {
		return Group{}, err
	}
	if alreadyReversed {
		return Group{}, ErrAlreadyReversed
	}
	reversalID, err := newID("settlement_reversal")
	if err != nil {
		return Group{}, err
	}
	if _, err = tx.ExecContext(c, `INSERT INTO settlement_reversals(id,group_id,original_settlement_id,actor_user_id,actor_member_id,reason)VALUES($1,$2,$3,$4,$5,$6)`, reversalID, groupID, settlementID, userID, actorMemberID, reason); err != nil {
		return Group{}, err
	}
	return getOn(c, tx, userID, groupID)
}

func validateReversalReason(raw string) (string, error) {
	reason := strings.TrimSpace(raw)
	if reason == "" || utf8.RuneCountInString(reason) > MaxReversalReasonLength {
		return "", ErrInvalid
	}
	return reason, nil
}

func validateExpenseReplacement(c context.Context, q queryer, groupID, replacesExpenseID string) error {
	var exists bool
	if err := q.QueryRowContext(c, `SELECT EXISTS(SELECT 1 FROM expenses WHERE id=$1 AND group_id=$2)`, replacesExpenseID, groupID).Scan(&exists); err != nil {
		return err
	}
	if !exists {
		return ErrNotFound
	}
	var reversed bool
	if err := q.QueryRowContext(c, `SELECT EXISTS(SELECT 1 FROM expense_reversals WHERE original_expense_id=$1 AND group_id=$2)`, replacesExpenseID, groupID).Scan(&reversed); err != nil {
		return err
	}
	if !reversed {
		return ErrInvalid
	}
	var alreadyReplaced bool
	if err := q.QueryRowContext(c, `SELECT EXISTS(SELECT 1 FROM expenses WHERE replaces_expense_id=$1)`, replacesExpenseID).Scan(&alreadyReplaced); err != nil {
		return err
	}
	if alreadyReplaced {
		return ErrInvalid
	}
	return nil
}

func validateSettlementReplacement(c context.Context, q queryer, groupID, replacesSettlementID string) error {
	var exists bool
	if err := q.QueryRowContext(c, `SELECT EXISTS(SELECT 1 FROM settlements WHERE id=$1 AND group_id=$2)`, replacesSettlementID, groupID).Scan(&exists); err != nil {
		return err
	}
	if !exists {
		return ErrNotFound
	}
	var reversed bool
	if err := q.QueryRowContext(c, `SELECT EXISTS(SELECT 1 FROM settlement_reversals WHERE original_settlement_id=$1 AND group_id=$2)`, replacesSettlementID, groupID).Scan(&reversed); err != nil {
		return err
	}
	if !reversed {
		return ErrInvalid
	}
	var alreadyReplaced bool
	if err := q.QueryRowContext(c, `SELECT EXISTS(SELECT 1 FROM settlements WHERE replaces_settlement_id=$1)`, replacesSettlementID).Scan(&alreadyReplaced); err != nil {
		return err
	}
	if alreadyReplaced {
		return ErrInvalid
	}
	return nil
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
	if g.Visibility != "shared" || amountCents <= 0 {
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
