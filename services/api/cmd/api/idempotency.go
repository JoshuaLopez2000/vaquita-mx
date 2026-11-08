package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"strings"
)

// Operation labels remember each command intent per authenticated user, per
// operation, and per target scope, so reusing a key value across commands or
// across groups can never replay another command's stored result.
const (
	opCreateGroup       = "POST /groups"
	opAddMember         = "POST /groups/{groupID}/members"
	opAddExpense        = "POST /groups/{groupID}/expenses"
	opAddSettlement     = "POST /groups/{groupID}/settlements"
	opRespondInvitation = "POST /group-invitations/{groupID}/response"
	opSaveContacts      = "POST /contacts"
)

// commandOutcome is one concluded command run. Replayed outcomes carry the
// stored response as json.RawMessage, which writeJSON encodes verbatim.
type commandOutcome struct {
	status int
	body   any
}

// idempotencyKey extracts and validates the optional header. An absent header
// keeps the previous per-command behavior; a present value over 128
// characters is rejected instead of accepted silently. The bool is false when
// an error response was already written.
func idempotencyKey(w http.ResponseWriter, r *http.Request) (string, bool) {
	key := strings.TrimSpace(r.Header.Get("Idempotency-Key"))
	if key == "" {
		return "", true
	}
	if len(key) > 128 {
		writeAPIError(w, http.StatusBadRequest, "idempotency_key_invalid", "Idempotency-Key must be 1 to 128 bytes", map[string]string{"Idempotency-Key": "invalid"})
		return "", false
	}
	return key, true
}

// commandPayloadHash hashes the decoded request body. Retries must repeat the
// same payload to replay; any semantic difference under the same key
// conflicts (409 idempotency_key_conflict).
func commandPayloadHash(payload any) (string, error) {
	encoded, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(encoded)
	return hex.EncodeToString(sum[:]), nil
}

// writeOutcome writes a command's response. Repeated requests replay the
// stored status exactly, and no-content commands never gain a body.
func writeOutcome(w http.ResponseWriter, outcome commandOutcome) {
	if outcome.status == http.StatusNoContent {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	writeJSON(w, outcome.status, outcome.body)
}

// writeConflict maps a reused key with a different payload to the shared
// 409 error envelope.
func writeConflict(w http.ResponseWriter) {
	writeAPIError(w, http.StatusConflict, "idempotency_key_conflict", "Idempotency-Key was already used with a different request", nil)
}
