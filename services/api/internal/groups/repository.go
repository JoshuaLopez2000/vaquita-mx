package groups

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

const CurrentUserID = "me"

var (
	ErrInvalid  = errors.New("invalid group data")
	ErrNotFound = errors.New("group not found")
)

type Member struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type Expense struct {
	ID             string    `json:"id"`
	Description    string    `json:"description"`
	AmountCents    int64     `json:"amount_cents"`
	PayerID        string    `json:"payer_id"`
	ParticipantIDs []string  `json:"participant_ids"`
	CreatedAt      time.Time `json:"created_at"`
}

type Settlement struct {
	ID           string    `json:"id"`
	FromMemberID string    `json:"from_member_id"`
	ToMemberID   string    `json:"to_member_id"`
	AmountCents  int64     `json:"amount_cents"`
	CreatedAt    time.Time `json:"created_at"`
}

type Group struct {
	ID          string       `json:"id"`
	Name        string       `json:"name"`
	Emoji       string       `json:"emoji"`
	Members     []Member     `json:"members"`
	Expenses    []Expense    `json:"expenses"`
	Settlements []Settlement `json:"settlements"`
}

type CreateGroupInput struct {
	Name        string   `json:"name"`
	MemberNames []string `json:"member_names"`
}

type AddExpenseInput struct {
	Description    string   `json:"description"`
	AmountCents    int64    `json:"amount_cents"`
	PayerID        string   `json:"payer_id"`
	ParticipantIDs []string `json:"participant_ids"`
}

type Repository struct {
	db *sql.DB
}

func Open(ctx context.Context, databaseURL string) (*Repository, error) {
	db, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}
	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(30 * time.Minute)

	var pingErr error
	for attempt := 0; attempt < 12; attempt++ {
		pingErr = db.PingContext(ctx)
		if pingErr == nil {
			return &Repository{db: db}, nil
		}
		select {
		case <-ctx.Done():
			db.Close()
			return nil, ctx.Err()
		case <-time.After(time.Second):
		}
	}
	db.Close()
	return nil, fmt.Errorf("ping database: %w", pingErr)
}

func (r *Repository) Close() error { return r.db.Close() }

func (r *Repository) Ping(ctx context.Context) error { return r.db.PingContext(ctx) }

func (r *Repository) Migrate(ctx context.Context) error {
	_, err := r.db.ExecContext(ctx, schema)
	if err != nil {
		return fmt.Errorf("apply schema: %w", err)
	}
	return r.seed(ctx)
}

func (r *Repository) List(ctx context.Context) ([]Group, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT id, name, emoji FROM expense_groups ORDER BY created_at DESC`)
	if err != nil {
		return nil, fmt.Errorf("list groups: %w", err)
	}
	defer rows.Close()

	result := make([]Group, 0)
	for rows.Next() {
		var group Group
		if err := rows.Scan(&group.ID, &group.Name, &group.Emoji); err != nil {
			return nil, fmt.Errorf("scan group: %w", err)
		}
		result = append(result, group)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate groups: %w", err)
	}
	for i := range result {
		if err := r.loadRelations(ctx, &result[i]); err != nil {
			return nil, err
		}
	}
	return result, nil
}

func (r *Repository) Get(ctx context.Context, id string) (Group, error) {
	var group Group
	err := r.db.QueryRowContext(
		ctx,
		`SELECT id, name, emoji FROM expense_groups WHERE id = $1`,
		id,
	).Scan(&group.ID, &group.Name, &group.Emoji)
	if errors.Is(err, sql.ErrNoRows) {
		return Group{}, ErrNotFound
	}
	if err != nil {
		return Group{}, fmt.Errorf("get group: %w", err)
	}
	if err := r.loadRelations(ctx, &group); err != nil {
		return Group{}, err
	}
	return group, nil
}

func (r *Repository) Create(ctx context.Context, input CreateGroupInput) (Group, error) {
	input.Name = strings.TrimSpace(input.Name)
	if len(input.Name) < 2 || len(input.MemberNames) == 0 {
		return Group{}, ErrInvalid
	}
	id, err := newID("group")
	if err != nil {
		return Group{}, err
	}
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return Group{}, fmt.Errorf("begin create group: %w", err)
	}
	defer tx.Rollback()

	emoji := emojiFor(input.Name)
	if _, err := tx.ExecContext(ctx, `INSERT INTO expense_groups (id, name, emoji) VALUES ($1, $2, $3)`, id, input.Name, emoji); err != nil {
		return Group{}, fmt.Errorf("insert group: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO group_members (group_id, member_id, position) VALUES ($1, $2, 0)`, id, CurrentUserID); err != nil {
		return Group{}, fmt.Errorf("add current user: %w", err)
	}
	position := 1
	for _, rawName := range input.MemberNames {
		name := strings.TrimSpace(rawName)
		if name == "" || strings.EqualFold(name, "you") {
			continue
		}
		memberID, idErr := newID("member")
		if idErr != nil {
			return Group{}, idErr
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO members (id, name) VALUES ($1, $2)`, memberID, name); err != nil {
			return Group{}, fmt.Errorf("insert member: %w", err)
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO group_members (group_id, member_id, position) VALUES ($1, $2, $3)`, id, memberID, position); err != nil {
			return Group{}, fmt.Errorf("add group member: %w", err)
		}
		position++
	}
	if position == 1 {
		return Group{}, ErrInvalid
	}
	if err := tx.Commit(); err != nil {
		return Group{}, fmt.Errorf("commit group: %w", err)
	}
	return r.Get(ctx, id)
}

func (r *Repository) AddExpense(ctx context.Context, groupID string, input AddExpenseInput) (Group, error) {
	input.Description = strings.TrimSpace(input.Description)
	if input.Description == "" || input.AmountCents <= 0 || input.PayerID == "" || len(input.ParticipantIDs) == 0 {
		return Group{}, ErrInvalid
	}
	group, err := r.Get(ctx, groupID)
	if err != nil {
		return Group{}, err
	}
	memberIDs := make(map[string]bool, len(group.Members))
	for _, member := range group.Members {
		memberIDs[member.ID] = true
	}
	if !memberIDs[input.PayerID] {
		return Group{}, ErrInvalid
	}
	for _, participantID := range input.ParticipantIDs {
		if !memberIDs[participantID] {
			return Group{}, ErrInvalid
		}
	}

	expenseID, err := newID("expense")
	if err != nil {
		return Group{}, err
	}
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return Group{}, fmt.Errorf("begin add expense: %w", err)
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `INSERT INTO expenses (id, group_id, description, amount_cents, payer_id) VALUES ($1, $2, $3, $4, $5)`, expenseID, groupID, input.Description, input.AmountCents, input.PayerID); err != nil {
		return Group{}, fmt.Errorf("insert expense: %w", err)
	}
	seen := make(map[string]bool)
	for position, participantID := range input.ParticipantIDs {
		if seen[participantID] {
			return Group{}, ErrInvalid
		}
		seen[participantID] = true
		if _, err := tx.ExecContext(ctx, `INSERT INTO expense_participants (expense_id, member_id, position) VALUES ($1, $2, $3)`, expenseID, participantID, position); err != nil {
			return Group{}, fmt.Errorf("insert participant: %w", err)
		}
	}
	if err := tx.Commit(); err != nil {
		return Group{}, fmt.Errorf("commit expense: %w", err)
	}
	return r.Get(ctx, groupID)
}

func (r *Repository) AddSettlement(ctx context.Context, groupID, memberID string) (Group, error) {
	group, err := r.Get(ctx, groupID)
	if err != nil {
		return Group{}, err
	}
	if memberID == CurrentUserID {
		return Group{}, ErrInvalid
	}
	balance, ok := Balances(group)[memberID]
	if !ok || balance == 0 {
		return Group{}, ErrInvalid
	}
	fromID, toID := CurrentUserID, memberID
	if balance < 0 {
		fromID, toID = memberID, CurrentUserID
		balance = -balance
	}
	id, err := newID("settlement")
	if err != nil {
		return Group{}, err
	}
	_, err = r.db.ExecContext(ctx, `INSERT INTO settlements (id, group_id, from_member_id, to_member_id, amount_cents) VALUES ($1, $2, $3, $4, $5)`, id, groupID, fromID, toID, balance)
	if err != nil {
		return Group{}, fmt.Errorf("insert settlement: %w", err)
	}
	return r.Get(ctx, groupID)
}

func Balances(group Group) map[string]int64 {
	result := make(map[string]int64, len(group.Members))
	for _, member := range group.Members {
		result[member.ID] = 0
	}
	for _, expense := range group.Expenses {
		result[expense.PayerID] += expense.AmountCents
		count := int64(len(expense.ParticipantIDs))
		if count == 0 {
			continue
		}
		base, remainder := expense.AmountCents/count, expense.AmountCents%count
		for _, participantID := range expense.ParticipantIDs {
			share := base
			if remainder > 0 {
				share++
				remainder--
			}
			result[participantID] -= share
		}
	}
	for _, settlement := range group.Settlements {
		result[settlement.FromMemberID] += settlement.AmountCents
		result[settlement.ToMemberID] -= settlement.AmountCents
	}
	return result
}

func (r *Repository) loadRelations(ctx context.Context, group *Group) error {
	group.Members = make([]Member, 0)
	group.Expenses = make([]Expense, 0)
	group.Settlements = make([]Settlement, 0)
	memberRows, err := r.db.QueryContext(ctx, `SELECT m.id, m.name FROM group_members gm JOIN members m ON m.id = gm.member_id WHERE gm.group_id = $1 ORDER BY gm.position`, group.ID)
	if err != nil {
		return fmt.Errorf("list members: %w", err)
	}
	for memberRows.Next() {
		var member Member
		if err := memberRows.Scan(&member.ID, &member.Name); err != nil {
			memberRows.Close()
			return fmt.Errorf("scan member: %w", err)
		}
		group.Members = append(group.Members, member)
	}
	if err := memberRows.Close(); err != nil {
		return err
	}

	expenseRows, err := r.db.QueryContext(ctx, `SELECT id, description, amount_cents, payer_id, created_at FROM expenses WHERE group_id = $1 ORDER BY created_at DESC, id DESC`, group.ID)
	if err != nil {
		return fmt.Errorf("list expenses: %w", err)
	}
	for expenseRows.Next() {
		var expense Expense
		if err := expenseRows.Scan(&expense.ID, &expense.Description, &expense.AmountCents, &expense.PayerID, &expense.CreatedAt); err != nil {
			expenseRows.Close()
			return fmt.Errorf("scan expense: %w", err)
		}
		participantRows, queryErr := r.db.QueryContext(ctx, `SELECT member_id FROM expense_participants WHERE expense_id = $1 ORDER BY position`, expense.ID)
		if queryErr != nil {
			expenseRows.Close()
			return fmt.Errorf("list participants: %w", queryErr)
		}
		for participantRows.Next() {
			var participantID string
			if err := participantRows.Scan(&participantID); err != nil {
				participantRows.Close()
				expenseRows.Close()
				return fmt.Errorf("scan participant: %w", err)
			}
			expense.ParticipantIDs = append(expense.ParticipantIDs, participantID)
		}
		participantRows.Close()
		group.Expenses = append(group.Expenses, expense)
	}
	if err := expenseRows.Close(); err != nil {
		return err
	}

	settlementRows, err := r.db.QueryContext(ctx, `SELECT id, from_member_id, to_member_id, amount_cents, created_at FROM settlements WHERE group_id = $1 ORDER BY created_at DESC, id DESC`, group.ID)
	if err != nil {
		return fmt.Errorf("list settlements: %w", err)
	}
	defer settlementRows.Close()
	for settlementRows.Next() {
		var settlement Settlement
		if err := settlementRows.Scan(&settlement.ID, &settlement.FromMemberID, &settlement.ToMemberID, &settlement.AmountCents, &settlement.CreatedAt); err != nil {
			return fmt.Errorf("scan settlement: %w", err)
		}
		group.Settlements = append(group.Settlements, settlement)
	}
	return settlementRows.Err()
}

func (r *Repository) seed(ctx context.Context) error {
	var count int
	if err := r.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM expense_groups`).Scan(&count); err != nil {
		return fmt.Errorf("count groups: %w", err)
	}
	if count > 0 {
		return nil
	}
	_, err := r.db.ExecContext(ctx, seedData)
	if err != nil {
		return fmt.Errorf("seed database: %w", err)
	}
	return nil
}

func newID(prefix string) (string, error) {
	value := make([]byte, 12)
	if _, err := rand.Read(value); err != nil {
		return "", fmt.Errorf("generate id: %w", err)
	}
	return prefix + "_" + hex.EncodeToString(value), nil
}

func emojiFor(name string) string {
	emojis := []string{"🍜", "🏠", "🎁", "🏖️", "🎮", "🚗"}
	var total int
	for _, value := range name {
		total += int(value)
	}
	return emojis[total%len(emojis)]
}

const schema = `
CREATE TABLE IF NOT EXISTS members (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL CHECK (length(trim(name)) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS expense_groups (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL CHECK (length(trim(name)) > 0),
    emoji TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS group_members (
    group_id TEXT NOT NULL REFERENCES expense_groups(id) ON DELETE CASCADE,
    member_id TEXT NOT NULL REFERENCES members(id),
    position INTEGER NOT NULL,
    PRIMARY KEY (group_id, member_id)
);
CREATE TABLE IF NOT EXISTS expenses (
    id TEXT PRIMARY KEY,
    group_id TEXT NOT NULL REFERENCES expense_groups(id) ON DELETE CASCADE,
    description TEXT NOT NULL,
    amount_cents BIGINT NOT NULL CHECK (amount_cents > 0),
    payer_id TEXT NOT NULL REFERENCES members(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS expenses_group_created_idx ON expenses(group_id, created_at DESC);
CREATE TABLE IF NOT EXISTS expense_participants (
    expense_id TEXT NOT NULL REFERENCES expenses(id) ON DELETE CASCADE,
    member_id TEXT NOT NULL REFERENCES members(id),
    position INTEGER NOT NULL,
    PRIMARY KEY (expense_id, member_id)
);
CREATE TABLE IF NOT EXISTS settlements (
    id TEXT PRIMARY KEY,
    group_id TEXT NOT NULL REFERENCES expense_groups(id) ON DELETE CASCADE,
    from_member_id TEXT NOT NULL REFERENCES members(id),
    to_member_id TEXT NOT NULL REFERENCES members(id),
    amount_cents BIGINT NOT NULL CHECK (amount_cents > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (from_member_id <> to_member_id)
);
CREATE INDEX IF NOT EXISTS settlements_group_created_idx ON settlements(group_id, created_at DESC);
`

const seedData = `
INSERT INTO members (id, name) VALUES
    ('me', 'You'), ('ana', 'Ana'), ('diego', 'Diego'), ('sofia', 'Sofía'), ('marco', 'Marco');
INSERT INTO expense_groups (id, name, emoji, created_at) VALUES
    ('cdmx-weekend', 'Weekend in CDMX', '🌮', now()),
    ('apartment', 'Apartment', '🏠', now() - interval '1 minute');
INSERT INTO group_members (group_id, member_id, position) VALUES
    ('cdmx-weekend', 'me', 0), ('cdmx-weekend', 'ana', 1), ('cdmx-weekend', 'diego', 2), ('cdmx-weekend', 'sofia', 3),
    ('apartment', 'me', 0), ('apartment', 'marco', 1);
INSERT INTO expenses (id, group_id, description, amount_cents, payer_id, created_at) VALUES
    ('expense_tacos', 'cdmx-weekend', 'Tacos and drinks', 128000, 'me', now() - interval '3 hours'),
    ('expense_museum', 'cdmx-weekend', 'Museum tickets', 36000, 'ana', now() - interval '1 day'),
    ('expense_internet', 'apartment', 'Internet — September', 64900, 'marco', now() - interval '4 days');
INSERT INTO expense_participants (expense_id, member_id, position) VALUES
    ('expense_tacos', 'me', 0), ('expense_tacos', 'ana', 1), ('expense_tacos', 'diego', 2), ('expense_tacos', 'sofia', 3),
    ('expense_museum', 'me', 0), ('expense_museum', 'ana', 1), ('expense_museum', 'diego', 2),
    ('expense_internet', 'me', 0), ('expense_internet', 'marco', 1);
`
