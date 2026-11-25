# Vaquita MX

Vaquita MX is a portfolio-grade, offline-first group expense application for Mexico. A group can record an expense, identify one or multiple payers, deterministically allocate every centavo across four split modes, correct mistakes through immutable compensating reversals, and issue individual payment requests. The production design supports Banco de Mexico's CoDi collection workflow through a replaceable payment-provider adapter.

> The repository does not claim live or certified CoDi access. The included provider is a simulator. A real CoDi integration requires the applicable registration, certification, credentials, message signing, and operational controls.

## Screenshots

<p align="center">
  <img src="docs/screenshots/01-dashboard.png" alt="Vaquita MX dashboard showing net balance across shared groups" width="84%">
</p>

<table>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/screenshots/02-group-detail.png" alt="Shared group detail with salary-based splits and bilateral member balances" width="100%">
      <p align="center"><sub><strong>Shared group detail</strong> — bilateral balances, salary-proportional splits, and group expenses</sub></p>
    </td>
    <td width="50%" valign="top">
      <img src="docs/screenshots/03-payment-request-sheet.png" alt="Simulated payment request and creditor receipt confirmation sheet" width="100%">
      <p align="center"><sub><strong>Collection & settlement sheet</strong> — CoDi-ready payment request with explicit demo-mode disclosure</sub></p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/screenshots/04-inbox.png" alt="Bandeja inbox showing shared group invitations and bilateral contact balances" width="100%">
      <p align="center"><sub><strong>Bandeja (Inbox)</strong> — pending shared-group invitations and cross-group contact balances</sub></p>
    </td>
    <td width="50%" valign="top">
      <img src="docs/screenshots/05-movements-reversals.png" alt="Movements feed showing expenses, compensating reversals, and settlements" width="100%">
      <p align="center"><sub><strong>Immutable ledger & reversals</strong> — separate expense, settlement, and compensating-entry history</sub></p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/screenshots/06-contact-balance.png" alt="Per-contact balance details grouped by shared expenses" width="100%">
      <p align="center"><sub><strong>Contact balance breakdown</strong> — net bilateral position itemized by group and concept</sub></p>
    </td>
    <td width="50%" valign="top">
      <img src="docs/screenshots/07-financial-statistics.png" alt="Financial statistics sheet showing distributed and retained overpayments" width="100%">
      <p align="center"><sub><strong>Financial statistics</strong> — distributed vs. retained tips and overpayments by period</sub></p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/screenshots/08-contacts.png" alt="Contacts directory with phone import support" width="100%">
      <p align="center"><sub><strong>Contacts</strong> — saved Mexican mobile contacts and opt-in phone import</sub></p>
    </td>
    <td width="50%" valign="top">
      <img src="docs/screenshots/09-profile.png" alt="Account profile with opt-in local group sync and settings" width="100%">
      <p align="center"><sub><strong>Profile & sync</strong> — account status, opt-in local SQLite group sync, and bilingual preferences</sub></p>
    </td>
  </tr>
</table>

## Repository status

This is a portfolio demonstration with a working full-stack vertical slice:

- `apps/mobile`: offline-first Flutter application targeting Android and web (SQLite local persistence, outbox replay, bilingual ES/EN copy, and light/dark Material 3 UI).
- `services/api`: Go HTTP modular monolith backed by PostgreSQL migrations, rotating refresh sessions, deterministic centavo ledger, compensating reversals, idempotency keys, and simulated payment-request endpoints.
- `docs`: product, architecture, CoDi, security, deployment, and delivery documentation.
- `deploy`: deployment assets.

## Portfolio scope and demo boundaries

- The payment provider is a simulator. It creates a deep-link-shaped request only; it never initiates, verifies, or settles a real transfer.
- A simulated settlement is a deliberate demo action. A production release must replace it with an authenticated, idempotent provider callback and reconciliation flow.
- Payment requests require an authenticated payer and must match a participant's exact share of a recorded expense. They are not persisted payment instruments.
- Release builds must be signed with `RELEASE_STORE_FILE`, `RELEASE_STORE_PASSWORD`, `RELEASE_KEY_ALIAS`, and `RELEASE_KEY_PASSWORD`. Those values are intentionally not committed.

## Local API

Requirements: Go 1.26.6 or newer.

```bash
cd services/api
go test ./...
go run ./cmd/api migrate
go run ./cmd/api
```

PostgreSQL-backed API and migration tests run when `TEST_DATABASE_URL` points
to a disposable database. Each test creates and removes its own schema, so the
suite is repeatable and safe for parallel CI jobs. Never point it at a database
containing data you need to preserve.

```bash
TEST_DATABASE_URL=postgres://postgres:postgres@localhost:5432/vaquita_test?sslmode=disable \
  go test ./... -count=1
```

The API listens on `http://localhost:8080` by default.

Authentication returns a 15-minute access token and a rotating refresh token
for a 30-day device session. Apply migrations before starting the API; migration
`0003_rotating_sessions` bounds pre-existing bearer sessions to a 15-minute
transition window.

```bash
curl http://localhost:8080/healthz
curl http://localhost:8080/api/v1/payment-providers
```

Create a simulated request:

```bash
curl -X POST http://localhost:8080/api/v1/payment-requests \
  -H "Content-Type: application/json" \
  -d '{"group_id":"trip-2026","expense_id":"dinner-1","debtor_id":"user-2","amount_cents":40000,"currency":"MXN","description":"Dinner share"}'
```

## Local containers

With Docker Desktop running, Compose waits for PostgreSQL, applies all pending
versioned migrations in a one-off container, and only then starts the API:

```bash
docker compose up --detach --build --wait
docker compose ps
```

The API is then available at `http://localhost:8080`; PostgreSQL stays private to the Compose network. Groups, expenses, and settlements created by the Android app are stored in PostgreSQL and survive container restarts. Stop the services while preserving database data with:

```bash
docker compose down
```

## Flutter application

Requirements: Flutter stable with the Android SDK configured for Android builds. A Chrome-based browser is sufficient for web development.

```bash
cd apps/mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

`10.0.2.2` routes from the Android emulator to Docker on the host machine. Keep the Compose stack running while using the app. For a physical Android device, use the computer's reachable LAN address during development; production builds must use an HTTPS server.

To run the web version against the local API:

```bash
flutter run -d chrome --web-port=3000
```

On web, the app defaults to `http://localhost:8080`, rather than the Android-emulator-only `10.0.2.2`. The API permits cross-origin requests from local web development by default; set `ALLOWED_ORIGINS` to a comma-separated allowlist of HTTPS frontend origins when deploying. Product application code lives under `lib/`.

## Documentation

- [Product definition](docs/PRODUCT.md)
- [Architecture](docs/ARCHITECTURE.md)
- [API reference](docs/API.md)
- [CoDi integration strategy](docs/CODI_INTEGRATION.md)
- [Security](docs/SECURITY.md)
- [Remote deployment](docs/DEPLOYMENT.md)
- [Roadmap](docs/ROADMAP.md)
- [Delivery workflow](docs/WORKFLOW.md)

## Working agreements

- Amounts are integer centavos; floating point is forbidden for money.
- The first release is MXN-only.
- Expense history and settlement history are separate.
- Payment callbacks must be authenticated and idempotent.
- Secrets never enter the mobile binary or Git history.

## License

No license has been selected yet. Add one before accepting external contributions.
