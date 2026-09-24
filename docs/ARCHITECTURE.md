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

The mobile application never connects directly to the database or holds provider secrets. All authoritative calculations and state transitions happen on the API.

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
- Provider event IDs and idempotency keys have unique constraints.
- Financial rows are reversed with compensating entries rather than deleted.
- All records use UTC timestamps; presentation uses the user's time zone.

## API conventions

- Prefix endpoints with `/api/v1`.
- Authenticate with short-lived access tokens and rotated refresh tokens.
- Require an `Idempotency-Key` for request creation and settlement commands.
- Return stable machine error codes alongside user-safe messages.
- Publish an OpenAPI document as endpoints mature.
- Propagate a request/correlation ID through logs and provider calls.

## Initial API

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/healthz` | Hosting health probe |
| `GET` | `/api/v1/payment-providers` | Active provider capabilities |
| `POST` | `/api/v1/payment-requests` | Create a simulated MXN request |

The initial endpoint is intentionally unauthenticated only to make the skeleton easy to exercise. Authentication is required before any non-local deployment exposes domain mutations.
