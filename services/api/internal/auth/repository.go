package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
	"golang.org/x/crypto/bcrypt"
)

var (
	ErrInvalid      = errors.New("invalid credentials")
	ErrEmailInUse   = errors.New("email already registered")
	ErrUnauthorized = errors.New("unauthorized")
)

type User struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Email string `json:"email"`
	Phone string `json:"phone"`
}

type Session struct {
	Token string `json:"token"`
	User  User   `json:"user"`
}

type Repository struct{ db *sql.DB }

func Open(databaseURL string) (*Repository, error) {
	db, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return nil, fmt.Errorf("open auth database: %w", err)
	}
	return &Repository{db: db}, nil
}

func (r *Repository) Close() error { return r.db.Close() }

func (r *Repository) Migrate(ctx context.Context) error {
	_, err := r.db.ExecContext(ctx, schema)
	return err
}

func (r *Repository) Register(ctx context.Context, name, email, phone, password string) (Session, error) {
	name, email = strings.TrimSpace(name), strings.ToLower(strings.TrimSpace(email))
	phone, validPhone := NormalizePhone(phone)
	if len(name) < 2 || !strings.Contains(email, "@") || !validPhone || len(password) < 8 {
		return Session{}, ErrInvalid
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return Session{}, fmt.Errorf("hash password: %w", err)
	}
	userID, err := newID("user")
	if err != nil {
		return Session{}, err
	}
	user := User{ID: userID, Name: name, Email: email, Phone: phone}
	result, err := r.db.ExecContext(ctx, `INSERT INTO users (id, name, email, phone, password_hash) VALUES ($1, $2, $3, $4, $5) ON CONFLICT DO NOTHING`, user.ID, user.Name, user.Email, user.Phone, string(hash))
	if err != nil {
		return Session{}, fmt.Errorf("insert user: %w", err)
	}
	if inserted, err := result.RowsAffected(); err != nil || inserted == 0 {
		return Session{}, ErrEmailInUse
	}
	return r.newSession(ctx, user)
}

func (r *Repository) Login(ctx context.Context, email, password string) (Session, error) {
	var user User
	var hash string
	err := r.db.QueryRowContext(ctx, `SELECT id, name, email, COALESCE(phone, ''), password_hash FROM users WHERE email = $1`, strings.ToLower(strings.TrimSpace(email))).Scan(&user.ID, &user.Name, &user.Email, &user.Phone, &hash)
	if err != nil || bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) != nil {
		return Session{}, ErrInvalid
	}
	return r.newSession(ctx, user)
}

func (r *Repository) UserForToken(ctx context.Context, token string) (User, error) {
	hash := sha256.Sum256([]byte(token))
	var user User
	err := r.db.QueryRowContext(ctx, `
SELECT u.id, u.name, u.email, COALESCE(u.phone, '')
FROM sessions s JOIN users u ON u.id = s.user_id
WHERE s.token_hash = $1 AND s.expires_at > now()`, hex.EncodeToString(hash[:])).Scan(&user.ID, &user.Name, &user.Email, &user.Phone)
	if errors.Is(err, sql.ErrNoRows) {
		return User{}, ErrUnauthorized
	}
	if err != nil {
		return User{}, fmt.Errorf("find session: %w", err)
	}
	return user, nil
}

func (r *Repository) Contacts(ctx context.Context, userID string, phones []string) ([]User, error) {
	if len(phones) == 0 {
		return []User{}, nil
	}
	rows, err := r.db.QueryContext(ctx, `SELECT id, name, email, phone FROM users WHERE phone = ANY($1) AND id <> $2 ORDER BY name`, phones, userID)
	if err != nil {
		return nil, fmt.Errorf("find contacts: %w", err)
	}
	defer rows.Close()
	contacts := []User{}
	for rows.Next() {
		var user User
		if err := rows.Scan(&user.ID, &user.Name, &user.Email, &user.Phone); err != nil {
			return nil, fmt.Errorf("scan contact: %w", err)
		}
		contacts = append(contacts, user)
	}
	return contacts, rows.Err()
}

func NormalizePhone(value string) (string, bool) {
	var digits strings.Builder
	for _, char := range value {
		if char >= '0' && char <= '9' {
			digits.WriteRune(char)
		}
	}
	number := digits.String()
	if len(number) == 10 {
		return "+52" + number, number[0] != '0'
	}
	if len(number) == 12 && strings.HasPrefix(number, "52") {
		return "+" + number, number[2] != '0'
	}
	return "", false
}

func (r *Repository) newSession(ctx context.Context, user User) (Session, error) {
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return Session{}, fmt.Errorf("generate session: %w", err)
	}
	token := hex.EncodeToString(bytes)
	hash := sha256.Sum256([]byte(token))
	_, err := r.db.ExecContext(ctx, `INSERT INTO sessions (token_hash, user_id, expires_at) VALUES ($1, $2, $3)`, hex.EncodeToString(hash[:]), user.ID, time.Now().Add(30*24*time.Hour))
	if err != nil {
		return Session{}, fmt.Errorf("insert session: %w", err)
	}
	return Session{Token: token, User: user}, nil
}

func newID(prefix string) (string, error) {
	bytes := make([]byte, 12)
	if _, err := rand.Read(bytes); err != nil {
		return "", fmt.Errorf("generate user ID: %w", err)
	}
	return prefix + "_" + hex.EncodeToString(bytes), nil
}

const schema = `
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL CHECK (length(trim(name)) > 1),
  email TEXT NOT NULL UNIQUE,
	phone TEXT UNIQUE,
  password_hash TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS users_phone_unique_idx ON users(phone) WHERE phone IS NOT NULL;
CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS sessions_user_idx ON sessions(user_id);
`
