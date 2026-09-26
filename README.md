# Vaquita MX

Vaquita MX is a portfolio-grade group expense application for Mexico. A group can record an expense, identify who paid, calculate what each member owes, and issue individual payment requests. The production design supports Banco de Mexico's CoDi collection workflow through a replaceable payment-provider adapter.

> The repository does not claim live or certified CoDi access. The included provider is a simulator. A real CoDi integration requires the applicable registration, certification, credentials, message signing, and operational controls.

## Repository status

This is a portfolio demonstration with a working local vertical slice:

- `apps/mobile`: Flutter application targeting Android.
- `services/api`: dependency-free Go HTTP API with health and simulated payment-request endpoints.
- `docs`: product, architecture, CoDi, security, deployment, and delivery documentation.
- `deploy`: deployment assets.

## Portfolio scope and demo boundaries

- The payment provider is a simulator. It creates a deep-link-shaped request only; it never initiates, verifies, or settles a real transfer.
- A simulated settlement is a deliberate demo action. A production release must replace it with an authenticated, idempotent provider callback and reconciliation flow.
- Payment requests require an authenticated payer and must match a participant's exact share of a recorded expense. They are not persisted payment instruments.
- Release builds must be signed with `RELEASE_STORE_FILE`, `RELEASE_STORE_PASSWORD`, `RELEASE_KEY_ALIAS`, and `RELEASE_KEY_PASSWORD`. Those values are intentionally not committed.

## Local API

Requirements: Go 1.24 or newer.

```bash
cd services/api
go test ./...
go run ./cmd/api
```

The API listens on `http://localhost:8080` by default.

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

With Docker Desktop running:

```bash
docker compose up --detach --build --wait
docker compose ps
```

The API is then available at `http://localhost:8080`; PostgreSQL stays private to the Compose network. Groups, expenses, and settlements created by the Android app are stored in PostgreSQL and survive container restarts. Stop the services while preserving database data with:

```bash
docker compose down
```

## Flutter application

Requirements: Flutter stable with the Android SDK configured.

```bash
cd apps/mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

`10.0.2.2` routes from the Android emulator to Docker on the host machine. Keep the Compose stack running while using the app. For a physical Android device, use the computer's reachable LAN address during development; production builds must use an HTTPS server.

The standard Android runner is committed with the project. Product application code lives under `lib/`.

## Documentation

- [Product definition](docs/PRODUCT.md)
- [Architecture](docs/ARCHITECTURE.md)
- [API reference](docs/API.md)
- [CoDi integration strategy](docs/CODI_INTEGRATION.md)
- [Security](docs/SECURITY.md)
- [Remote deployment](docs/DEPLOYMENT.md)
- [Roadmap](docs/ROADMAP.md)

## Working agreements

- Amounts are integer centavos; floating point is forbidden for money.
- The first release is MXN-only.
- Expense history and settlement history are separate.
- Payment callbacks must be authenticated and idempotent.
- Secrets never enter the mobile binary or Git history.

## License

No license has been selected yet. Add one before accepting external contributions.
