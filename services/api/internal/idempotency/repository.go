// Package idempotency records the outcome of mutating API commands so
// clients can retry an interrupted request without creating a second
// financial row. The claim, the command, and its stored response commit in
// one transaction, so two concurrent identical requests can never both write
// business rows: the loser replays the stored outcome.
package idempotency

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

// ErrConflict means the same key was reused with a different request payload
// under the same user, operation, and scope.
var ErrConflict = errors.New("idempotency key conflicts with request")

// cleanupInterval is the recurring deletion period. Intent rows hold response
// snapshots with financial metadata, so retention stays bounded and short.
const cleanupInterval = time.Hour

// DefaultRetention bounds how long a stored outcome stays replayable. It can
// be raised through the IDEMPOTENCY_RETENTION environment setting, but never
// unbounded: the table is a retry window, not an audit log.
const DefaultRetention = 7 * 24 * time.Hour

type Repository struct{ db *sql.DB }

func Open(url string) (*Repository, error) {
	db, err := sql.Open("pgx", url)
	if err != nil {
		return nil, fmt.Errorf("open command idempotency database: %w", err)
	}
	return &Repository{db: db}, nil
}

func (r *Repository) Close() error { return r.db.Close() }

// Run executes one mutating command inside a transaction. The run callback
// receives the transaction and returns the success status and response body.
//
// With an empty key it behaves like the command's own transactional method.
// With a key, the first committed attempt stores its outcome and identical
// retries replay it; a different payload under the same user, operation,
// scope, and key fails with ErrConflict. Nothing is recorded when the command
// rejects the request, so a corrected retry claims the key freshly.
func (r *Repository) Run(ctx context.Context, user, operation, scope, key, payloadHash string, run func(*sql.Tx) (int, any, error)) (Result, error) {
	if key == "" {
		return r.run(ctx, run)
	}
	for attempt := 0; attempt < 3; attempt++ {
		result, retryable, err := r.runOnce(ctx, user, operation, scope, key, payloadHash, run)
		if err != nil {
			return Result{}, err
		}
		if retryable {
			continue
		}
		return result, nil
	}
	return Result{}, errors.New("command idempotency: intent could not be claimed")
}

// Result is one concluded command. Replayed results carry the stored body as
// json.RawMessage; fresh results carry the command's own value.
type Result struct {
	Replayed bool
	Status   int
	Body     any
}

func (r *Repository) run(ctx context.Context, run func(*sql.Tx) (int, any, error)) (Result, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return Result{}, fmt.Errorf("begin command transaction: %w", err)
	}
	defer tx.Rollback()
	status, body, err := run(tx)
	if err != nil {
		return Result{}, err
	}
	if err := tx.Commit(); err != nil {
		return Result{}, fmt.Errorf("commit command: %w", err)
	}
	return Result{Status: status, Body: body}, nil
}

// runOnce attempts one claim. retryable is true only when the context intent
// row disappeared between our losing the claim and reading it, which means a
// concurrent run rolled back and we can claim again.
func (r *Repository) runOnce(ctx context.Context, user, operation, scope, key, payloadHash string, run func(*sql.Tx) (int, any, error)) (Result, bool, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return Result{}, false, fmt.Errorf("begin command transaction: %w", err)
	}
	defer tx.Rollback()
	claimed, err := r.claim(ctx, tx, user, operation, scope, key, payloadHash)
	if err != nil {
		return Result{}, false, err
	}
	if claimed {
		status, body, err := run(tx)
		if err != nil {
			return Result{}, false, err
		}
		if err := r.record(ctx, tx, user, operation, scope, key, status, body); err != nil {
			return Result{}, false, err
		}
		if err := tx.Commit(); err != nil {
			return Result{}, false, fmt.Errorf("commit command outcome: %w", err)
		}
		return Result{Status: status, Body: body}, false, nil
	}
	stored, err := r.stored(ctx, tx, user, operation, scope, key)
	if err != nil {
		return Result{}, false, err
	}
	if stored.missing {
		return Result{}, true, nil
	}
	if stored.hash != payloadHash {
		return Result{}, false, ErrConflict
	}
	return Result{Replayed: true, Status: stored.status, Body: stored.body}, false, nil
}

// claim inserts the intent row. When another run holds an uncommitted claim,
// the insert waits for it: a committing run makes this one replay, and a
// rolling back run lets this one claim the key.
func (r *Repository) claim(ctx context.Context, tx *sql.Tx, user, operation, scope, key, payloadHash string) (bool, error) {
	result, err := tx.ExecContext(ctx, `
INSERT INTO command_idempotency(user_id,operation,scope_id,idempotency_key,payload_hash,status_code)
VALUES($1,$2,$3,$4,$5,0)
ON CONFLICT (user_id,operation,scope_id,idempotency_key) DO NOTHING`,
		user, operation, scope, key, payloadHash)
	if err != nil {
		return false, fmt.Errorf("claim command intent: %w", err)
	}
	inserted, err := result.RowsAffected()
	if err != nil {
		return false, err
	}
	return inserted == 1, nil
}

type storedOutcome struct {
	missing bool
	hash    string
	status  int
	body    json.RawMessage
}

func (r *Repository) stored(ctx context.Context, tx *sql.Tx, user, operation, scope, key string) (storedOutcome, error) {
	var out storedOutcome
	var responseBody []byte
	err := tx.QueryRowContext(ctx, `
SELECT payload_hash,status_code,response_body FROM command_idempotency
WHERE user_id=$1 AND operation=$2 AND scope_id=$3 AND idempotency_key=$4`,
		user, operation, scope, key).Scan(&out.hash, &out.status, &responseBody)
	if errors.Is(err, sql.ErrNoRows) {
		return storedOutcome{missing: true}, nil
	}
	if err != nil {
		return storedOutcome{}, fmt.Errorf("read command intent: %w", err)
	}
	out.body = json.RawMessage(responseBody)
	return out, nil
}

func (r *Repository) record(ctx context.Context, tx *sql.Tx, user, operation, scope, key string, status int, body any) error {
	var payload any
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("encode command outcome: %w", err)
		}
		payload = string(encoded)
	}
	if _, err := tx.ExecContext(ctx, `
UPDATE command_idempotency SET status_code=$5,response_body=$6
WHERE user_id=$1 AND operation=$2 AND scope_id=$3 AND idempotency_key=$4`,
		user, operation, scope, key, status, payload); err != nil {
		return fmt.Errorf("record command outcome: %w", err)
	}
	return nil
}

// RunCleanup deletes expired outcome snapshots once and then hourly. It is a
// background job; a failing cycle just logs and waits for the next tick.
// ctx governs the job's lifetime, so callers pass a long-lived context.
func (r *Repository) RunCleanup(ctx context.Context, retention time.Duration) {
	r.Cleanup(ctx, retention)
	ticker := time.NewTicker(cleanupInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			r.Cleanup(ctx, retention)
		}
	}
}

func (r *Repository) Cleanup(ctx context.Context, retention time.Duration) {
	deadline := time.Now().UTC().Add(-retention)
	result, err := r.db.ExecContext(ctx, `DELETE FROM command_idempotency WHERE created_at < $1`, deadline)
	if err != nil {
		slog.Error("clean command idempotency", "error", err)
		return
	}
	if deleted, _ := result.RowsAffected(); deleted > 0 {
		slog.Info("expired command idempotency outcomes deleted", "count", deleted)
	}
}
