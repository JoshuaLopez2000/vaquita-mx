# Vaquita MX contributor instructions

## Product and architecture

Vaquita MX is a Mexico-focused group-expense application. The Flutter client
lives in `apps/mobile`; the Go API and PostgreSQL repositories live in
`services/api`. Keep the backend as a modular monolith unless measured needs
justify a different architecture.

Read `docs/PRODUCT.md`, `docs/ARCHITECTURE.md`, and `docs/SECURITY.md` before
changing product behavior, authorization, money calculations, or payments.

## Non-negotiable invariants

- Store and calculate money as integer centavos. Never use floating point.
- MXN is the only supported currency until the product scope changes.
- Allocate every centavo deterministically.
- Keep expense history and settlement history separate.
- Treat financial records as immutable; correct them with compensating entries.
- Authenticate and authorize every non-local user or group mutation.
- Make payment commands and provider callbacks authenticated and idempotent.
- Never put secrets or provider credentials in the mobile application or Git.
- Never describe a simulated payment as a real transfer.

## Required verification

For API changes:

```text
cd services/api
go test ./...
go vet ./...
```

For mobile changes:

```text
cd apps/mobile
flutter analyze
flutter test
```

Run the checks relevant to every changed area. Add regression tests for bugs
and tests for important success and failure paths. Report any check that could
not be run.

## Delivery workflow

- Start from a GitHub issue with observable acceptance criteria.
- Keep one concern per branch and pull request.
- Use branch names such as `feature/12-payment-idempotency` or
  `fix/34-balance-rounding`.
- Link the issue from the pull request with `Closes #<issue>` when appropriate.
- Update API, architecture, security, or workflow documentation when behavior
  changes.
- Do not mark work complete until acceptance criteria and relevant checks pass.

When using an AI coding agent, ask it to inspect the relevant code, propose a
short implementation plan, implement only the issue scope, run verification,
and summarize risks and remaining work.
