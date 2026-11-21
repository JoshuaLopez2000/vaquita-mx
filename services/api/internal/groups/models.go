package groups

import (
	"database/sql"
	"errors"
	"time"
)

const CurrentUserID = "me"

const (
	RoleOwner  = "owner"
	RoleMember = "member"

	// PercentageBasisPointsTotal is 100.00% expressed in integer basis points
	// (0.01% precision, 100 bps = 1.00%).
	PercentageBasisPointsTotal = 10000

	// MaxReversalReasonLength bounds audit reversal reasons in UTF-8 runes.
	MaxReversalReasonLength = 500
)

var (
	ErrInvalid         = errors.New("invalid group data")
	ErrOverpayment     = errors.New("settlement exceeds outstanding balance")
	ErrNotFound        = errors.New("group not found")
	ErrSyncConflict    = errors.New("offline sync conflicts with existing data")
	ErrAlreadyReversed = errors.New("financial record already reversed")
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
	ID                   string           `json:"id"`
	Description          string           `json:"description"`
	AmountCents          int64            `json:"amount_cents"`
	PayerID              string           `json:"payer_id"`
	Payers               []ExpensePayer   `json:"payers"`
	ParticipantIDs       []string         `json:"participant_ids"`
	SplitMode            string           `json:"split_mode"`
	Shares               map[string]int64 `json:"shares"`
	Percentages          map[string]int   `json:"percentages,omitempty"`
	PaidAmountCents      int64            `json:"paid_amount_cents"`
	ConsumptionShares    map[string]int64 `json:"consumption_shares,omitempty"`
	OverpaymentCents     int64            `json:"overpayment_cents"`
	OverpaymentShares    map[string]int64 `json:"overpayment_shares,omitempty"`
	SplitOverpayment     bool             `json:"split_overpayment"`
	RetainedOverpayments []ExpensePayer   `json:"retained_overpayments,omitempty"`
	ReplacesExpenseID    string           `json:"replaces_expense_id,omitempty"`
	ExplicitShares       []ExpenseShare   `json:"-"`
	CreatedAt            time.Time        `json:"created_at"`
}
type ExpensePayer struct {
	MemberID    string `json:"member_id"`
	AmountCents int64  `json:"amount_cents"`
}

// ExpenseShare is an explicit, ordered allocation of an expense to a member.
// It is used for exact splits and for persisted final shares computed for
// percentage splits; payer contributions remain a separate fact about who
// paid the expense.
type ExpenseShare struct {
	MemberID    string `json:"member_id"`
	AmountCents int64  `json:"amount_cents"`
}

// ExpensePercentage is an explicit fixed-point percentage allocation in basis
// points (100 bps = 1.00%, sum must equal PercentageBasisPointsTotal).
type ExpensePercentage struct {
	MemberID      string `json:"member_id"`
	PercentageBps int    `json:"percentage_bps"`
}
type Settlement struct {
	ID                   string    `json:"id"`
	FromMemberID         string    `json:"from_member_id"`
	ToMemberID           string    `json:"to_member_id"`
	AmountCents          int64     `json:"amount_cents"`
	ReplacesSettlementID string    `json:"replaces_settlement_id,omitempty"`
	CreatedAt            time.Time `json:"created_at"`
}

// ExpenseReversal is an immutable compensating entry that negates one posted
// expense exactly once while keeping the original expense visible in history.
type ExpenseReversal struct {
	ID                string    `json:"id"`
	OriginalExpenseID string    `json:"original_expense_id"`
	ActorUserID       string    `json:"actor_user_id,omitempty"`
	ActorMemberID     string    `json:"actor_member_id"`
	Reason            string    `json:"reason"`
	CreatedAt         time.Time `json:"created_at"`
}

// SettlementReversal is an immutable compensating entry that negates one
// posted settlement exactly once while keeping the original settlement visible
// in history.
type SettlementReversal struct {
	ID                   string    `json:"id"`
	OriginalSettlementID string    `json:"original_settlement_id"`
	ActorUserID          string    `json:"actor_user_id,omitempty"`
	ActorMemberID        string    `json:"actor_member_id"`
	Reason               string    `json:"reason"`
	CreatedAt            time.Time `json:"created_at"`
}

type ReverseRecordInput struct {
	Reason string `json:"reason"`
}

type Group struct {
	ID                   string               `json:"id"`
	Name                 string               `json:"name"`
	Emoji                string               `json:"emoji"`
	Visibility           string               `json:"visibility"`
	SalarySplitEnabled   bool                 `json:"salary_split_enabled"`
	SalarySplitAvailable bool                 `json:"salary_split_available"`
	Members              []Member             `json:"members"`
	Expenses             []Expense            `json:"expenses"`
	ExpenseReversals     []ExpenseReversal    `json:"expense_reversals"`
	Settlements          []Settlement         `json:"settlements"`
	SettlementReversals  []SettlementReversal `json:"settlement_reversals"`
	Balances             map[string]int64     `json:"balances"`
	PaymentRelations     []PaymentRelation    `json:"payment_relations"`
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
	Description       string              `json:"description"`
	AmountCents       int64               `json:"amount_cents"`
	PayerID           string              `json:"payer_id"`
	Payers            []ExpensePayer      `json:"payers"`
	ParticipantIDs    []string            `json:"participant_ids"`
	SplitMode         string              `json:"split_mode"`
	Shares            []ExpenseShare      `json:"shares"`
	Percentages       []ExpensePercentage `json:"percentages,omitempty"`
	SplitOverpayment  *bool               `json:"split_overpayment"`
	ReplacesExpenseID string              `json:"replaces_expense_id,omitempty"`
}
type Repository struct{ db *sql.DB }
type Invitation struct {
	Group  Group  `json:"group"`
	Member Member `json:"member"`
}

type OfflineSyncGroupInput struct {
	ID                  string                               `json:"id"`
	Name                string                               `json:"name"`
	Emoji               string                               `json:"emoji"`
	Visibility          string                               `json:"visibility"`
	SalarySplitEnabled  bool                                 `json:"salary_split_enabled"`
	Members             []OfflineSyncMemberInput             `json:"members"`
	Expenses            []OfflineSyncExpenseInput            `json:"expenses"`
	ExpenseReversals    []OfflineSyncExpenseReversalInput    `json:"expense_reversals,omitempty"`
	Settlements         []OfflineSyncSettlementInput         `json:"settlements"`
	SettlementReversals []OfflineSyncSettlementReversalInput `json:"settlement_reversals,omitempty"`
}

type OfflineSyncMemberInput struct {
	ID            string `json:"id"`
	Name          string `json:"name"`
	Phone         string `json:"phone"`
	SalarySharing bool   `json:"salary_sharing"`
	Active        bool   `json:"active"`
}

type OfflineSyncExpenseInput struct {
	ID                string           `json:"id"`
	Description       string           `json:"description"`
	AmountCents       int64            `json:"amount_cents"`
	PayerID           string           `json:"payer_id"`
	Payers            []ExpensePayer   `json:"payers"`
	ParticipantIDs    []string         `json:"participant_ids"`
	SplitMode         string           `json:"split_mode"`
	Shares            map[string]int64 `json:"shares"`
	Percentages       map[string]int   `json:"percentages,omitempty"`
	SplitOverpayment  bool             `json:"split_overpayment"`
	ReplacesExpenseID string           `json:"replaces_expense_id,omitempty"`
	CreatedAt         time.Time        `json:"created_at"`
}

type OfflineSyncExpenseReversalInput struct {
	ID                string    `json:"id"`
	OriginalExpenseID string    `json:"original_expense_id"`
	ActorMemberID     string    `json:"actor_member_id"`
	Reason            string    `json:"reason"`
	CreatedAt         time.Time `json:"created_at"`
}

type OfflineSyncSettlementInput struct {
	ID                   string    `json:"id"`
	FromMemberID         string    `json:"from_member_id"`
	ToMemberID           string    `json:"to_member_id"`
	AmountCents          int64     `json:"amount_cents"`
	ReplacesSettlementID string    `json:"replaces_settlement_id,omitempty"`
	CreatedAt            time.Time `json:"created_at"`
}

type OfflineSyncSettlementReversalInput struct {
	ID                   string    `json:"id"`
	OriginalSettlementID string    `json:"original_settlement_id"`
	ActorMemberID        string    `json:"actor_member_id"`
	Reason               string    `json:"reason"`
	CreatedAt            time.Time `json:"created_at"`
}

type OfflineSyncGroupResult struct {
	LocalGroupID  string `json:"local_group_id"`
	RemoteGroupID string `json:"remote_group_id"`
}
