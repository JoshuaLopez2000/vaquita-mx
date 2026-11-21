# Architecture

## System context

```text
Flutter Android app
        |
        | HTTPS / JSON
        v
Go API ---- PostgreSQL
  |             |
  |             +-- users, groups, expenses, obligations, settlements
  |
  +-- job worker / reminders (later)
  |
  +-- PaymentProvider
        |-- SimulatedProvider (included)
        `-- CoDiProvider (requires registration and certification)
```

The mobile app stores offline groups, cached server-backed groups, and an
account-scoped `pending_mutations` outbox in a local SQLite database
(`OfflineDatabase` v2) on supported native platforms. It can be used before
authentication; the user chooses from Profile whether to upload local-only
groups after logging in or signing up. Mutations to groups already stored on
the server use the authenticated API while online, and queue expenses,
personal-group settlements, and shared-group received-payment confirmations in
SQLite when offline or on transient transport errors for automatic FIFO replay
with stable `Idempotency-Key` headers when connectivity returns. Local-only
groups and their ledger history remain on-device until sync is explicitly
enabled. The web build currently keeps local data and queued mutations in
memory only. The mobile application never connects directly to PostgreSQL or
holds provider secrets. The API remains authoritative for synced calculations
and state transitions.

## Proposed modules

- **Identity:** accounts, sessions, device registrations, and account recovery.
- **Groups:** membership, invitations, and authorization.
- **Expenses:** expense headers, payers, allocations, and attachments.
- **Ledger:** obligations, settlements, balance projections, and audit events.
- **Payments:** provider requests, callbacks, idempotency, and reconciliation.
- **Notifications:** push registrations, reminders, and delivery tracking.

Start as a modular monolith. It is simpler to operate, preserves transactional consistency, and still demonstrates clean boundaries. Extract services only when measured operational needs justify it.

## Core data model

```text
User 1---* GroupMember *---1 Group
Group 1---* Expense
Expense 1---* ExpensePayer
Expense 1---* ExpenseShare
ExpenseShare 1---* PaymentRequest
PaymentRequest 1---* ProviderEvent
ExpenseShare 1---* Settlement
```

Recommended database rules:

- Monetary columns use `BIGINT` centavos and currency is `CHAR(3)`.
- IDs are UUIDv7 or ULID values generated on the server.
- Expense shares must sum exactly to the expense total.
- Percentage splits store fixed-point integer basis points (`percentage_bps`,
  `1..10000`, summing to `10000` = `100.00%`) alongside the immutable final
  centavo share in `expense_shares`. Leftover centavos are allocated by
  largest exact remainder `(total * bps) % 10000` descending, breaking ties in
  stored `participant_ids` order. Stored final centavo shares drive ledger
  balances; client offline calculations use the identical `BigInt` algorithm.
- Group responses include a deterministic bilateral debt projection derived
  from expense shares and direct settlements. It is a read model, never a
  financial record; settlements remain the authoritative immutable history.
- Provider event IDs and idempotency keys have unique constraints.
- Simulator requests, callbacks, and their settlement reference are stored in
  one PostgreSQL transaction; a callback replay can never create another
  settlement.
- Financial rows are reversed with compensating entries rather than deleted.
  `expense_reversals` (`UNIQUE(original_expense_id)`) and
  `settlement_reversals` (`UNIQUE(original_settlement_id)`) stay separate,
  record actor, reason (`1..500` chars), and timestamp, and negate the original
  record's exact integer-centavo ledger effect once. Optional
  `expenses.replaces_expense_id` and `settlements.replaces_settlement_id`
  (`UNIQUE WHERE NOT NULL`) link a separate immutable replacement record to an
  already-reversed entry in the same group without modifying the original row.
- All records use UTC timestamps; presentation uses the user's time zone.

## API conventions

- Prefix endpoints with `/api/v1`.
- Authenticate with short-lived access tokens and rotated refresh tokens.
- Require an `Idempotency-Key` for payment-request creation; group, member,
  expense, settlement, invitation-response, and contact commands accept an
  optional key to replay a stored outcome while preserving legacy behavior.
- Return stable machine error codes alongside user-safe messages.
- Publish an OpenAPI document as endpoints mature.
- Propagate a request/correlation ID through logs and provider calls.

## Initial API

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/healthz` | Hosting health probe |
| `GET` | `/api/v1/groups` | Load groups, members, expenses, and settlements |
| `POST` | `/api/v1/groups` | Create a group and its members |
| `POST` | `/api/v1/groups/{id}/expenses` | Add an expense (equal, percentage, salary, or exact split; optional `replaces_expense_id`) |
| `POST` | `/api/v1/groups/{id}/expenses/{expenseId}/reversals` | Record an immutable compensating reversal for a posted expense |
| `POST` | `/api/v1/groups/{id}/settlements` | Record a manual settlement in a personal group (optional `replaces_settlement_id`) |
| `POST` | `/api/v1/groups/{id}/settlements/received` | Authenticated creditor confirmation of a full or partial received payment (optional `replaces_settlement_id`) |
| `POST` | `/api/v1/groups/{id}/settlements/{settlementId}/reversals` | Record an immutable compensating reversal for a posted settlement |
| `POST` | `/api/v1/offline-sync/groups` | Authenticated, opt-in merge of local groups and ledger history |
| `GET` | `/api/v1/payment-providers` | Active provider capabilities |
| `POST` | `/api/v1/payment-requests` | Create a simulated MXN request |
| `POST` | `/api/v1/payment-requests/{id}/simulate` | Complete a simulated payment |

Offline sync is disabled per account until the user chooses to sync. The
client uploads local groups with stable local IDs; the API records local-to-
server group/member mappings and hashes of synced expenses and settlements so
retries are idempotent and edits to already-synced financial records are
rejected. Existing account groups are preserved and merged rather than
replaced. Each group is committed transactionally, so a failed multi-group
request can be retried without duplicating already-committed groups. Group
invitations are created only as part of this explicit sync operation.

An authenticated mutation to a group that is already server-backed uses its
idempotent API endpoint (`POST /groups/{id}/expenses`,
`POST /groups/{id}/expenses/{expenseId}/reversals`,
`POST /groups/{id}/settlements`, `POST /groups/{id}/settlements/received`,
`POST /groups/{id}/settlements/{settlementId}/reversals`)
directly when online. When offline, when the group already has queued mutations
(preserving FIFO order), or when a transient transport/5xx failure leaves the
outcome unknown, the client applies the optimistic integer-centavo entry
locally and persists a `pending_mutations` outbox row scoped to the signed-in
`account_id` with a stable `Idempotency-Key`. On reconnect, queued mutations
replay in FIFO order independently of the pre-login local-group sync opt-in;
`load()` preserves groups with pending mutations until their outbox drains,
then refreshes authoritative server state (including server-computed salary
shares). Permanent 4xx rejections mark the entry `failed` without blocking
other queued mutations, allowing explicit retry or discard. Mutations to
local-only groups (including local reversals and linked replacements) remain
persisted locally and are uploaded chronologically only after the account's
explicit sync opt-in; local unsynced entries on server-backed groups must sync
before they can be reversed.

Manual payment requests are available only for authenticated shared groups.
In shared groups, `POST /groups/{id}/settlements/received` records a full or
partial receipt only for the authenticated creditor's exact bilateral
receivable. Personal-group owners may record settlements in either direction.
Unauthenticated local groups are always personal; their full or partial
settlements are stored locally and do not call the server or imply a transfer.

Manual payment requests are available only for authenticated shared groups.
In shared groups, `POST /groups/{id}/settlements/received` records a full or
partial receipt only for the authenticated creditor's exact bilateral
receivable. Personal-group owners may record settlements in either direction.
Unauthenticated local groups are always personal; their full or partial
settlements are stored locally and do not call the server or imply a transfer.

Simulated payment completion revalidates the bilateral ledger inside the
completion transaction and stores the outstanding debtor/creditor balance in
`payment_provider_events.outstanding_cents`. Amounts are never capped at
completion: when the outstanding debt shrank between creation and the callback
(such as a partial settlement in between), the payment completes in full and
the difference is projected as the receiver's debt to the payer. The
annotation keeps every overpayment traceable in the immutable event history.

### Payment reconciliation job (Phase 2)

A `payments.Reconciler` runs inside the API process (30 second interval in
development). Each cycle:

1. Claims due `PENDING` payment requests with `FOR UPDATE SKIP LOCKED` plus a
   lease on `payment_requests.reconcile_after`, so concurrent workers and
   crashed workers pair up correctly.
2. Asks the active provider adapter for the request's own record through the
   opaque `provider_ref` returned at creation.
3. Applies a provider-confirmed `PAID` state exactly once through the same
   completion transaction as client callbacks, matching amount, MXN currency,
   receiver, and correlation ID first.
4. Closes requests the provider reports as `EXPIRED` or `FAILED`, retries
   provider outages with bounded exponential backoff (`max 5` fruitless
   attempts), and parks unresolved mismatches in `payment_reconcile_events`
   with a `MANUAL` outcome.

Pending requests untouched by matching provider state simply reschedule; only
settlement-grade divergence reaches manual review.

The development endpoints are intentionally unauthenticated to make the local vertical slice easy to exercise. Authentication is required before any non-local deployment exposes domain mutations.
