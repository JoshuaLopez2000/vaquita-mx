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
)

var (
	ErrInvalid     = errors.New("invalid group data")
	ErrOverpayment = errors.New("settlement exceeds outstanding balance")
	ErrNotFound    = errors.New("group not found")
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
	PaidAmountCents      int64            `json:"paid_amount_cents"`
	ConsumptionShares    map[string]int64 `json:"consumption_shares,omitempty"`
	OverpaymentCents     int64            `json:"overpayment_cents"`
	OverpaymentShares    map[string]int64 `json:"overpayment_shares,omitempty"`
	SplitOverpayment     bool             `json:"split_overpayment"`
	RetainedOverpayments []ExpensePayer   `json:"retained_overpayments,omitempty"`
	ExplicitShares       []ExpenseShare   `json:"-"`
	CreatedAt            time.Time        `json:"created_at"`
}
type ExpensePayer struct {
	MemberID    string `json:"member_id"`
	AmountCents int64  `json:"amount_cents"`
}

// ExpenseShare is an explicit, ordered allocation of an expense to a member.
// It is used only with the exact split mode; payer contributions remain a
// separate fact about who paid the expense.
type ExpenseShare struct {
	MemberID    string `json:"member_id"`
	AmountCents int64  `json:"amount_cents"`
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
	Description      string         `json:"description"`
	AmountCents      int64          `json:"amount_cents"`
	PayerID          string         `json:"payer_id"`
	Payers           []ExpensePayer `json:"payers"`
	ParticipantIDs   []string       `json:"participant_ids"`
	SplitMode        string         `json:"split_mode"`
	Shares           []ExpenseShare `json:"shares"`
	SplitOverpayment *bool          `json:"split_overpayment"`
}
type Repository struct{ db *sql.DB }
type Invitation struct {
	Group  Group  `json:"group"`
	Member Member `json:"member"`
}
