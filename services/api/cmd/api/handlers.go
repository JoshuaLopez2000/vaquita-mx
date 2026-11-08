package main

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/auth"
	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/groups"
	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/idempotency"
	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/payments"
)

func (app application) register(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Name        string `json:"name"`
		Email       string `json:"email"`
		Phone       string `json:"phone"`
		Password    string `json:"password"`
		SalaryCents int64  `json:"salary_cents"`
	}
	if !decodeJSON(w, r, &input) {
		return
	}
	session, err := app.auth.Register(r.Context(), input.Name, input.Email, input.Phone, input.Password, input.SalaryCents)
	if errors.Is(err, auth.ErrInvalid) {
		writeAPIError(w, http.StatusUnprocessableEntity, "validation_failed", "name, valid email, Mexican mobile number, non-negative monthly salary, and an 8-character password are required", nil)
		return
	}
	if errors.Is(err, auth.ErrEmailInUse) {
		writeAPIError(w, http.StatusConflict, "email_already_registered", "email is already registered", map[string]string{"email": "already_registered"})
		return
	}
	if err != nil {
		serverError(w, "register", err)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusCreated, session)
}

func (app application) updateGroup(w http.ResponseWriter, r *http.Request) {
	var input groups.UpdateGroupInput
	if !decodeJSON(w, r, &input) {
		return
	}
	result, err := app.groups.Update(r.Context(), userID(r), r.PathValue("groupID"), input)
	if errors.Is(err, groups.ErrInvalid) {
		writeAPIError(w, http.StatusUnprocessableEntity, "validation_failed", "invalid group settings", nil)
		return
	}
	if errors.Is(err, groups.ErrNotFound) {
		writeAPIError(w, http.StatusNotFound, "resource_not_found", "group not found", nil)
		return
	}
	if err != nil {
		serverError(w, "update group", err)
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (app application) addMember(w http.ResponseWriter, r *http.Request) {
	var input groups.MemberInput
	if !decodeJSON(w, r, &input) {
		return
	}
	key, ok := idempotencyKey(w, r)
	if !ok {
		return
	}
	hash, hashErr := commandPayloadHash(input)
	if hashErr != nil {
		serverError(w, "hash add member", hashErr)
		return
	}
	groupID := r.PathValue("groupID")
	result, err := app.intents.Run(r.Context(), userID(r), opAddMember, groupID, key, hash, func(tx *sql.Tx) (int, any, error) {
		group, err := app.groups.AddMemberTx(r.Context(), tx, userID(r), groupID, input)
		return http.StatusCreated, group, err
	})
	if errors.Is(err, idempotency.ErrConflict) {
		writeConflict(w)
		return
	}
	if errors.Is(err, groups.ErrInvalid) {
		writeAPIError(w, http.StatusUnprocessableEntity, "validation_failed", "a member needs a name or Mexican mobile number", nil)
		return
	}
	if errors.Is(err, groups.ErrNotFound) {
		writeAPIError(w, http.StatusNotFound, "resource_not_found", "group not found", nil)
		return
	}
	if err != nil {
		serverError(w, "add member", err)
		return
	}
	writeJSON(w, result.Status, result.Body)
}

func (app application) updateMember(w http.ResponseWriter, r *http.Request) {
	var input groups.UpdateMemberInput
	if !decodeJSON(w, r, &input) {
		return
	}
	result, err := app.groups.UpdateMember(r.Context(), userID(r), r.PathValue("groupID"), r.PathValue("memberID"), input)
	if errors.Is(err, groups.ErrInvalid) {
		writeAPIError(w, http.StatusUnprocessableEntity, "validation_failed", "invalid member update or salary consent", nil)
		return
	}
	if errors.Is(err, groups.ErrNotFound) {
		writeAPIError(w, http.StatusNotFound, "resource_not_found", "group or member not found", nil)
		return
	}
	if err != nil {
		serverError(w, "update member", err)
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (app application) login(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if !decodeJSON(w, r, &input) {
		return
	}
	session, err := app.auth.Login(r.Context(), input.Email, input.Password)
	if errors.Is(err, auth.ErrInvalid) {
		writeAPIError(w, http.StatusUnauthorized, "invalid_credentials", "invalid email or password", nil)
		return
	}
	if err != nil {
		serverError(w, "login", err)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, session)
}

func (app application) refreshSession(w http.ResponseWriter, r *http.Request) {
	var input struct {
		RefreshToken string `json:"refresh_token"`
	}
	if !decodeJSON(w, r, &input) {
		return
	}
	session, err := app.auth.Refresh(r.Context(), input.RefreshToken)
	if errors.Is(err, auth.ErrUnauthorized) {
		writeAPIError(w, http.StatusUnauthorized, "invalid_refresh_token", "invalid or reused refresh token", nil)
		return
	}
	if err != nil {
		serverError(w, "refresh session", err)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, session)
}

func (app application) signOut(w http.ResponseWriter, r *http.Request) {
	if err := app.auth.RevokeSession(r.Context(), accessToken(r)); err != nil {
		if errors.Is(err, auth.ErrUnauthorized) {
			writeAPIError(w, http.StatusUnauthorized, "authentication_required", "authentication required", nil)
			return
		}
		serverError(w, "sign out", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (app application) signOutAll(w http.ResponseWriter, r *http.Request) {
	if err := app.auth.RevokeAll(r.Context(), userID(r)); err != nil {
		serverError(w, "sign out all", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func runHealthcheck() {
	client := http.Client{Timeout: 2 * time.Second}
	response, err := client.Get("http://127.0.0.1:" + getenv("PORT", "8080") + "/healthz")
	if err != nil || response.StatusCode != http.StatusOK {
		os.Exit(1)
	}
	response.Body.Close()
}

func (app application) health(w http.ResponseWriter, _ *http.Request) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if err := app.groups.Ping(ctx); err != nil {
		writeAPIError(w, http.StatusServiceUnavailable, "service_unavailable", "service unavailable", nil)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok", "service": "vaquita-api"})
}

func (app application) requireUser(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		token, found := strings.CutPrefix(header, "Bearer ")
		if !found || token == "" {
			writeAPIError(w, http.StatusUnauthorized, "authentication_required", "authentication required", nil)
			return
		}
		user, err := app.auth.UserForToken(r.Context(), token)
		if err != nil {
			writeAPIError(w, http.StatusUnauthorized, "authentication_required", "authentication required", nil)
			return
		}
		ctx := context.WithValue(r.Context(), userIDKey{}, user.ID)
		ctx = context.WithValue(ctx, accessTokenKey{}, token)
		next(w, r.WithContext(ctx))
	}
}

type userIDKey struct{}
type accessTokenKey struct{}

func userID(r *http.Request) string { return r.Context().Value(userIDKey{}).(string) }
func accessToken(r *http.Request) string {
	return r.Context().Value(accessTokenKey{}).(string)
}

func (app application) matchContacts(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Phones []string `json:"phones"`
	}
	if !decodeJSON(w, r, &input) {
		return
	}
	if len(input.Phones) > 500 {
		writeAPIError(w, http.StatusBadRequest, "request_limit_exceeded", "at most 500 contacts can be matched at once", map[string]string{"phones": "too_many"})
		return
	}
	phones := make([]string, 0, len(input.Phones))
	seen := map[string]bool{}
	for _, value := range input.Phones {
		if phone, ok := auth.NormalizePhone(value); ok && !seen[phone] {
			phones, seen[phone] = append(phones, phone), true
		}
	}
	contacts, err := app.auth.Contacts(r.Context(), userID(r), phones)
	if err != nil {
		serverError(w, "match contacts", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"contacts": contacts})
}

func (app application) listContacts(w http.ResponseWriter, r *http.Request) {
	contacts, err := app.auth.ListContacts(r.Context(), userID(r))
	if err != nil {
		serverError(w, "list contacts", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"contacts": contacts})
}
func (app application) saveContacts(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Contacts []auth.Contact `json:"contacts"`
	}
	if !decodeJSON(w, r, &input) {
		return
	}
	key, ok := idempotencyKey(w, r)
	if !ok {
		return
	}
	hash, hashErr := commandPayloadHash(input)
	if hashErr != nil {
		serverError(w, "hash save contacts", hashErr)
		return
	}
	result, err := app.intents.Run(r.Context(), userID(r), opSaveContacts, "", key, hash, func(tx *sql.Tx) (int, any, error) {
		contacts, err := app.auth.SaveContactsTx(r.Context(), tx, userID(r), input.Contacts)
		if err != nil {
			return 0, nil, err
		}
		return http.StatusOK, map[string]any{"contacts": contacts}, nil
	})
	if errors.Is(err, idempotency.ErrConflict) {
		writeConflict(w)
		return
	}
	if err != nil {
		serverError(w, "save contacts", err)
		return
	}
	writeJSON(w, result.Status, result.Body)
}

func (app application) removeContact(w http.ResponseWriter, r *http.Request) {
	err := app.auth.RemoveContact(r.Context(), userID(r), r.PathValue("contactID"))
	if errors.Is(err, auth.ErrInvalid) {
		writeAPIError(w, http.StatusNotFound, "resource_not_found", "contact not found", nil)
		return
	}
	if err != nil {
		serverError(w, "remove contact", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (app application) listGroups(w http.ResponseWriter, r *http.Request) {
	result, err := app.groups.List(r.Context(), userID(r))
	if err != nil {
		serverError(w, "list groups", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"groups": result})
}

func (app application) listInvitations(w http.ResponseWriter, r *http.Request) {
	result, err := app.groups.Invitations(r.Context(), userID(r))
	if err != nil {
		serverError(w, "list invitations", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"invitations": result})
}

func (app application) respondInvitation(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Accept bool `json:"accept"`
	}
	if !decodeJSON(w, r, &input) {
		return
	}
	key, ok := idempotencyKey(w, r)
	if !ok {
		return
	}
	hash, hashErr := commandPayloadHash(input)
	if hashErr != nil {
		serverError(w, "hash invitation response", hashErr)
		return
	}
	groupID := r.PathValue("groupID")
	result, err := app.intents.Run(r.Context(), userID(r), opRespondInvitation, groupID, key, hash, func(tx *sql.Tx) (int, any, error) {
		if err := app.groups.RespondInvitationTx(r.Context(), tx, userID(r), groupID, input.Accept); err != nil {
			return 0, nil, err
		}
		return http.StatusNoContent, nil, nil
	})
	if errors.Is(err, idempotency.ErrConflict) {
		writeConflict(w)
		return
	}
	if errors.Is(err, groups.ErrNotFound) {
		writeAPIError(w, http.StatusNotFound, "resource_not_found", "invitation not found", nil)
		return
	}
	if err != nil {
		serverError(w, "respond invitation", err)
		return
	}
	writeOutcome(w, commandOutcome{status: result.Status, body: result.Body})
}

func (app application) createGroup(w http.ResponseWriter, r *http.Request) {
	var input groups.CreateGroupInput
	if !decodeJSON(w, r, &input) {
		return
	}
	key, ok := idempotencyKey(w, r)
	if !ok {
		return
	}
	hash, hashErr := commandPayloadHash(input)
	if hashErr != nil {
		serverError(w, "hash create group", hashErr)
		return
	}
	result, err := app.intents.Run(r.Context(), userID(r), opCreateGroup, "", key, hash, func(tx *sql.Tx) (int, any, error) {
		group, err := app.groups.CreateTx(r.Context(), tx, userID(r), input)
		return http.StatusCreated, group, err
	})
	if errors.Is(err, idempotency.ErrConflict) {
		writeConflict(w)
		return
	}
	if errors.Is(err, groups.ErrInvalid) {
		writeAPIError(w, http.StatusUnprocessableEntity, "validation_failed", "a name, emoji, and at least one member are required", nil)
		return
	}
	if err != nil {
		serverError(w, "create group", err)
		return
	}
	writeJSON(w, result.Status, result.Body)
}

func (app application) syncLocalGroups(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Groups []groups.OfflineSyncGroupInput `json:"groups"`
	}
	if !decodeJSON(w, r, &input) {
		return
	}
	results, err := app.groups.SyncLocalGroups(r.Context(), userID(r), input.Groups)
	switch {
	case errors.Is(err, groups.ErrSyncConflict):
		writeAPIError(w, http.StatusConflict, "sync_conflict", "local history conflicts with previously synchronized data", nil)
	case errors.Is(err, groups.ErrInvalid):
		writeAPIError(w, http.StatusUnprocessableEntity, "validation_failed", "invalid local group data", nil)
	case errors.Is(err, groups.ErrOverpayment):
		writeAPIError(w, http.StatusUnprocessableEntity, "validation_failed", "local settlement exceeds the outstanding balance", nil)
	case errors.Is(err, groups.ErrNotFound):
		writeAPIError(w, http.StatusNotFound, "resource_not_found", "group not found", nil)
	case err != nil:
		serverError(w, "sync local groups", err)
	default:
		writeJSON(w, http.StatusOK, map[string]any{"groups": results})
	}
}

func (app application) addExpense(w http.ResponseWriter, r *http.Request) {
	var input groups.AddExpenseInput
	if !decodeJSON(w, r, &input) {
		return
	}
	key, ok := idempotencyKey(w, r)
	if !ok {
		return
	}
	hash, hashErr := commandPayloadHash(input)
	if hashErr != nil {
		serverError(w, "hash add expense", hashErr)
		return
	}
	groupID := r.PathValue("groupID")
	result, err := app.intents.Run(r.Context(), userID(r), opAddExpense, groupID, key, hash, func(tx *sql.Tx) (int, any, error) {
		group, err := app.groups.AddExpenseTx(r.Context(), tx, userID(r), groupID, input)
		return http.StatusCreated, group, err
	})
	if errors.Is(err, idempotency.ErrConflict) {
		writeConflict(w)
		return
	}
	if errors.Is(err, groups.ErrInvalid) {
		writeAPIError(w, http.StatusUnprocessableEntity, "validation_failed", "invalid expense or group member", nil)
		return
	}
	if errors.Is(err, groups.ErrNotFound) {
		writeAPIError(w, http.StatusNotFound, "resource_not_found", "group not found", nil)
		return
	}
	if err != nil {
		serverError(w, "add expense", err)
		return
	}
	writeJSON(w, result.Status, result.Body)
}

func (app application) addSettlement(w http.ResponseWriter, r *http.Request) {
	var input struct {
		MemberID    string `json:"member_id"`
		AmountCents *int64 `json:"amount_cents"`
	}
	if !decodeJSON(w, r, &input) {
		return
	}
	key, ok := idempotencyKey(w, r)
	if !ok {
		return
	}
	hash, hashErr := commandPayloadHash(input)
	if hashErr != nil {
		serverError(w, "hash add settlement", hashErr)
		return
	}
	groupID := r.PathValue("groupID")
	result, err := app.intents.Run(r.Context(), userID(r), opAddSettlement, groupID, key, hash, func(tx *sql.Tx) (int, any, error) {
		group, err := app.groups.AddSettlementTx(r.Context(), tx, userID(r), groupID, input.MemberID, input.AmountCents)
		return http.StatusCreated, group, err
	})
	if errors.Is(err, idempotency.ErrConflict) {
		writeConflict(w)
		return
	}
	if errors.Is(err, groups.ErrInvalid) {
		writeAPIError(w, http.StatusUnprocessableEntity, "validation_failed", "member has no balance to settle", nil)
		return
	}
	if errors.Is(err, groups.ErrOverpayment) {
		writeAPIError(w, http.StatusUnprocessableEntity, "validation_failed", "amount exceeds the outstanding balance", nil)
		return
	}
	if errors.Is(err, groups.ErrNotFound) {
		writeAPIError(w, http.StatusNotFound, "resource_not_found", "group not found", nil)
		return
	}
	if err != nil {
		serverError(w, "add settlement", err)
		return
	}
	writeJSON(w, result.Status, result.Body)
}

func (app application) confirmReceivedSettlement(w http.ResponseWriter, r *http.Request) {
	var input struct {
		DebtorMemberID string `json:"debtor_member_id"`
		AmountCents    *int64 `json:"amount_cents"`
	}
	if !decodeJSON(w, r, &input) {
		return
	}
	key, ok := idempotencyKey(w, r)
	if !ok {
		return
	}
	hash, hashErr := commandPayloadHash(input)
	if hashErr != nil {
		serverError(w, "hash received settlement", hashErr)
		return
	}
	groupID := r.PathValue("groupID")
	result, err := app.intents.Run(r.Context(), userID(r), opConfirmReceived, groupID, key, hash, func(tx *sql.Tx) (int, any, error) {
		group, err := app.groups.ConfirmReceivedSettlementTx(r.Context(), tx, userID(r), groupID, input.DebtorMemberID, input.AmountCents)
		return http.StatusCreated, group, err
	})
	if errors.Is(err, idempotency.ErrConflict) {
		writeConflict(w)
		return
	}
	if errors.Is(err, groups.ErrInvalid) {
		writeAPIError(w, http.StatusUnprocessableEntity, "validation_failed", "member has no balance to settle", nil)
		return
	}
	if errors.Is(err, groups.ErrOverpayment) {
		writeAPIError(w, http.StatusUnprocessableEntity, "validation_failed", "amount exceeds the outstanding balance", nil)
		return
	}
	if errors.Is(err, groups.ErrNotFound) {
		writeAPIError(w, http.StatusNotFound, "resource_not_found", "group or receivable balance not found", nil)
		return
	}
	if err != nil {
		serverError(w, "confirm received settlement", err)
		return
	}
	writeJSON(w, result.Status, result.Body)
}

func (app application) removeMember(w http.ResponseWriter, r *http.Request) {
	err := app.groups.RemoveMember(r.Context(), userID(r), r.PathValue("groupID"), r.PathValue("memberID"))
	if errors.Is(err, groups.ErrInvalid) {
		writeAPIError(w, http.StatusUnprocessableEntity, "validation_failed", "you cannot remove yourself", nil)
		return
	}
	if errors.Is(err, groups.ErrNotFound) {
		writeAPIError(w, http.StatusNotFound, "resource_not_found", "member not found", nil)
		return
	}
	if err != nil {
		serverError(w, "remove member", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (app application) unpaid(w http.ResponseWriter, r *http.Request) {
	result, err := app.groups.Unpaid(r.Context(), userID(r), r.PathValue("groupID"))
	if errors.Is(err, groups.ErrNotFound) {
		writeAPIError(w, http.StatusNotFound, "resource_not_found", "group not found", nil)
		return
	}
	if err != nil {
		serverError(w, "unpaid", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"balances": result})
}

func (app application) status(w http.ResponseWriter, r *http.Request) {
	result, err := app.groups.Status(r.Context(), userID(r))
	if err != nil {
		serverError(w, "status", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"contacts": result})
}

func (app application) providers(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"active": app.payments.Name(),
		"providers": []map[string]any{{
			"id": app.payments.Name(), "live": false,
		}},
	})
}

func (app application) createPaymentRequest(w http.ResponseWriter, r *http.Request) {
	var input payments.CreateRequest
	if !decodeJSON(w, r, &input) {
		return
	}
	key := strings.TrimSpace(r.Header.Get("Idempotency-Key"))
	if key == "" || len(key) > 128 {
		writeAPIError(w, http.StatusBadRequest, "idempotency_key_required", "a valid Idempotency-Key is required", map[string]string{"Idempotency-Key": "required"})
		return
	}
	payloadHash, err := paymentPayloadHash(input)
	if err != nil {
		serverError(w, "hash payment request", err)
		return
	}
	if existing, found, err := app.requests.FindIdempotent(r.Context(), userID(r), key, payloadHash); err != nil {
		if errors.Is(err, payments.ErrIdempotencyConflict) {
			writeAPIError(w, http.StatusConflict, "idempotency_key_conflict", "Idempotency-Key was already used with a different request", nil)
			return
		}
		serverError(w, "find idempotent payment request", err)
		return
	} else if found {
		writeJSON(w, http.StatusOK, existing)
		return
	}
	if err := app.groups.ValidatePaymentRequest(r.Context(), userID(r), input.GroupID, input.DebtorID, input.AmountCents); err != nil {
		if errors.Is(err, groups.ErrNotFound) {
			writeAPIError(w, http.StatusNotFound, "resource_not_found", "group not found", nil)
			return
		}
		if errors.Is(err, groups.ErrInvalid) {
			writeAPIError(w, http.StatusUnprocessableEntity, "validation_failed", "payment request must match the debtor's current balance with you", nil)
			return
		}
		serverError(w, "validate payment request", err)
		return
	}
	creditorMemberID, err := app.requests.CreditorMemberID(r.Context(), userID(r), input.GroupID)
	if err != nil {
		serverError(w, "find payment request creditor", err)
		return
	}
	// The provider needs the receiver reference to authenticate its side of
	// the payment; it is derived server-side from the authenticated user and
	// excluded from the idempotency hash (json:"-").
	input.CreditorID = creditorMemberID
	result, err := app.payments.CreateRequest(r.Context(), input)
	if errors.Is(err, payments.ErrInvalidRequest) {
		writeAPIError(w, http.StatusUnprocessableEntity, "validation_failed", "group_id, debtor_id, a positive amount_cents, and currency MXN are required", nil)
		return
	}
	if err != nil {
		serverError(w, "create payment request", err)
		return
	}
	stored, created, err := app.requests.Create(r.Context(), userID(r), key, payloadHash, creditorMemberID, result, input)
	if errors.Is(err, payments.ErrIdempotencyConflict) {
		writeAPIError(w, http.StatusConflict, "idempotency_key_conflict", "Idempotency-Key was already used with a different request", nil)
		return
	}
	if err != nil {
		serverError(w, "persist payment request", err)
		return
	}
	if !created {
		writeJSON(w, http.StatusOK, stored)
		return
	}
	writeJSON(w, http.StatusCreated, stored)
}

func (app application) completeSimulatedPayment(w http.ResponseWriter, r *http.Request) {
	var input struct {
		ProviderEventID string `json:"provider_event_id"`
	}
	if !decodeJSON(w, r, &input) {
		return
	}
	result, created, err := app.requests.CompleteSimulated(r.Context(), userID(r), r.PathValue("requestID"), input.ProviderEventID)
	if errors.Is(err, payments.ErrNotFound) {
		writeAPIError(w, http.StatusNotFound, "resource_not_found", "payment request not found", nil)
		return
	}
	if errors.Is(err, payments.ErrInvalidEvent) {
		writeAPIError(w, http.StatusUnprocessableEntity, "validation_failed", "invalid or expired simulated payment event", nil)
		return
	}
	if err != nil {
		serverError(w, "complete simulated payment", err)
		return
	}
	if !created {
		writeJSON(w, http.StatusOK, result)
		return
	}
	writeJSON(w, http.StatusCreated, result)
}

func paymentPayloadHash(input payments.CreateRequest) (string, error) {
	encoded, err := json.Marshal(input)
	if err != nil {
		return "", err
	}
	digest := sha256.Sum256(encoded)
	return hex.EncodeToString(digest[:]), nil
}
