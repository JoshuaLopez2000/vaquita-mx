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
	ID          string `json:"id"`
	Name        string `json:"name"`
	Email       string `json:"email"`
	Phone       string `json:"phone"`
	SalaryCents int64  `json:"salary_cents,omitempty"`
}

type Session struct {
	Token string `json:"token"`
	User  User   `json:"user"`
}
type Contact struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	Phone  string `json:"phone"`
	UserID string `json:"user_id,omitempty"`
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

func (r *Repository) Register(ctx context.Context, name, email, phone, password string, salaryCents int64) (Session, error) {
	name, email = strings.TrimSpace(name), strings.ToLower(strings.TrimSpace(email))
	phone, validPhone := NormalizePhone(phone)
	if len(name) < 2 || !strings.Contains(email, "@") || !validPhone || len(password) < 8 || salaryCents < 0 {
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
	user := User{ID: userID, Name: name, Email: email, Phone: phone, SalaryCents: salaryCents}
	result, err := r.db.ExecContext(ctx, `INSERT INTO users (id, name, email, phone, password_hash, salary_cents) VALUES ($1, $2, $3, $4, $5, $6) ON CONFLICT DO NOTHING`, user.ID, user.Name, user.Email, user.Phone, string(hash), user.SalaryCents)
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
	err := r.db.QueryRowContext(ctx, `SELECT id, name, email, COALESCE(phone, ''), COALESCE(salary_cents, 0), password_hash FROM users WHERE email = $1`, strings.ToLower(strings.TrimSpace(email))).Scan(&user.ID, &user.Name, &user.Email, &user.Phone, &user.SalaryCents, &hash)
	if err != nil || bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) != nil {
		return Session{}, ErrInvalid
	}
	return r.newSession(ctx, user)
}

func (r *Repository) UserForToken(ctx context.Context, token string) (User, error) {
	hash := sha256.Sum256([]byte(token))
	var user User
	err := r.db.QueryRowContext(ctx, `
SELECT u.id, u.name, u.email, COALESCE(u.phone, ''), COALESCE(u.salary_cents, 0)
FROM sessions s JOIN users u ON u.id = s.user_id
WHERE s.token_hash = $1 AND s.expires_at > now()`, hex.EncodeToString(hash[:])).Scan(&user.ID, &user.Name, &user.Email, &user.Phone, &user.SalaryCents)
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

func (r *Repository) SaveContacts(ctx context.Context, ownerID string, contacts []Contact) ([]Contact, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	for _, contact := range contacts {
		contact.Name = strings.TrimSpace(contact.Name)
		phone, ok := NormalizePhone(contact.Phone)
		if contact.Name == "" || !ok {
			continue
		}
		id, err := newID("contact")
		if err != nil {
			return nil, err
		}
		if _, err = tx.ExecContext(ctx, `INSERT INTO contacts(id,owner_id,name,phone,linked_user_id) VALUES($1,$2,$3,$4,(SELECT id FROM users WHERE phone=$4)) ON CONFLICT(owner_id,phone) DO UPDATE SET name=EXCLUDED.name,linked_user_id=EXCLUDED.linked_user_id`, id, ownerID, contact.Name, phone); err != nil {
			return nil, err
		}
	}
	if err = tx.Commit(); err != nil {
		return nil, err
	}
	return r.ListContacts(ctx, ownerID)
}
func (r *Repository) ListContacts(ctx context.Context, ownerID string) ([]Contact, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT id,name,phone,COALESCE(linked_user_id,'') FROM contacts WHERE owner_id=$1 ORDER BY name`, ownerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]Contact, 0)
	for rows.Next() {
		var c Contact
		if err = rows.Scan(&c.ID, &c.Name, &c.Phone, &c.UserID); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (r *Repository) RemoveContact(ctx context.Context, ownerID, contactID string) error {
	result, err := r.db.ExecContext(ctx, `DELETE FROM contacts WHERE id=$1 AND owner_id=$2`, contactID, ownerID)
	if err != nil {
		return fmt.Errorf("delete contact: %w", err)
	}
	deleted, err := result.RowsAffected()
	if err != nil || deleted == 0 {
		return ErrInvalid
	}
	return nil
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
