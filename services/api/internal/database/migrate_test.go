package database

import (
	"context"
	"database/sql"
	"fmt"
	"net/url"
	"os"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

var schemaSequence atomic.Uint64

func TestMigrationsAreSequential(t *testing.T) {
	migrations, err := Migrations()
	if err != nil {
		t.Fatal(err)
	}
	if len(migrations) == 0 {
		t.Fatal("expected at least one migration")
	}
	for index, migration := range migrations {
		if migration.Version != index+1 {
			t.Fatalf("migration version = %d, want %d", migration.Version, index+1)
		}
		if migration.Name == "" || len(migration.Checksum) != 64 || strings.TrimSpace(migration.SQL) == "" {
			t.Fatalf("invalid migration metadata: %#v", migration)
		}
	}
}

func TestMigrateCleanDatabase(t *testing.T) {
	db := isolatedDatabase(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	result, err := Migrate(ctx, db)
	if err != nil {
		t.Fatal(err)
	}
	if result.CurrentVersion != 4 || len(result.Applied) != 4 {
		t.Fatalf("unexpected migration result: %#v", result)
	}
	for _, table := range []string{"users", "contacts", "sessions", "session_families", "refresh_tokens", "members", "expense_groups", "group_members", "expenses", "expense_payers", "expense_participants", "expense_shares", "settlements", "schema_migrations"} {
		var exists bool
		if err := db.QueryRowContext(ctx, `SELECT to_regclass($1) IS NOT NULL`, table).Scan(&exists); err != nil {
			t.Fatalf("find table %s: %v", table, err)
		}
		if !exists {
			t.Fatalf("table %s was not created", table)
		}
	}
	version, err := Verify(ctx, db)
	if err != nil || version != 4 {
		t.Fatalf("verify version = %d, error = %v", version, err)
	}

	second, err := Migrate(ctx, db)
	if err != nil {
		t.Fatal(err)
	}
	if second.CurrentVersion != 4 || len(second.Applied) != 0 {
		t.Fatalf("migration rerun was not idempotent: %#v", second)
	}
}

func TestVerifyRejectsUnmigratedDatabase(t *testing.T) {
	db := isolatedDatabase(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	if _, err := Verify(ctx, db); err == nil {
		t.Fatal("expected an unmigrated database to be rejected")
	}
	var migrationTableExists bool
	if err := db.QueryRowContext(ctx, `SELECT to_regclass('schema_migrations') IS NOT NULL`).Scan(&migrationTableExists); err != nil {
		t.Fatal(err)
	}
	if migrationTableExists {
		t.Fatal("schema verification unexpectedly performed DDL")
	}
}

func TestMigrateAdoptsCurrentUnversionedSchemaWithoutDataLoss(t *testing.T) {
	db := isolatedDatabase(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	migrations, err := Migrations()
	if err != nil {
		t.Fatal(err)
	}
	// This is the state produced by the application before migrations were
	// versioned: the current schema exists, but there is no migration ledger.
	if _, err := db.ExecContext(ctx, migrations[0].SQL); err != nil {
		t.Fatalf("create unversioned schema: %v", err)
	}
	seed := []string{
		`INSERT INTO users(id,name,email,phone,password_hash,salary_cents) VALUES('user-1','Ana','ana@example.test','+525511112222','hash',2500000)`,
		`INSERT INTO contacts(id,owner_id,name,phone,linked_user_id) VALUES('contact-1','user-1','Beto','+525533334444',NULL)`,
		`INSERT INTO sessions(token_hash,user_id,expires_at) VALUES('token-hash','user-1',now() + interval '1 day')`,
		`INSERT INTO members(id,name,phone,user_id) VALUES('user-1','Ana','+525511112222','user-1'),('member-2','Beto','+525533334444',NULL)`,
		`INSERT INTO expense_groups(id,name,emoji,owner_id,visibility) VALUES('group-1','Viaje','trip','user-1','personal')`,
		`INSERT INTO group_members(group_id,member_id,position,user_id) VALUES('group-1','user-1',0,'user-1'),('group-1','member-2',1,NULL)`,
		`INSERT INTO expenses(id,group_id,description,amount_cents,payer_id,split_mode) VALUES('expense-1','group-1','Cena',10001,'user-1','equal')`,
		`INSERT INTO expense_participants(expense_id,member_id,position) VALUES('expense-1','user-1',0),('expense-1','member-2',1)`,
		`INSERT INTO settlements(id,group_id,from_member_id,to_member_id,amount_cents) VALUES('settlement-1','group-1','member-2','user-1',2500)`,
	}
	for _, statement := range seed {
		if _, err := db.ExecContext(ctx, statement); err != nil {
			t.Fatalf("seed current schema: %v", err)
		}
	}

	result, err := Migrate(ctx, db)
	if err != nil {
		t.Fatal(err)
	}
	if result.CurrentVersion != 4 || len(result.Applied) != 4 {
		t.Fatalf("unexpected adoption result: %#v", result)
	}
	var amount, settlement int64
	if err := db.QueryRowContext(ctx, `SELECT amount_cents FROM expenses WHERE id='expense-1'`).Scan(&amount); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRowContext(ctx, `SELECT amount_cents FROM settlements WHERE id='settlement-1'`).Scan(&settlement); err != nil {
		t.Fatal(err)
	}
	if amount != 10001 || settlement != 2500 {
		t.Fatalf("financial data changed: expense=%d settlement=%d", amount, settlement)
	}
	var payerAmount int64
	if err := db.QueryRowContext(ctx, `SELECT amount_cents FROM expense_payers WHERE expense_id='expense-1' AND member_id='user-1'`).Scan(&payerAmount); err != nil || payerAmount != 10001 {
		t.Fatalf("legacy payer was not migrated: amount=%d error=%v", payerAmount, err)
	}
	var users, groups, contacts int
	if err := db.QueryRowContext(ctx, `SELECT (SELECT count(*) FROM users), (SELECT count(*) FROM expense_groups), (SELECT count(*) FROM contacts)`).Scan(&users, &groups, &contacts); err != nil {
		t.Fatal(err)
	}
	if users != 1 || groups != 1 || contacts != 1 {
		t.Fatalf("representative data was not preserved: users=%d groups=%d contacts=%d", users, groups, contacts)
	}
	var ownerRole, memberRole string
	if err := db.QueryRowContext(ctx, `SELECT role FROM group_members WHERE group_id='group-1' AND member_id='user-1'`).Scan(&ownerRole); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRowContext(ctx, `SELECT role FROM group_members WHERE group_id='group-1' AND member_id='member-2'`).Scan(&memberRole); err != nil {
		t.Fatal(err)
	}
	if ownerRole != "owner" || memberRole != "member" {
		t.Fatalf("roles were not preserved: owner=%q member=%q", ownerRole, memberRole)
	}
	var legacySessionBounded bool
	if err := db.QueryRowContext(ctx, `SELECT family_id IS NULL AND revoked_at IS NULL AND expires_at <= now() + interval '16 minutes' FROM sessions WHERE token_hash='token-hash'`).Scan(&legacySessionBounded); err != nil {
		t.Fatal(err)
	}
	if !legacySessionBounded {
		t.Fatal("legacy bearer session did not receive a bounded compatibility lifetime")
	}
}

func TestVerifyRejectsChangedAppliedMigration(t *testing.T) {
	db := isolatedDatabase(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	if _, err := Migrate(ctx, db); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE schema_migrations SET checksum='changed' WHERE version=1`); err != nil {
		t.Fatal(err)
	}
	if _, err := Verify(ctx, db); err == nil {
		t.Fatal("expected checksum verification failure")
	}
	if _, err := Migrate(ctx, db); err == nil {
		t.Fatal("expected migration checksum failure")
	}
}

func isolatedDatabase(t *testing.T) *sql.DB {
	t.Helper()
	databaseURL := os.Getenv("TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}
	admin, err := Open(databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := admin.PingContext(ctx); err != nil {
		admin.Close()
		t.Fatalf("connect to test database: %v", err)
	}
	schema := fmt.Sprintf("migration_test_%d_%d", time.Now().UnixNano(), schemaSequence.Add(1))
	if _, err := admin.ExecContext(ctx, `CREATE SCHEMA "`+schema+`"`); err != nil {
		admin.Close()
		t.Fatalf("create test schema: %v", err)
	}
	t.Cleanup(func() {
		cleanupContext, cleanupCancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cleanupCancel()
		_, _ = admin.ExecContext(cleanupContext, `DROP SCHEMA "`+schema+`" CASCADE`)
		_ = admin.Close()
	})
	parsed, err := url.Parse(databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	query := parsed.Query()
	query.Set("search_path", schema)
	parsed.RawQuery = query.Encode()
	db, err := Open(parsed.String())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Close() })
	return db
}
