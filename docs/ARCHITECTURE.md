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

The mobile app stores offline groups and ledger history in a local SQLite
database on supported native platforms. It can be used before authentication;
the user chooses from Profile whether to upload local groups after logging in
or signing up. The web build currently keeps local data in memory only. The
mobile application never connects directly to PostgreSQL or holds provider
secrets. The API remains authoritative for synced calculations and state
transitions.

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
- Group responses include a deterministic bilateral debt projection derived
  from expense shares and direct settlements. It is a read model, never a
  financial record; settlements remain the authoritative immutable history.
- Provider event IDs and idempotency keys have unique constraints.
- Simulator requests, callbacks, and their settlement reference are stored in
  one PostgreSQL transaction; a callback replay can never create another
  settlement.
- Financial rows are reversed with compensating entries rather than deleted.
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
| `POST` | `/api/v1/groups/{id}/expenses` | Add an equally split expense |
| `POST` | `/api/v1/groups/{id}/settlements` | Record a simulated settlement |
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
