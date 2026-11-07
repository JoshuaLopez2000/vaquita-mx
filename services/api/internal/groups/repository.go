package groups

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"strings"
	"time"

	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/auth"
)

func Open(ctx context.Context, url string) (*Repository, error) {
	db, e := sql.Open("pgx", url)
	if e != nil {
		return nil, e
	}
	for i := 0; i < 12; i++ {
		if e = db.PingContext(ctx); e == nil {
			return &Repository{db}, nil
		}
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(time.Second):
		}
	}
	return nil, e
}
func (r *Repository) Close() error                 { return r.db.Close() }
func (r *Repository) Ping(c context.Context) error { return r.db.PingContext(c) }
func (r *Repository) List(c context.Context, u string) ([]Group, error) {
	rows, e := r.db.QueryContext(c, `SELECT g.id,g.name,g.emoji,g.visibility,g.salary_split_enabled FROM expense_groups g WHERE EXISTS(SELECT 1 FROM group_members x WHERE x.group_id=g.id AND x.user_id=$1 AND x.removed_at IS NULL AND x.accepted AND x.declined_at IS NULL AND (x.role='owner' OR g.visibility='shared')) ORDER BY g.created_at DESC`, u)
	if e != nil {
		return nil, e
	}
	defer rows.Close()
	out := make([]Group, 0)
	for rows.Next() {
		var g Group
		if e = rows.Scan(&g.ID, &g.Name, &g.Emoji, &g.Visibility, &g.SalarySplitEnabled); e != nil {
			return nil, e
		}
		if e = r.load(c, &g); e != nil {
			return nil, e
		}
		out = append(out, g)
	}
	return out, rows.Err()
}
func (r *Repository) Get(c context.Context, u, id string) (Group, error) {
	var g Group
	e := r.db.QueryRowContext(c, `SELECT g.id,g.name,g.emoji,g.visibility,g.salary_split_enabled FROM expense_groups g WHERE g.id=$1 AND EXISTS(SELECT 1 FROM group_members x WHERE x.group_id=g.id AND x.user_id=$2 AND x.removed_at IS NULL AND x.accepted AND x.declined_at IS NULL AND (x.role='owner' OR g.visibility='shared'))`, id, u).Scan(&g.ID, &g.Name, &g.Emoji, &g.Visibility, &g.SalarySplitEnabled)
	if errors.Is(e, sql.ErrNoRows) {
		return g, ErrNotFound
	}
	if e != nil {
		return g, e
	}
	return g, r.load(c, &g)
}
func (r *Repository) Create(c context.Context, u string, in CreateGroupInput) (Group, error) {
	in.Name = strings.TrimSpace(in.Name)
	in.Emoji = strings.TrimSpace(in.Emoji)
	if len(in.Name) < 2 || in.Emoji == "" {
		return Group{}, ErrInvalid
	}
	if in.Visibility == "" {
		in.Visibility = "personal"
	}
	if in.Visibility != "personal" && in.Visibility != "shared" {
		return Group{}, ErrInvalid
	}
	// Shared invitations and salary consent are completed after creation.
	in.SalarySplitEnabled = false
	id, e := newID("group")
	if e != nil {
		return Group{}, e
	}
	tx, e := r.db.BeginTx(c, nil)
	if e != nil {
		return Group{}, e
	}
	defer tx.Rollback()
	_, e = tx.ExecContext(c, `INSERT INTO expense_groups(id,name,emoji,owner_id,visibility,salary_split_enabled)VALUES($1,$2,$3,$4,$5,$6)`, id, in.Name, in.Emoji, u, in.Visibility, in.SalarySplitEnabled)
	if e != nil {
		return Group{}, e
	}
	if e = r.owner(c, tx, id, u); e != nil {
		return Group{}, e
	}
	p := 1
	for _, m := range in.Members {
		if e = r.member(c, tx, id, p, m, in.Visibility == "shared"); e != nil {
			return Group{}, e
		}
		p++
	}
	for _, n := range in.MemberNames {
		if e = r.member(c, tx, id, p, MemberInput{Name: n}, in.Visibility == "shared"); e != nil {
			return Group{}, e
		}
		p++
	}
	if e = tx.Commit(); e != nil {
		return Group{}, e
	}
	return r.Get(c, u, id)
}
func (r *Repository) owner(c context.Context, t *sql.Tx, g, u string) error {
	var n, p string
	e := t.QueryRowContext(c, `SELECT name,COALESCE(phone,'') FROM users WHERE id=$1`, u).Scan(&n, &p)
	if e != nil {
		return e
	}
	_, e = t.ExecContext(c, `INSERT INTO members(id,name,phone,user_id)VALUES($1,$2,$3,$1) ON CONFLICT(id)DO UPDATE SET name=EXCLUDED.name,phone=EXCLUDED.phone`, u, n, p)
	if e != nil {
		return e
	}
	_, e = t.ExecContext(c, `INSERT INTO group_members(group_id,member_id,position,user_id,role)VALUES($1,$2,0,$2,$3)`, g, u, RoleOwner)
	return e
}
func (r *Repository) member(c context.Context, t *sql.Tx, g string, p int, in MemberInput, shared bool) error {
	in.Name = strings.TrimSpace(in.Name)
	phone, ok := auth.NormalizePhone(in.Phone)
	if !ok {
		return ErrInvalid
	}
	var uid sql.NullString
	var known string
	if phone != "" {
		e := t.QueryRowContext(c, `SELECT id,name FROM users WHERE phone=$1`, phone).Scan(&uid, &known)
		if e != nil && !errors.Is(e, sql.ErrNoRows) {
			return e
		}
		if in.Name == "" && uid.Valid {
			in.Name = known
		}
	}
	if in.Name == "" {
		return ErrInvalid
	}
	if shared && !uid.Valid {
		return ErrInvalid
	}
	id, e := newID("member")
	if e != nil {
		return e
	}
	_, e = t.ExecContext(c, `INSERT INTO members(id,name,phone,user_id)VALUES($1,$2,NULLIF($3,''),$4)`, id, in.Name, phone, uid)
	if e != nil {
		return e
	}
	_, e = t.ExecContext(c, `INSERT INTO group_members(group_id,member_id,position,user_id,accepted,role)VALUES($1,$2,$3,$4,$5,$6)`, g, id, p, uid, !shared, RoleMember)
	return e
}
func (r *Repository) Update(c context.Context, u, id string, in UpdateGroupInput) (Group, error) {
	if e := r.requireRole(c, u, id, RoleOwner); e != nil {
		return Group{}, e
	}
	g, e := r.Get(c, u, id)
	if e != nil {
		return g, e
	}
	if in.Name != "" {
		g.Name = strings.TrimSpace(in.Name)
		if len(g.Name) < 2 {
			return g, ErrInvalid
		}
	}
	if in.Emoji != "" {
		g.Emoji = in.Emoji
	}
	if in.Visibility != "" {
		if in.Visibility != "personal" && in.Visibility != "shared" {
			return g, ErrInvalid
		}
		g.Visibility = in.Visibility
	}
	if in.SalarySplitEnabled != nil {
		if *in.SalarySplitEnabled && (g.Visibility != "shared" || !salaryReady(c, r.db, id)) {
			return g, ErrInvalid
		}
		g.SalarySplitEnabled = *in.SalarySplitEnabled
	}
	res, e := r.db.ExecContext(c, `UPDATE expense_groups SET name=$1,emoji=$2,visibility=$3,salary_split_enabled=$4 WHERE id=$5`, g.Name, g.Emoji, g.Visibility, g.SalarySplitEnabled, id)
	if e != nil {
		return g, e
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return g, ErrNotFound
	}
	return r.Get(c, u, id)
}
func (r *Repository) AddMember(c context.Context, u, g string, in MemberInput) (Group, error) {
	if e := r.requireRole(c, u, g, RoleOwner); e != nil {
		return Group{}, e
	}
	group, e := r.Get(c, u, g)
	if e != nil {
		return Group{}, e
	}
	var p int
	e = r.db.QueryRowContext(c, `SELECT COALESCE(MAX(position),0)+1 FROM group_members WHERE group_id=$1`, g).Scan(&p)
	if e != nil {
		return Group{}, e
	}
	t, e := r.db.BeginTx(c, nil)
	if e != nil {
		return Group{}, e
	}
	defer t.Rollback()
	if e = r.member(c, t, g, p, in, group.Visibility == "shared"); e != nil {
		return Group{}, e
	}
	if e = t.Commit(); e != nil {
		return Group{}, e
	}
	return r.Get(c, u, g)
}
func (r *Repository) UpdateMember(c context.Context, u, g, id string, in UpdateMemberInput) (Group, error) {
	_, e := r.Get(c, u, g)
	if e != nil {
		return Group{}, e
	}
	var n, p string
	var memberUserID sql.NullString
	e = r.db.QueryRowContext(c, `SELECT m.name,COALESCE(m.phone,''),x.user_id FROM members m JOIN group_members x ON x.member_id=m.id WHERE x.group_id=$1 AND m.id=$2 AND x.removed_at IS NULL`, g, id).Scan(&n, &p, &memberUserID)
	if errors.Is(e, sql.ErrNoRows) {
		return Group{}, ErrNotFound
	}
	if e != nil {
		return Group{}, e
	}
	identityChange := in.Name != "" || in.Phone != ""
	if identityChange {
		requesterRole, roleErr := r.role(c, u, g)
		if roleErr != nil || requesterRole != RoleOwner {
			return Group{}, ErrNotFound
		}
	}
	if in.SalarySharing != nil && (!memberUserID.Valid || memberUserID.String != u) {
		return Group{}, ErrNotFound
	}
	if in.Name != "" {
		n = strings.TrimSpace(in.Name)
	}
	if in.Phone != "" {
		var ok bool
		p, ok = auth.NormalizePhone(in.Phone)
		if !ok {
			return Group{}, ErrInvalid
		}
	}
	if n == "" {
		return Group{}, ErrInvalid
	}
	if identityChange {
		_, e = r.db.ExecContext(c, `UPDATE members SET name=$1,phone=NULLIF($2,'') WHERE id=$3`, n, p, id)
		if e != nil {
			return Group{}, e
		}
	}
	if in.SalarySharing != nil {
		_, e = r.db.ExecContext(c, `UPDATE group_members SET salary_sharing=$1 WHERE group_id=$2 AND member_id=$3`, *in.SalarySharing, g, id)
		if e != nil {
			return Group{}, e
		}
	}
	return r.Get(c, u, g)
}
func (r *Repository) RemoveMember(c context.Context, u, g, id string) error {
	if e := r.requireRole(c, u, g, RoleOwner); e != nil {
		return e
	}
	var targetRole string
	e := r.db.QueryRowContext(c, `SELECT role FROM group_members WHERE group_id=$1 AND member_id=$2 AND removed_at IS NULL`, g, id).Scan(&targetRole)
	if errors.Is(e, sql.ErrNoRows) {
		return ErrNotFound
	}
	if e != nil {
		return e
	}
	if targetRole == RoleOwner {
		return ErrInvalid
	}
	z, e := r.db.ExecContext(c, `UPDATE group_members SET removed_at=now() WHERE group_id=$1 AND member_id=$2 AND removed_at IS NULL AND role='member'`, g, id)
	if e != nil {
		return e
	}
	n, _ := z.RowsAffected()
	if n == 0 {
		return ErrNotFound
	}
	return nil
}
func (r *Repository) Unpaid(c context.Context, u, id string) ([]UnpaidBalance, error) {
	g, e := r.Get(c, u, id)
	if e != nil {
		return nil, e
	}
	b, e := calculateBalances(g)
	if e != nil {
		return nil, e
	}
	var o []UnpaidBalance
	for _, m := range g.Members {
		if b[m.ID] != 0 {
			o = append(o, UnpaidBalance{m, b[m.ID]})
		}
	}
	return o, nil
}
func (r *Repository) Status(c context.Context, u string) ([]ContactStatus, error) {
	gs, e := r.List(c, u)
	if e != nil {
		return nil, e
	}
	return ContactStatuses(gs, u), nil
}

// ContactStatuses projects only the balances between the signed-in member and
// each contact. A positive amount means the signed-in member owes the contact.
func ContactStatuses(gs []Group, u string) []ContactStatus {
	x := map[string]ContactStatus{}
	for _, g := range gs {
		members := map[string]Member{}
		var selfID string
		for _, member := range g.Members {
			members[member.ID] = member
			if member.UserID == u && member.Active && member.Accepted {
				selfID = member.ID
			}
		}
		if selfID == "" {
			continue
		}
		for _, relation := range g.PaymentRelations {
			contactID, amount := "", int64(0)
			if relation.FromMemberID == selfID {
				contactID, amount = relation.ToMemberID, relation.AmountCents
			} else if relation.ToMemberID == selfID {
				contactID, amount = relation.FromMemberID, -relation.AmountCents
			}
			if contactID == "" {
				continue
			}
			s := x[contactID]
			s.Member = members[contactID]
			s.AmountCents += amount
			x[contactID] = s
		}
	}
	o := []ContactStatus{}
	for _, s := range x {
		if s.AmountCents != 0 {
			o = append(o, s)
		}
	}
	return o
}

func (r *Repository) Invitations(c context.Context, u string) ([]Invitation, error) {
	rows, e := r.db.QueryContext(c, `SELECT g.id,g.name,g.emoji,g.visibility,g.salary_split_enabled,m.id,x.role,m.name,COALESCE(m.phone,'') FROM group_members x JOIN expense_groups g ON g.id=x.group_id JOIN members m ON m.id=x.member_id WHERE x.user_id=$1 AND g.visibility='shared' AND x.removed_at IS NULL AND NOT x.accepted AND x.declined_at IS NULL ORDER BY g.created_at DESC`, u)
	if e != nil {
		return nil, e
	}
	defer rows.Close()
	out := make([]Invitation, 0)
	for rows.Next() {
		var invite Invitation
		if e = rows.Scan(&invite.Group.ID, &invite.Group.Name, &invite.Group.Emoji, &invite.Group.Visibility, &invite.Group.SalarySplitEnabled, &invite.Member.ID, &invite.Member.Role, &invite.Member.Name, &invite.Member.Phone); e != nil {
			return nil, e
		}
		out = append(out, invite)
	}
	return out, rows.Err()
}

func (r *Repository) RespondInvitation(c context.Context, u, groupID string, accept bool) error {
	result, e := r.db.ExecContext(c, `UPDATE group_members SET accepted=$1,declined_at=CASE WHEN $1 THEN NULL ELSE now() END WHERE group_id=$2 AND user_id=$3 AND removed_at IS NULL AND NOT accepted AND declined_at IS NULL`, accept, groupID, u)
	if e != nil {
		return e
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

func salaryReady(c context.Context, q queryer, groupID string) bool {
	var missing int
	e := q.QueryRowContext(c, `SELECT COUNT(*) FROM group_members x LEFT JOIN users u ON u.id=x.user_id WHERE x.group_id=$1 AND x.removed_at IS NULL AND (NOT x.accepted OR x.declined_at IS NOT NULL OR NOT x.salary_sharing OR COALESCE(u.salary_cents,0)<=0)`, groupID).Scan(&missing)
	return e == nil && missing == 0
}
// queryer is the subset of *sql.DB and *sql.Tx that read-only loading needs.
// It lets a single transaction serve both the authorization read and the
// validation used by commands that must not write against stale state.
type queryer interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
	QueryContext(context.Context, string, ...any) (*sql.Rows, error)
}

func (r *Repository) load(c context.Context, g *Group) error {
	return load(c, g, r.db)
}

// Ledger reads the persisted members, expenses, and settlements of one group
// through q and derives balances and payment relations with the exact
// projection the API serves. q may be a *sql.DB or *sql.Tx, so other packages
// can revalidate financial state inside their own transaction snapshots.
func Ledger(c context.Context, groupID string, q queryer) (Group, error) {
	g := Group{ID: groupID}
	if err := load(c, &g, q); err != nil {
		return Group{}, err
	}
	return g, nil
}

func load(c context.Context, g *Group, q queryer) error {
	g.Members = make([]Member, 0)
	g.Expenses = make([]Expense, 0)
	g.Settlements = make([]Settlement, 0)
	rows, e := q.QueryContext(c, `SELECT m.id,COALESCE(x.user_id,''),x.role,m.name,COALESCE(m.phone,''),x.removed_at IS NULL,x.salary_sharing,x.accepted,COALESCE(u.salary_cents,0) FROM group_members x JOIN members m ON m.id=x.member_id LEFT JOIN users u ON u.id=x.user_id WHERE x.group_id=$1 ORDER BY x.position`, g.ID)
	if e != nil {
		return e
	}
	for rows.Next() {
		var m Member
		if e = rows.Scan(&m.ID, &m.UserID, &m.Role, &m.Name, &m.Phone, &m.Active, &m.SalarySharing, &m.Accepted, &m.SalaryCents); e != nil {
			rows.Close()
			return e
		}
		g.Members = append(g.Members, m)
	}
	rows.Close()
	g.SalarySplitAvailable = salaryReady(c, q, g.ID)
	es, e := q.QueryContext(c, `SELECT id,description,amount_cents,payer_id,split_mode,split_overpayment,created_at FROM expenses WHERE group_id=$1 ORDER BY created_at DESC,id DESC`, g.ID)
	if e != nil {
		return e
	}
	// A transaction shares one connection, so the expense rows must all be
	// read and closed before any per-expense query runs on the same tx.
	type expenseSeed struct {
		id               string
		description      string
		amountCents      int64
		payerID          string
		splitMode        string
		splitOverpayment bool
		createdAt        time.Time
	}
	seeds := make([]expenseSeed, 0)
	for es.Next() {
		var x expenseSeed
		if e = es.Scan(&x.id, &x.description, &x.amountCents, &x.payerID, &x.splitMode, &x.splitOverpayment, &x.createdAt); e != nil {
			es.Close()
			return e
		}
		seeds = append(seeds, x)
	}
	if e = es.Err(); e != nil {
		es.Close()
		return e
	}
	es.Close()
	for _, seed := range seeds {
		x := Expense{ID: seed.id, Description: seed.description, AmountCents: seed.amountCents, PayerID: seed.payerID, SplitMode: seed.splitMode, SplitOverpayment: seed.splitOverpayment, CreatedAt: seed.createdAt}
		ps, _ := q.QueryContext(c, `SELECT member_id FROM expense_participants WHERE expense_id=$1 ORDER BY position`, x.ID)
		for ps.Next() {
			var id string
			ps.Scan(&id)
			x.ParticipantIDs = append(x.ParticipantIDs, id)
		}
		ps.Close()
		payers, queryErr := q.QueryContext(c, `SELECT member_id,amount_cents FROM expense_payers WHERE expense_id=$1 ORDER BY position`, x.ID)
		if queryErr != nil {
			return queryErr
		}
		for payers.Next() {
			var payer ExpensePayer
			if queryErr = payers.Scan(&payer.MemberID, &payer.AmountCents); queryErr != nil {
				payers.Close()
				return queryErr
			}
			x.Payers = append(x.Payers, payer)
		}
		if queryErr = payers.Err(); queryErr != nil {
			payers.Close()
			return queryErr
		}
		payers.Close()
		explicit, queryErr := q.QueryContext(c, `SELECT member_id,amount_cents FROM expense_shares WHERE expense_id=$1 ORDER BY position`, x.ID)
		if queryErr != nil {
			return queryErr
		}
		for explicit.Next() {
			var share ExpenseShare
			if queryErr = explicit.Scan(&share.MemberID, &share.AmountCents); queryErr != nil {
				explicit.Close()
				return queryErr
			}
			x.ExplicitShares = append(x.ExplicitShares, share)
		}
		if queryErr = explicit.Err(); queryErr != nil {
			explicit.Close()
			return queryErr
		}
		explicit.Close()
		retained, queryErr := q.QueryContext(c, `SELECT member_id,amount_cents FROM expense_retained_overpayments WHERE expense_id=$1 ORDER BY position`, x.ID)
		if queryErr != nil {
			return queryErr
		}
		for retained.Next() {
			var payer ExpensePayer
			if queryErr = retained.Scan(&payer.MemberID, &payer.AmountCents); queryErr != nil {
				retained.Close()
				return queryErr
			}
			x.RetainedOverpayments = append(x.RetainedOverpayments, payer)
		}
		if queryErr = retained.Err(); queryErr != nil {
			retained.Close()
			return queryErr
		}
		retained.Close()
		if len(x.Payers) == 0 {
			x.Payers = []ExpensePayer{{MemberID: x.PayerID, AmountCents: x.AmountCents}}
		}
		allocatedAmount, allocationErr := expenseAllocatedAmount(x)
		if allocationErr != nil {
			return allocationErr
		}
		x.PaidAmountCents = allocatedAmount
		x.OverpaymentCents = allocatedAmount - x.AmountCents
		if x.SplitMode == "exact" {
			x.ConsumptionShares, e = validateExactShares(x.ExplicitShares, x.ParticipantIDs, x.AmountCents)
			if e != nil {
				return e
			}
		}
		x.Shares, e = sharesForExpense(x, *g, allocatedAmount)
		if e != nil {
			return e
		}
		if x.SplitOverpayment && x.OverpaymentCents > 0 && x.ConsumptionShares != nil {
			x.OverpaymentShares = make(map[string]int64, len(x.Shares))
			for id, share := range x.Shares {
				x.OverpaymentShares[id] = share - x.ConsumptionShares[id]
			}
		}
		g.Expenses = append(g.Expenses, x)
	}
	ss, e := q.QueryContext(c, `SELECT id,from_member_id,to_member_id,amount_cents,created_at FROM settlements WHERE group_id=$1 ORDER BY created_at DESC,id DESC`, g.ID)
	if e != nil {
		return e
	}
	defer ss.Close()
	for ss.Next() {
		var x Settlement
		if e = ss.Scan(&x.ID, &x.FromMemberID, &x.ToMemberID, &x.AmountCents, &x.CreatedAt); e != nil {
			return e
		}
		g.Settlements = append(g.Settlements, x)
	}
	if err := ss.Err(); err != nil {
		return err
	}
	g.Balances, e = calculateBalances(*g)
	if e != nil {
		return e
	}
	g.PaymentRelations = PaymentRelations(*g)
	return nil
}

func (r *Repository) role(c context.Context, userID, groupID string) (string, error) {
	var role string
	err := r.db.QueryRowContext(c, `SELECT role FROM group_members WHERE group_id=$1 AND user_id=$2 AND removed_at IS NULL AND accepted AND declined_at IS NULL ORDER BY CASE role WHEN 'owner' THEN 0 ELSE 1 END LIMIT 1`, groupID, userID).Scan(&role)
	if errors.Is(err, sql.ErrNoRows) {
		return "", ErrNotFound
	}
	return role, err
}

func (r *Repository) requireRole(c context.Context, userID, groupID, required string) error {
	role, err := r.role(c, userID, groupID)
	if err != nil {
		return err
	}
	if role != required {
		return ErrNotFound
	}
	return nil
}

func newID(p string) (string, error) {
	b := make([]byte, 12)
	_, e := rand.Read(b)
	return p + "_" + hex.EncodeToString(b), e
}
func emojiFor(s string) string {
	e := []string{"🍜", "🏠", "🎁", "🏖️", "🎮", "🚗"}
	n := 0
	for _, c := range s {
		n += int(c)
	}
	return e[n%len(e)]
}
