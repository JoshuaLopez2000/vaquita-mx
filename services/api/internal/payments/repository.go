package payments

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

var (
	ErrNotFound            = errors.New("payment request not found")
	ErrIdempotencyConflict = errors.New("idempotency key conflicts with request")
	ErrInvalidEvent        = errors.New("invalid provider event")
)

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
	GroupID          string `json:"group_id"`
	DebtorMemberID   string `json:"debtor_id"`
	CreditorMemberID string `json:"creditor_id"`
	SettlementID     string `json:"settlement_id,omitempty"`
}

func (r *Repository) FindIdempotent(ctx context.Context, userID, key, hash string) (StoredRequest, bool, error) {
	stored, err := r.read(ctx, r.db, `SELECT id,group_id,creditor_member_id,debtor_member_id,amount_cents,currency,provider,status,payment_url,expires_at,correlation_id,COALESCE(settlement_id,'') FROM payment_requests WHERE requester_user_id=$1 AND idempotency_key=$2`, userID, key)
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
	_, err := r.db.ExecContext(ctx, `INSERT INTO payment_requests(id,group_id,creditor_member_id,debtor_member_id,requester_user_id,amount_cents,currency,provider,status,payment_url,correlation_id,expires_at,idempotency_key,payload_hash) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)`, result.ID, input.GroupID, creditorMemberID, input.DebtorID, userID, input.AmountCents, input.Currency, result.Provider, result.Status, result.PaymentURL, result.CorrelationID, result.ExpiresAt, key, hash)
	if err == nil {
		return StoredRequest{PaymentRequest: result, GroupID: input.GroupID, DebtorMemberID: input.DebtorID, CreditorMemberID: creditorMemberID}, true, nil
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

// CompleteSimulated stores the callback and immutable settlement in the same
// transaction. The request row lock serializes concurrent callbacks.
func (r *Repository) CompleteSimulated(ctx context.Context, actorUserID, requestID, providerEventID string) (StoredRequest, bool, error) {
	if strings.TrimSpace(providerEventID) == "" || len(providerEventID) > 128 {
		return StoredRequest{}, false, ErrInvalidEvent
	}
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return StoredRequest{}, false, err
	}
	defer tx.Rollback()
	request, err := r.read(ctx, tx, `SELECT id,group_id,creditor_member_id,debtor_member_id,amount_cents,currency,provider,status,payment_url,expires_at,correlation_id,COALESCE(settlement_id,'') FROM payment_requests WHERE id=$1 FOR UPDATE`, requestID)
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

	eventID, err := newEventID()
	if err != nil {
		return StoredRequest{}, false, err
	}
	result, err := tx.ExecContext(ctx, `INSERT INTO payment_provider_events(id,provider,provider_event_id,payment_request_id,status) VALUES($1,$2,$3,$4,$5) ON CONFLICT(provider,provider_event_id) DO NOTHING`, eventID, request.Provider, providerEventID, request.ID, StatusPaid)
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
		settlementID, err := newEventID()
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

type queryer interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}

func (r *Repository) read(ctx context.Context, q queryer, query string, args ...any) (StoredRequest, error) {
	var result StoredRequest
	err := q.QueryRowContext(ctx, query, args...).Scan(&result.ID, &result.GroupID, &result.CreditorMemberID, &result.DebtorMemberID, &result.AmountCents, &result.Currency, &result.Provider, &result.Status, &result.PaymentURL, &result.ExpiresAt, &result.CorrelationID, &result.SettlementID)
	return result, err
}

func (r *Repository) CreditorMemberID(ctx context.Context, userID, groupID string) (string, error) {
	var memberID string
	err := r.db.QueryRowContext(ctx, `SELECT member_id FROM group_members WHERE group_id=$1 AND user_id=$2 AND removed_at IS NULL AND accepted AND declined_at IS NULL`, groupID, userID).Scan(&memberID)
	if errors.Is(err, sql.ErrNoRows) {
		return "", ErrNotFound
	}
	return memberID, err
}

func newEventID() (string, error) {
	value := make([]byte, 16)
	if _, err := rand.Read(value); err != nil {
		return "", fmt.Errorf("generate payment event id: %w", err)
	}
	return "pe_" + hex.EncodeToString(value), nil
}
func isUniqueViolation(err error) bool { return strings.Contains(err.Error(), "duplicate key") }
