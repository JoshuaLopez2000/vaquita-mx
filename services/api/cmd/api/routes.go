package main

import "net/http"

func (app application) routes(allowedOrigins string) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", app.health)
	mux.HandleFunc("POST /api/v1/auth/register", app.register)
	mux.HandleFunc("POST /api/v1/auth/login", app.login)
	mux.HandleFunc("POST /api/v1/auth/refresh", app.refreshSession)
	mux.HandleFunc("POST /api/v1/auth/sign-out", app.requireUser(app.signOut))
	mux.HandleFunc("POST /api/v1/auth/sign-out-all", app.requireUser(app.signOutAll))
	mux.HandleFunc("POST /api/v1/contacts/matches", app.requireUser(app.matchContacts))
	mux.HandleFunc("GET /api/v1/contacts", app.requireUser(app.listContacts))
	mux.HandleFunc("POST /api/v1/contacts", app.requireUser(app.saveContacts))
	mux.HandleFunc("DELETE /api/v1/contacts/{contactID}", app.requireUser(app.removeContact))
	mux.HandleFunc("GET /api/v1/groups", app.requireUser(app.listGroups))
	mux.HandleFunc("POST /api/v1/offline-sync/groups", app.requireUser(app.syncLocalGroups))
	mux.HandleFunc("GET /api/v1/group-invitations", app.requireUser(app.listInvitations))
	mux.HandleFunc("POST /api/v1/group-invitations/{groupID}/response", app.requireUser(app.respondInvitation))
	mux.HandleFunc("POST /api/v1/groups", app.requireUser(app.createGroup))
	mux.HandleFunc("PATCH /api/v1/groups/{groupID}", app.requireUser(app.updateGroup))
	mux.HandleFunc("POST /api/v1/groups/{groupID}/members", app.requireUser(app.addMember))
	mux.HandleFunc("PATCH /api/v1/groups/{groupID}/members/{memberID}", app.requireUser(app.updateMember))
	mux.HandleFunc("POST /api/v1/groups/{groupID}/expenses", app.requireUser(app.addExpense))
	mux.HandleFunc("POST /api/v1/groups/{groupID}/settlements", app.requireUser(app.addSettlement))
	mux.HandleFunc("POST /api/v1/groups/{groupID}/settlements/received", app.requireUser(app.confirmReceivedSettlement))
	mux.HandleFunc("DELETE /api/v1/groups/{groupID}/members/{memberID}", app.requireUser(app.removeMember))
	mux.HandleFunc("GET /api/v1/groups/{groupID}/unpaid", app.requireUser(app.unpaid))
	mux.HandleFunc("GET /api/v1/status", app.requireUser(app.status))
	mux.HandleFunc("GET /api/v1/payment-providers", app.providers)
	// The simulator is protected and validates its input against the ledger. It
	// remains a portfolio/demo boundary; it does not move money or settle debt.
	mux.HandleFunc("POST /api/v1/payment-requests", app.requireUser(app.createPaymentRequest))
	mux.HandleFunc("POST /api/v1/payment-requests/{requestID}/simulate", app.requireUser(app.completeSimulatedPayment))
	mux.HandleFunc("/", func(w http.ResponseWriter, _ *http.Request) {
		writeAPIError(w, http.StatusNotFound, "resource_not_found", "resource not found", nil)
	})
	return correlationIDs(requestLogger(cors(mux, allowedOrigins)))
}
