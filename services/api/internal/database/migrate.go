package database

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"embed"
	"encoding/hex"
	"fmt"
	"io/fs"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

const migrationLockID int64 = 0x56415155495441

var migrationName = regexp.MustCompile(`^(\d{4})_([a-z0-9_]+)\.sql$`)

//go:embed migrations/*.sql
var migrationFiles embed.FS

type Migration struct {
	Version  int
	Name     string
	SQL      string
	Checksum string
}

type Result struct {
	Applied        []Migration
	CurrentVersion int
}

func Verify(ctx context.Context, db *sql.DB) (int, error) {
	migrations, err := Migrations()
	if err != nil {
		return 0, err
	}
	conn, err := db.Conn(ctx)
	if err != nil {
		return 0, fmt.Errorf("acquire schema verification connection: %w", err)
	}
	defer conn.Close()
	applied, err := appliedMigrations(ctx, conn)
	if err != nil {
		return 0, fmt.Errorf("verify schema migrations: %w", err)
	}
	if len(applied) != len(migrations) {
		return 0, fmt.Errorf("database schema has %d applied migrations, expected %d; run the migration command", len(applied), len(migrations))
	}
	current := 0
	for _, migration := range migrations {
		recorded, ok := applied[migration.Version]
		if !ok {
			return 0, fmt.Errorf("database is missing migration %04d_%s; run the migration command", migration.Version, migration.Name)
		}
		if recorded.Name != migration.Name || recorded.Checksum != migration.Checksum {
			return 0, fmt.Errorf("applied migration %04d_%s does not match the embedded file", migration.Version, recorded.Name)
		}
		current = migration.Version
	}
	return current, nil
}

func Open(databaseURL string) (*sql.DB, error) {
	db, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return nil, fmt.Errorf("open migration database: %w", err)
	}
	return db, nil
}

func Migrations() ([]Migration, error) {
	entries, err := fs.ReadDir(migrationFiles, "migrations")
	if err != nil {
		return nil, fmt.Errorf("read embedded migrations: %w", err)
	}
	migrations := make([]Migration, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		matches := migrationName.FindStringSubmatch(entry.Name())
		if matches == nil {
			return nil, fmt.Errorf("invalid migration filename %q", entry.Name())
		}
		version, err := strconv.Atoi(matches[1])
		if err != nil {
			return nil, fmt.Errorf("parse migration version %q: %w", entry.Name(), err)
		}
		contents, err := migrationFiles.ReadFile(filepath.ToSlash("migrations/" + entry.Name()))
		if err != nil {
			return nil, fmt.Errorf("read migration %q: %w", entry.Name(), err)
		}
		canonicalSQL := strings.ReplaceAll(string(contents), "\r\n", "\n")
		if strings.TrimSpace(canonicalSQL) == "" {
			return nil, fmt.Errorf("migration %q is empty", entry.Name())
		}
		digest := sha256.Sum256([]byte(canonicalSQL))
		migrations = append(migrations, Migration{
			Version:  version,
			Name:     matches[2],
			SQL:      canonicalSQL,
			Checksum: hex.EncodeToString(digest[:]),
		})
	}
	sort.Slice(migrations, func(i, j int) bool { return migrations[i].Version < migrations[j].Version })
	for index, migration := range migrations {
		expected := index + 1
		if migration.Version != expected {
			return nil, fmt.Errorf("migration sequence has version %04d, expected %04d", migration.Version, expected)
		}
	}
	return migrations, nil
}

func Migrate(ctx context.Context, db *sql.DB) (Result, error) {
	migrations, err := Migrations()
	if err != nil {
		return Result{}, err
	}
	conn, err := db.Conn(ctx)
	if err != nil {
		return Result{}, fmt.Errorf("acquire migration connection: %w", err)
	}
	defer conn.Close()
	if _, err := conn.ExecContext(ctx, `SELECT pg_advisory_lock($1)`, migrationLockID); err != nil {
		return Result{}, fmt.Errorf("acquire migration lock: %w", err)
	}
	defer func() {
		unlockContext, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_, _ = conn.ExecContext(unlockContext, `SELECT pg_advisory_unlock($1)`, migrationLockID)
	}()

	if _, err := conn.ExecContext(ctx, `
CREATE TABLE IF NOT EXISTS schema_migrations (
  version BIGINT PRIMARY KEY,
  name TEXT NOT NULL,
  checksum TEXT NOT NULL,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
)`); err != nil {
		return Result{}, fmt.Errorf("create migration ledger: %w", err)
	}

	applied, err := appliedMigrations(ctx, conn)
	if err != nil {
		return Result{}, err
	}
	expected := make(map[int]Migration, len(migrations))
	for _, migration := range migrations {
		expected[migration.Version] = migration
	}
	for version, recorded := range applied {
		migration, ok := expected[version]
		if !ok {
			return Result{}, fmt.Errorf("database contains unknown migration version %04d", version)
		}
		if recorded.Name != migration.Name || recorded.Checksum != migration.Checksum {
			return Result{}, fmt.Errorf("applied migration %04d_%s does not match the embedded file", version, recorded.Name)
		}
	}

	result := Result{}
	for _, migration := range migrations {
		if _, ok := applied[migration.Version]; ok {
			result.CurrentVersion = migration.Version
			continue
		}
		tx, err := conn.BeginTx(ctx, nil)
		if err != nil {
			return Result{}, fmt.Errorf("begin migration %04d_%s: %w", migration.Version, migration.Name, err)
		}
		if _, err = tx.ExecContext(ctx, migration.SQL); err != nil {
			_ = tx.Rollback()
			return Result{}, fmt.Errorf("apply migration %04d_%s: %w", migration.Version, migration.Name, err)
		}
		if _, err = tx.ExecContext(ctx, `INSERT INTO schema_migrations(version, name, checksum) VALUES($1, $2, $3)`, migration.Version, migration.Name, migration.Checksum); err != nil {
			_ = tx.Rollback()
			return Result{}, fmt.Errorf("record migration %04d_%s: %w", migration.Version, migration.Name, err)
		}
		if err = tx.Commit(); err != nil {
			return Result{}, fmt.Errorf("commit migration %04d_%s: %w", migration.Version, migration.Name, err)
		}
		result.Applied = append(result.Applied, migration)
		result.CurrentVersion = migration.Version
	}
	return result, nil
}

func appliedMigrations(ctx context.Context, conn *sql.Conn) (map[int]Migration, error) {
	rows, err := conn.QueryContext(ctx, `SELECT version, name, checksum FROM schema_migrations ORDER BY version`)
	if err != nil {
		return nil, fmt.Errorf("read migration ledger: %w", err)
	}
	defer rows.Close()
	applied := map[int]Migration{}
	for rows.Next() {
		var migration Migration
		if err := rows.Scan(&migration.Version, &migration.Name, &migration.Checksum); err != nil {
			return nil, fmt.Errorf("scan migration ledger: %w", err)
		}
		applied[migration.Version] = migration
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate migration ledger: %w", err)
	}
	return applied, nil
}
