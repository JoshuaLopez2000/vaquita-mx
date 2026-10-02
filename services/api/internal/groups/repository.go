package groups

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/auth"
	_ "github.com/jackc/pgx/v5/stdlib"
	"math"
	"math/big"
	"strings"
	"time"
)

const CurrentUserID = "me"

const (
	RoleOwner  = "owner"
	RoleMember = "member"
)

var (
	ErrInvalid  = errors.New("invalid group data")
	ErrNotFound = errors.New("group not found")
)

type Member struct {
	ID            string `json:"id"`
	UserID        string `json:"user_id,omitempty"`
	Role          string `json:"role"`
	Name          string `json:"name"`
	Phone         string `json:"phone,omitempty"`
	Active        bool   `json:"active"`
	SalarySharing bool   `json:"salary_sharing"`
	Accepted      bool   `json:"accepted"`
	SalaryCents   int64  `json:"-"`
}
type UnpaidBalance struct {
	Member      Member `json:"member"`
	AmountCents int64  `json:"amount_cents"`
}

// PaymentRelation is a deterministic, derived instruction for settling a
// group's current net balances. It is not a ledger entry.
type PaymentRelation struct {
	FromMemberID string `json:"from_member_id"`
	ToMemberID   string `json:"to_member_id"`
	AmountCents  int64  `json:"amount_cents"`
}
type ContactStatus = UnpaidBalance
type Expense struct {
	ID             string           `json:"id"`
	Description    string           `json:"description"`
	AmountCents    int64            `json:"amount_cents"`
	PayerID        string           `json:"payer_id"`
	ParticipantIDs []string         `json:"participant_ids"`
	SplitMode      string           `json:"split_mode"`
	Shares         map[string]int64 `json:"shares"`
	CreatedAt      time.Time        `json:"created_at"`
}
type Settlement struct {
	ID           string    `json:"id"`
	FromMemberID string    `json:"from_member_id"`
	ToMemberID   string    `json:"to_member_id"`
	AmountCents  int64     `json:"amount_cents"`
	CreatedAt    time.Time `json:"created_at"`
}
type Group struct {
	ID                   string            `json:"id"`
	Name                 string            `json:"name"`
	Emoji                string            `json:"emoji"`
	Visibility           string            `json:"visibility"`
	SalarySplitEnabled   bool              `json:"salary_split_enabled"`
	SalarySplitAvailable bool              `json:"salary_split_available"`
	Members              []Member          `json:"members"`
	Expenses             []Expense         `json:"expenses"`
	Settlements          []Settlement      `json:"settlements"`
	Balances             map[string]int64  `json:"balances"`
	PaymentRelations     []PaymentRelation `json:"payment_relations"`
}
type MemberInput struct {
	Name  string `json:"name"`
	Phone string `json:"phone"`
}
type CreateGroupInput struct {
	Name               string        `json:"name"`
	Emoji              string        `json:"emoji"`
	Visibility         string        `json:"visibility"`
	SalarySplitEnabled bool          `json:"salary_split_enabled"`
	Members            []MemberInput `json:"members"`
	MemberNames        []string      `json:"member_names"`
}
type UpdateGroupInput struct {
	Name               string `json:"name"`
	Emoji              string `json:"emoji"`
	Visibility         string `json:"visibility"`
	SalarySplitEnabled *bool  `json:"salary_split_enabled"`
}
type UpdateMemberInput struct {
	Name          string `json:"name"`
	Phone         string `json:"phone"`
	SalarySharing *bool  `json:"salary_sharing"`
}
type AddExpenseInput struct {
	Description    string   `json:"description"`
	AmountCents    int64    `json:"amount_cents"`
	PayerID        string   `json:"payer_id"`
	ParticipantIDs []string `json:"participant_ids"`
	SplitMode      string   `json:"split_mode"`
}
type Repository struct{ db *sql.DB }
type Invitation struct {
	Group  Group  `json:"group"`
	Member Member `json:"member"`
}

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
		if *in.SalarySplitEnabled && (g.Visibility != "shared" || !r.salaryReady(c, id)) {
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
func (r *Repository) AddExpense(c context.Context, u, gid string, in AddExpenseInput) (Group, error) {
	g, e := r.Get(c, u, gid)
	if e != nil {
		return g, e
	}
	in.Description = strings.TrimSpace(in.Description)
	if in.Description == "" || in.AmountCents <= 0 || len(in.ParticipantIDs) == 0 {
		return g, ErrInvalid
	}
	if in.SplitMode == "" {
		in.SplitMode = "equal"
	}
	if in.SplitMode != "equal" && in.SplitMode != "salary" || in.SplitMode == "salary" && (!g.SalarySplitEnabled || !g.SalarySplitAvailable) {
		return g, ErrInvalid
	}
	ms := map[string]Member{}
	for _, m := range g.Members {
		if m.Active {
			ms[m.ID] = m
		}
	}
	if _, ok := ms[in.PayerID]; !ok {
		return g, ErrInvalid
	}
	seen := map[string]bool{}
	for _, id := range in.ParticipantIDs {
		m, ok := ms[id]
		if !ok || seen[id] || in.SplitMode == "salary" && !m.SalarySharing {
			return g, ErrInvalid
		}
		seen[id] = true
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
	_, e = t.ExecContext(c, `INSERT INTO expenses(id,group_id,description,amount_cents,payer_id,split_mode)VALUES($1,$2,$3,$4,$5,$6)`, id, gid, in.Description, in.AmountCents, in.PayerID, in.SplitMode)
	if e != nil {
		return g, e
	}
	for p, m := range in.ParticipantIDs {
		if _, e = t.ExecContext(c, `INSERT INTO expense_participants(expense_id,member_id,position)VALUES($1,$2,$3)`, id, m, p); e != nil {
			return g, e
		}
	}
	if e = t.Commit(); e != nil {
		return g, e
	}
	return r.Get(c, u, gid)
}
func (r *Repository) AddSettlement(c context.Context, u, g, id string) (Group, error) {
	x, e := r.Get(c, u, g)
	if e != nil {
		return x, e
	}
	var selfID string
	if e = r.db.QueryRowContext(c, `SELECT member_id FROM group_members WHERE group_id=$1 AND user_id=$2 AND removed_at IS NULL AND accepted AND declined_at IS NULL`, g, u).Scan(&selfID); e != nil {
		return x, ErrNotFound
	}
	if id == selfID {
		return x, ErrInvalid
	}
	var amount int64
	for _, relation := range x.PaymentRelations {
		if relation.FromMemberID == selfID && relation.ToMemberID == id {
			amount = relation.AmountCents
			break
		}
	}
	if amount == 0 {
		return x, ErrInvalid
	}
	sid, e := newID("settlement")
	if e != nil {
		return x, e
	}
	_, e = r.db.ExecContext(c, `INSERT INTO settlements(id,group_id,from_member_id,to_member_id,amount_cents)VALUES($1,$2,$3,$4,$5)`, sid, g, selfID, id, amount)
	if e != nil {
		return x, e
	}
	return r.Get(c, u, g)
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

func (r *Repository) salaryReady(c context.Context, groupID string) bool {
	var missing int
	e := r.db.QueryRowContext(c, `SELECT COUNT(*) FROM group_members x LEFT JOIN users u ON u.id=x.user_id WHERE x.group_id=$1 AND x.removed_at IS NULL AND (NOT x.accepted OR x.declined_at IS NOT NULL OR NOT x.salary_sharing OR COALESCE(u.salary_cents,0)<=0)`, groupID).Scan(&missing)
	return e == nil && missing == 0
}
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
		shares, err := split(expense.AmountCents, expense.ParticipantIDs, g, expense.SplitMode)
		if err != nil {
			return nil, err
		}
		for participantID, share := range shares {
			if err := add(participantID, expense.PayerID, share); err != nil {
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
		if _, exists := exact[e.PayerID]; !exists || e.AmountCents <= 0 {
			return nil, ErrInvalid
		}
		exact[e.PayerID].Add(exact[e.PayerID], big.NewInt(e.AmountCents))
		shares, err := split(e.AmountCents, e.ParticipantIDs, g, e.SplitMode)
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

func addCentavos(current, delta int64) (int64, error) {
	if (delta > 0 && current > math.MaxInt64-delta) || (delta < 0 && current < math.MinInt64-delta) {
		return 0, ErrInvalid
	}
	return current + delta, nil
}
func (r *Repository) load(c context.Context, g *Group) error {
	g.Members = make([]Member, 0)
	g.Expenses = make([]Expense, 0)
	g.Settlements = make([]Settlement, 0)
	rows, e := r.db.QueryContext(c, `SELECT m.id,COALESCE(x.user_id,''),x.role,m.name,COALESCE(m.phone,''),x.removed_at IS NULL,x.salary_sharing,x.accepted,COALESCE(u.salary_cents,0) FROM group_members x JOIN members m ON m.id=x.member_id LEFT JOIN users u ON u.id=x.user_id WHERE x.group_id=$1 ORDER BY x.position`, g.ID)
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
	g.SalarySplitAvailable = r.salaryReady(c, g.ID)
	es, e := r.db.QueryContext(c, `SELECT id,description,amount_cents,payer_id,split_mode,created_at FROM expenses WHERE group_id=$1 ORDER BY created_at DESC,id DESC`, g.ID)
	if e != nil {
		return e
	}
	for es.Next() {
		var x Expense
		if e = es.Scan(&x.ID, &x.Description, &x.AmountCents, &x.PayerID, &x.SplitMode, &x.CreatedAt); e != nil {
			es.Close()
			return e
		}
		ps, _ := r.db.QueryContext(c, `SELECT member_id FROM expense_participants WHERE expense_id=$1 ORDER BY position`, x.ID)
		for ps.Next() {
			var id string
			ps.Scan(&id)
			x.ParticipantIDs = append(x.ParticipantIDs, id)
		}
		ps.Close()
		x.Shares, e = split(x.AmountCents, x.ParticipantIDs, *g, x.SplitMode)
		if e != nil {
			es.Close()
			return e
		}
		g.Expenses = append(g.Expenses, x)
	}
	es.Close()
	ss, e := r.db.QueryContext(c, `SELECT id,from_member_id,to_member_id,amount_cents,created_at FROM settlements WHERE group_id=$1 ORDER BY created_at DESC,id DESC`, g.ID)
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
