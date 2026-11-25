package payments

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"

	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/groups"
)

const (
	OrientationAll      = "all"
	OrientationCreditor = "creditor"
	OrientationDebtor   = "debtor"

	DefaultListLimit = 20
	MaxListLimit     = 100
)

var (
	ErrNotFound            = errors.New("payment request not found")
	ErrIdempotencyConflict = errors.New("idempotency key conflicts with request")
	ErrInvalidEvent        = errors.New("invalid provider event")
)

// requestColumns is the canonical projection read wherever a stored request is
// mutated. Keep any lock-time update list in the same order.
const requestColumns = `id,group_id,creditor_member_id,debtor_member_id,amount_cents,currency,provider,status,payment_url,expires_at,correlation_id,COALESCE(settlement_id,''),COALESCE(provider_ref,''),reconcile_attempts,COALESCE(description,''),created_at,paid_at`

type Repository struct{ db *sql.DB }

func Open(ctx context.Context, url string) (*Repository, error) {
	db, err := sql.Open("pgx", url)
	if err != nil {
		return nil, err
	}
	if err := db.PingContext(ctx); err != nil {
		_ = db.Close()
		return nil, err
	}
	return &Repository{db: db}, nil
}

func (r *Repository) Close() error { return r.db.Close() }

// StoredRequest includes only the normalized simulator fields. It never
// represents a bank transfer or provider credential.
type StoredRequest struct {
	PaymentRequest
	GroupID          string     `json:"group_id"`
	GroupName        string     `json:"group_name,omitempty"`
	GroupEmoji       string     `json:"group_emoji,omitempty"`
	DebtorMemberID   string     `json:"debtor_id"`
	DebtorName       string     `json:"debtor_name,omitempty"`
	CreditorMemberID string     `json:"creditor_id"`
	CreditorName     string     `json:"creditor_name,omitempty"`
	Description      string     `json:"description,omitempty"`
	Role             string     `json:"role,omitempty"`
	SettlementID     string     `json:"settlement_id,omitempty"`
	CreatedAt        time.Time  `json:"created_at,omitempty"`
	PaidAt           *time.Time `json:"paid_at,omitempty"`
	Attempts         int        `json:"-"`
}

type ListFilter struct {
	Status      string
	Orientation string
	GroupID     string
	Limit       int
	Cursor      string
}

type ListPage struct {
	Requests   []StoredRequest `json:"payment_requests"`
	NextCursor string          `json:"next_cursor,omitempty"`
}

func (r *Repository) FindIdempotent(ctx context.Context, userID, key, hash string) (StoredRequest, bool, error) {
	stored, err := r.read(ctx, r.db, `SELECT `+requestColumns+` FROM payment_requests WHERE requester_user_id=$1 AND idempotency_key=$2`, userID, key)
	if errors.Is(err, sql.ErrNoRows) {
		return StoredRequest{}, false, nil
	}
	if err != nil {
		return StoredRequest{}, false, err
	}
	var recordedHash string
	err = r.db.QueryRowContext(ctx, `SELECT payload_hash FROM payment_requests WHERE requester_user_id=$1 AND idempotency_key=$2`, userID, key).Scan(&recordedHash)
	if err != nil {
		return StoredRequest{}, false, err
	}
	if recordedHash != hash {
		return StoredRequest{}, true, ErrIdempotencyConflict
	}
	return stored, true, nil
}

func (r *Repository) Create(ctx context.Context, userID, key, hash, creditorMemberID string, result PaymentRequest, input CreateRequest) (StoredRequest, bool, error) {
	reconcileAfter := time.Now().UTC().Add(reconcileGrace)
	description := strings.TrimSpace(input.Description)
	createdAt := time.Now().UTC()
	_, err := r.db.ExecContext(ctx, `INSERT INTO payment_requests(id,group_id,creditor_member_id,debtor_member_id,requester_user_id,amount_cents,currency,provider,status,payment_url,correlation_id,expires_at,idempotency_key,payload_hash,provider_ref,reconcile_after,description,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18)`, result.ID, input.GroupID, creditorMemberID, input.DebtorID, userID, input.AmountCents, input.Currency, result.Provider, result.Status, result.PaymentURL, result.CorrelationID, result.ExpiresAt, key, hash, result.ProviderRef, reconcileAfter, description, createdAt)
	if err == nil {
		return StoredRequest{
			PaymentRequest:   result,
			GroupID:          input.GroupID,
			DebtorMemberID:   input.DebtorID,
			CreditorMemberID: creditorMemberID,
			Description:      description,
			Role:             OrientationCreditor,
			CreatedAt:        createdAt,
		}, true, nil
	}
	if !isUniqueViolation(err) {
		return StoredRequest{}, false, err
	}
	stored, found, findErr := r.FindIdempotent(ctx, userID, key, hash)
	if findErr != nil {
		return StoredRequest{}, false, findErr
	}
	if !found {
		return StoredRequest{}, false, err
	}
	return stored, false, nil
}

// List returns cursor-paginated payment requests visible to userID, scoped
// strictly to groups where userID has an active accepted membership and to
// requests where userID is either the creditor or the debtor.
func (r *Repository) List(ctx context.Context, userID string, filter ListFilter) (ListPage, error) {
	orientation := strings.ToLower(strings.TrimSpace(filter.Orientation))
	if orientation == "" {
		orientation = OrientationAll
	}
	if orientation != OrientationAll && orientation != OrientationCreditor && orientation != OrientationDebtor {
		return ListPage{}, ErrInvalidRequest
	}
	statusFilter := strings.ToUpper(strings.TrimSpace(filter.Status))
	if statusFilter != "" &&
		statusFilter != string(StatusPending) &&
		statusFilter != string(StatusPaid) &&
		statusFilter != string(StatusExpired) &&
		statusFilter != string(StatusFailed) {
		return ListPage{}, ErrInvalidRequest
	}
	limit := filter.Limit
	if limit == 0 {
		limit = DefaultListLimit
	}
	if limit < 1 || limit > MaxListLimit {
		return ListPage{}, ErrInvalidRequest
	}
	groupID := strings.TrimSpace(filter.GroupID)
	if groupID != "" {
		var visible bool
		if err := r.db.QueryRowContext(ctx, `
SELECT EXISTS(
  SELECT 1
  FROM group_members gm
  JOIN expense_groups g ON g.id = gm.group_id
  WHERE gm.group_id = $1 AND gm.user_id = $2
    AND gm.removed_at IS NULL AND gm.accepted AND gm.declined_at IS NULL
    AND (gm.role = 'owner' OR g.visibility = 'shared')
)`, groupID, userID).Scan(&visible); err != nil {
			return ListPage{}, err
		}
		if !visible {
			return ListPage{}, ErrNotFound
		}
	}

	var cursorTime time.Time
	var cursorID string
	hasCursor := false
	if strings.TrimSpace(filter.Cursor) != "" {
		var err error
		cursorTime, cursorID, err = decodeCursor(filter.Cursor)
		if err != nil {
			return ListPage{}, ErrInvalidRequest
		}
		hasCursor = true
	}

	rows, err := r.db.QueryContext(ctx, `
SELECT
  pr.id,
  pr.group_id,
  g.name,
  g.emoji,
  pr.creditor_member_id,
  cm.name,
  pr.debtor_member_id,
  dm.name,
  pr.amount_cents,
  pr.currency,
  pr.provider,
  CASE WHEN pr.status = 'PENDING' AND pr.expires_at <= now() THEN 'EXPIRED' ELSE pr.status END AS effective_status,
  pr.payment_url,
  pr.expires_at,
  pr.correlation_id,
  COALESCE(pr.settlement_id, ''),
  COALESCE(pr.provider_ref, ''),
  pr.reconcile_attempts,
  COALESCE(pr.description, ''),
  CASE WHEN pr.creditor_member_id = gm.member_id THEN 'creditor' ELSE 'debtor' END AS role,
  pr.created_at,
  pr.paid_at
FROM payment_requests pr
JOIN expense_groups g ON g.id = pr.group_id
JOIN group_members gm ON gm.group_id = pr.group_id
  AND gm.user_id = $1
  AND gm.removed_at IS NULL
  AND gm.accepted
  AND gm.declined_at IS NULL
  AND (gm.role = 'owner' OR g.visibility = 'shared')
JOIN members cm ON cm.id = pr.creditor_member_id
JOIN members dm ON dm.id = pr.debtor_member_id
WHERE (
  ($2 = 'all' AND (pr.creditor_member_id = gm.member_id OR pr.debtor_member_id = gm.member_id))
  OR ($2 = 'creditor' AND pr.creditor_member_id = gm.member_id)
  OR ($2 = 'debtor' AND pr.debtor_member_id = gm.member_id)
)
AND ($3 = '' OR pr.group_id = $3)
AND ($4 = '' OR (CASE WHEN pr.status = 'PENDING' AND pr.expires_at <= now() THEN 'EXPIRED' ELSE pr.status END) = $4)
AND (NOT $5 OR (pr.created_at, pr.id) < ($6, $7))
ORDER BY pr.created_at DESC, pr.id DESC
LIMIT $8`, userID, orientation, groupID, statusFilter, hasCursor, cursorTime, cursorID, limit+1)
	if err != nil {
		return ListPage{}, err
	}
	defer rows.Close()

	items := make([]StoredRequest, 0, limit)
	for rows.Next() {
		item, scanErr := scanEnrichedRequest(rows)
		if scanErr != nil {
			return ListPage{}, scanErr
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return ListPage{}, err
	}

	page := ListPage{Requests: items}
	if len(items) > limit {
		page.Requests = items[:limit]
		last := page.Requests[limit-1]
		page.NextCursor = encodeCursor(last.CreatedAt, last.ID)
	}
	return page, nil
}

// Get returns a single payment request visible to userID (as creditor or debtor
// in a visible group). Hidden groups and other people's requests return ErrNotFound.
func (r *Repository) Get(ctx context.Context, userID, requestID string) (StoredRequest, error) {
	row := r.db.QueryRowContext(ctx, `
SELECT
  pr.id,
  pr.group_id,
  g.name,
  g.emoji,
  pr.creditor_member_id,
  cm.name,
  pr.debtor_member_id,
  dm.name,
  pr.amount_cents,
  pr.currency,
  pr.provider,
  CASE WHEN pr.status = 'PENDING' AND pr.expires_at <= now() THEN 'EXPIRED' ELSE pr.status END AS effective_status,
  pr.payment_url,
  pr.expires_at,
  pr.correlation_id,
  COALESCE(pr.settlement_id, ''),
  COALESCE(pr.provider_ref, ''),
  pr.reconcile_attempts,
  COALESCE(pr.description, ''),
  CASE WHEN pr.creditor_member_id = gm.member_id THEN 'creditor' ELSE 'debtor' END AS role,
  pr.created_at,
  pr.paid_at
FROM payment_requests pr
JOIN expense_groups g ON g.id = pr.group_id
JOIN group_members gm ON gm.group_id = pr.group_id
  AND gm.user_id = $1
  AND gm.removed_at IS NULL
  AND gm.accepted
  AND gm.declined_at IS NULL
  AND (gm.role = 'owner' OR g.visibility = 'shared')
JOIN members cm ON cm.id = pr.creditor_member_id
JOIN members dm ON dm.id = pr.debtor_member_id
WHERE pr.id = $2
  AND (pr.creditor_member_id = gm.member_id OR pr.debtor_member_id = gm.member_id)`, userID, requestID)

	item, err := scanEnrichedRequestRow(row)
	if errors.Is(err, sql.ErrNoRows) {
		return StoredRequest{}, ErrNotFound
	}
	return item, err
}

// CompleteSimulated stores the callback and immutable settlement in the same
// transaction. The request row lock serializes concurrent callbacks. It serves
// the client-driven simulated completion path.
func (r *Repository) CompleteSimulated(ctx context.Context, actorUserID, requestID, providerEventID string) (StoredRequest, bool, error) {
	if strings.TrimSpace(providerEventID) == "" || len(providerEventID) > 128 {
		return StoredRequest{}, false, ErrInvalidEvent
	}
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return StoredRequest{}, false, err
	}
	defer tx.Rollback()
	request, err := r.read(ctx, tx, `SELECT `+requestColumns+` FROM payment_requests WHERE id=$1 FOR UPDATE`, requestID)
	if errors.Is(err, sql.ErrNoRows) {
		return StoredRequest{}, false, ErrNotFound
	}
	if err != nil {
		return StoredRequest{}, false, err
	}
	var memberID string
	err = tx.QueryRowContext(ctx, `SELECT member_id FROM group_members WHERE group_id=$1 AND user_id=$2 AND member_id=$3 AND removed_at IS NULL AND accepted AND declined_at IS NULL`, request.GroupID, actorUserID, request.DebtorMemberID).Scan(&memberID)
	if errors.Is(err, sql.ErrNoRows) {
		return StoredRequest{}, false, ErrNotFound
	}
	if err != nil {
		return StoredRequest{}, false, err
	}
	if request.Status == StatusExpired || (!request.ExpiresAt.After(time.Now().UTC()) && request.Status == StatusPending) {
		return StoredRequest{}, false, ErrInvalidEvent
	}
	return r.commitCompletion(ctx, tx, request, providerEventID)
}

// CompleteByProvider applies a provider-confirmed PAID transition once inside
// the same transaction the settlement is written in. It performs no actor
// membership check (the reconciler runs with server-side credentials) and it
// completes requests whose local expiry passed, because the provider observed
// real settlement of the original agreement.
func (r *Repository) CompleteByProvider(ctx context.Context, requestID, providerEventID string) (StoredRequest, bool, error) {
	if strings.TrimSpace(providerEventID) == "" || len(providerEventID) > 128 {
		return StoredRequest{}, false, ErrInvalidEvent
	}
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return StoredRequest{}, false, err
	}
	defer tx.Rollback()
	request, err := r.read(ctx, tx, `SELECT `+requestColumns+` FROM payment_requests WHERE id=$1 FOR UPDATE`, requestID)
	if errors.Is(err, sql.ErrNoRows) {
		return StoredRequest{}, false, ErrNotFound
	}
	if err != nil {
		return StoredRequest{}, false, err
	}
	if request.Status != StatusPending {
		if err := tx.Commit(); err != nil {
			return StoredRequest{}, false, err
		}
		return request, false, nil
	}
	return r.commitCompletion(ctx, tx, request, providerEventID)
}

// commitCompletion revalidates the bilateral ledger and writes the provider
// event and immutable settlement in one transaction. Payments are never capped
// by the recreated ledger: an amount above the outstanding debt completes
// fully and the difference is the receiver's debt to the payer in the next
// projection. The outstanding value stays on the event so overpayments remain
// traceable financial history.
func (r *Repository) commitCompletion(ctx context.Context, tx *sql.Tx, request StoredRequest, providerEventID string) (StoredRequest, bool, error) {
	outstanding, err := outstandingFor(ctx, tx, request)
	if err != nil {
		return StoredRequest{}, false, err
	}
	eventID, err := newEventID("pe_")
	if err != nil {
		return StoredRequest{}, false, err
	}
	result, err := tx.ExecContext(ctx, `INSERT INTO payment_provider_events(id,provider,provider_event_id,payment_request_id,status,outstanding_cents) VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT(provider,provider_event_id) DO NOTHING`, eventID, request.Provider, providerEventID, request.ID, StatusPaid, outstanding)
	if err != nil {
		return StoredRequest{}, false, err
	}
	if rows, _ := result.RowsAffected(); rows == 0 {
		var existingRequest string
		if err := tx.QueryRowContext(ctx, `SELECT payment_request_id FROM payment_provider_events WHERE provider=$1 AND provider_event_id=$2`, request.Provider, providerEventID).Scan(&existingRequest); err != nil {
			return StoredRequest{}, false, err
		}
		if existingRequest != request.ID {
			return StoredRequest{}, false, ErrInvalidEvent
		}
		if err := tx.Commit(); err != nil {
			return StoredRequest{}, false, err
		}
		return request, false, nil
	}
	if request.SettlementID == "" {
		settlementID, err := newEventID("se_")
		if err != nil {
			return StoredRequest{}, false, err
		}
		if _, err = tx.ExecContext(ctx, `INSERT INTO settlements(id,group_id,from_member_id,to_member_id,amount_cents) VALUES($1,$2,$3,$4,$5)`, settlementID, request.GroupID, request.DebtorMemberID, request.CreditorMemberID, request.AmountCents); err != nil {
			return StoredRequest{}, false, err
		}
		request.SettlementID = settlementID
	}
	request.Status = StatusPaid
	if _, err = tx.ExecContext(ctx, `UPDATE payment_requests SET status=$2, settlement_id=$3, paid_at=now() WHERE id=$1`, request.ID, request.Status, request.SettlementID); err != nil {
		return StoredRequest{}, false, err
	}
	if err := tx.Commit(); err != nil {
		return StoredRequest{}, false, err
	}
	return request, true, nil
}

// ClaimStalePending atomically claims up to limit pending payment requests
// whose reconciliation is due, working safely across concurrent workers with
// FOR UPDATE SKIP LOCKED. The lease (reconcile_after) expires so a crashed
// worker cannot park the claim forever.
func (r *Repository) ClaimStalePending(ctx context.Context, claimBefore, leaseUntil time.Time, limit int) ([]StoredRequest, error) {
	rows, err := r.db.QueryContext(ctx, `WITH due AS (
	  SELECT id FROM payment_requests
	  WHERE status='PENDING' AND reconcile_after <= $1
	  ORDER BY created_at, id
	  LIMIT $2
	  FOR UPDATE SKIP LOCKED
	) UPDATE payment_requests SET reconcile_after=$3 WHERE id IN (SELECT id FROM due) RETURNING `+requestColumns, claimBefore, limit, leaseUntil)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	claims := []StoredRequest{}
	for rows.Next() {
		claimed, err := scanRequest(rows)
		if err != nil {
			return nil, err
		}
		claims = append(claims, claimed)
	}
	return claims, rows.Err()
}

// MarkTerminal closes a pending request without a settlement when the provider
// reports the payment failed or expired.
func (r *Repository) MarkTerminal(ctx context.Context, requestID string, status Status) error {
	result, err := r.db.ExecContext(ctx, `UPDATE payment_requests SET status=$2 WHERE id=$1 AND status='PENDING'`, requestID, status)
	if err != nil {
		return err
	}
	if count, _ := result.RowsAffected(); count == 0 {
		return ErrNotFound
	}
	return nil
}

// MarkReconcileResult records bounded retry state. A nil until parks the
// request: reconciliation gives up and future outcomes need manual review.
func (r *Repository) MarkReconcileResult(ctx context.Context, requestID string, attempts int, until *time.Time) error {
	if until == nil {
		_, err := r.db.ExecContext(ctx, `UPDATE payment_requests SET reconcile_attempts=$2, reconcile_after=NULL WHERE id=$1`, requestID, attempts)
		return err
	}
	_, err := r.db.ExecContext(ctx, `UPDATE payment_requests SET reconcile_attempts=$2, reconcile_after=$3 WHERE id=$1`, requestID, attempts, *until)
	return err
}

// RecordReconcile adds one immutable outcome row to the reconciliation audit.
func (r *Repository) RecordReconcile(ctx context.Context, requestID, providerName, outcome, detail string) error {
	id, err := newEventID("re_")
	if err != nil {
		return err
	}
	_, err = r.db.ExecContext(ctx, `INSERT INTO payment_reconcile_events(id,payment_request_id,provider,outcome,detail) VALUES($1,$2,$3,$4,$5)`, id, requestID, providerName, outcome, detail)
	return err
}

func (r *Repository) read(ctx context.Context, q queryer, query string, args ...any) (StoredRequest, error) {
	return scanRequestRow(q.QueryRowContext(ctx, query, args...))
}

func scanRequestRow(row *sql.Row) (StoredRequest, error) {
	var result StoredRequest
	var paidAt sql.NullTime
	err := row.Scan(&result.ID, &result.GroupID, &result.CreditorMemberID, &result.DebtorMemberID, &result.AmountCents, &result.Currency, &result.Provider, &result.Status, &result.PaymentURL, &result.ExpiresAt, &result.CorrelationID, &result.SettlementID, &result.ProviderRef, &result.Attempts, &result.Description, &result.CreatedAt, &paidAt)
	if paidAt.Valid {
		t := paidAt.Time
		result.PaidAt = &t
	}
	return result, err
}

func scanRequest(rows *sql.Rows) (StoredRequest, error) {
	var result StoredRequest
	var paidAt sql.NullTime
	err := rows.Scan(&result.ID, &result.GroupID, &result.CreditorMemberID, &result.DebtorMemberID, &result.AmountCents, &result.Currency, &result.Provider, &result.Status, &result.PaymentURL, &result.ExpiresAt, &result.CorrelationID, &result.SettlementID, &result.ProviderRef, &result.Attempts, &result.Description, &result.CreatedAt, &paidAt)
	if paidAt.Valid {
		t := paidAt.Time
		result.PaidAt = &t
	}
	return result, err
}

func scanEnrichedRequestRow(row *sql.Row) (StoredRequest, error) {
	var result StoredRequest
	var paidAt sql.NullTime
	err := row.Scan(
		&result.ID, &result.GroupID, &result.GroupName, &result.GroupEmoji,
		&result.CreditorMemberID, &result.CreditorName,
		&result.DebtorMemberID, &result.DebtorName,
		&result.AmountCents, &result.Currency, &result.Provider, &result.Status,
		&result.PaymentURL, &result.ExpiresAt, &result.CorrelationID,
		&result.SettlementID, &result.ProviderRef, &result.Attempts,
		&result.Description, &result.Role, &result.CreatedAt, &paidAt,
	)
	if paidAt.Valid {
		t := paidAt.Time
		result.PaidAt = &t
	}
	return result, err
}

func scanEnrichedRequest(rows *sql.Rows) (StoredRequest, error) {
	var result StoredRequest
	var paidAt sql.NullTime
	err := rows.Scan(
		&result.ID, &result.GroupID, &result.GroupName, &result.GroupEmoji,
		&result.CreditorMemberID, &result.CreditorName,
		&result.DebtorMemberID, &result.DebtorName,
		&result.AmountCents, &result.Currency, &result.Provider, &result.Status,
		&result.PaymentURL, &result.ExpiresAt, &result.CorrelationID,
		&result.SettlementID, &result.ProviderRef, &result.Attempts,
		&result.Description, &result.Role, &result.CreatedAt, &paidAt,
	)
	if paidAt.Valid {
		t := paidAt.Time
		result.PaidAt = &t
	}
	return result, err
}

func encodeCursor(createdAt time.Time, id string) string {
	raw := createdAt.UTC().Format(time.RFC3339Nano) + "|" + id
	return base64.RawURLEncoding.EncodeToString([]byte(raw))
}

func decodeCursor(cursor string) (time.Time, string, error) {
	decoded, err := base64.RawURLEncoding.DecodeString(strings.TrimSpace(cursor))
	if err != nil {
		return time.Time{}, "", err
	}
	parts := strings.SplitN(string(decoded), "|", 2)
	if len(parts) != 2 || strings.TrimSpace(parts[1]) == "" {
		return time.Time{}, "", errors.New("malformed cursor")
	}
	ts, err := time.Parse(time.RFC3339Nano, parts[0])
	if err != nil {
		return time.Time{}, "", err
	}
	return ts, parts[1], nil
}

func (r *Repository) CreditorMemberID(ctx context.Context, userID, groupID string) (string, error) {
	var memberID string
	err := r.db.QueryRowContext(ctx, `SELECT member_id FROM group_members WHERE group_id=$1 AND user_id=$2 AND removed_at IS NULL AND accepted AND declined_at IS NULL`, groupID, userID).Scan(&memberID)
	if errors.Is(err, sql.ErrNoRows) {
		return "", ErrNotFound
	}
	return memberID, err
}

type queryer interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}

func newEventID(prefix string) (string, error) {
	value := make([]byte, 16)
	if _, err := rand.Read(value); err != nil {
		return "", fmt.Errorf("generate payment event id: %w", err)
	}
	return prefix + hex.EncodeToString(value), nil
}

// outstandingFor revalidates the current debtor/creditor debt through the same
// deterministic ledger projection the API serves. It reads through the
// completion transaction, so the annotation shares the settlement snapshot.
func outstandingFor(ctx context.Context, tx *sql.Tx, request StoredRequest) (int64, error) {
	ledger, err := groups.Ledger(ctx, request.GroupID, tx)
	if err != nil {
		return 0, fmt.Errorf("revalidate outstanding balance: %w", err)
	}
	for _, relation := range ledger.PaymentRelations {
		if relation.FromMemberID == request.DebtorMemberID && relation.ToMemberID == request.CreditorMemberID {
			return relation.AmountCents, nil
		}
	}
	return 0, nil
}
func isUniqueViolation(err error) bool { return strings.Contains(err.Error(), "duplicate key") }
