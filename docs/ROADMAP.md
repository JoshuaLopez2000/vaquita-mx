# Roadmap

## Phase 0 — foundation (current)

- Monorepo layout and documentation.
- Flutter product shell.
- Go API health endpoint.
- Payment-provider interface and simulator.
- API unit tests and container definition.

## Phase 1 — usable group ledger

- PostgreSQL migrations and repository layer.
- Registration, login, refresh sessions, and account recovery.
- Groups, invite links, and membership roles.
- Expenses, multiple payers, and exact split validation.
- Balance projection with deterministic centavo rounding.
- Flutter navigation, state management, API client, and offline-safe forms.

## Phase 2 — settlements

- Persisted payment requests and idempotency keys.
- Partial settlements and immutable ledger entries.
- Simulator callbacks, replay protection, and reconciliation job.
- Firebase Cloud Messaging reminders.
- Activity timeline and CSV export.

## Phase 3 — production quality

- OpenAPI contract and generated Dart client.
- Integration, end-to-end, and property-based money tests.
- Observability, backups, rate limiting, and security review.
- CI/CD, remote staging, and internal Android distribution.
- Spanish and English localization plus accessibility review.

## Phase 4 — certified provider path

- Confirm current Banco de Mexico requirements.
- Complete the applicable registration and certification process.
- Implement cryptographic signing and secure key custody.
- Add certified sandbox conformance tests.
- Enable the live adapter only after formal approval.
