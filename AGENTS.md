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

## Offline/online parity

The mobile client is offline-first on supported native platforms: local groups
and ledger history live in SQLite (`apps/mobile/lib/src/offline_database.dart`,
`store.dart`) and are usable before sign-in or sync opt-in. Every feature change
must behave consistently in all supported modes: local-only, offline-first, and
signed-in/remote. The web build keeps local data in memory only.

- Implement each user-facing mutation in both the local/offline path and the
  remote path. A mode must never silently no-op or diverge in money math.
- Keep client and server allocation identical: integer centavos, the same split
  methods, and the same deterministic remainder assignment.
- Make new or changed group data round-trip through `ExpenseGroup.toJson`/
  `fromJson`, the SQLite `groups` payload, `_offlineGroupPayload`, and
  `OfflineSyncGroupInput`; add the matching server migration and
  `offline_sync_entries` hash handling.
- Preserve sync semantics: stable local IDs, local-to-server mappings, pending
  edits as `revision > synced_revision`, idempotent retry, and rejection of edits
  to already-synced financial records.
- Keep `load()` merge-safe: pending local groups stay authoritative over server
  copies; server data may overwrite only non-pending groups.
- Any local schema change needs an `OfflineDatabase` version bump and
  `onUpgrade` migration. Never require users to lose offline data.
- State the offline behavior of remote-only concepts (contacts, invitations,
  payment requests, provider callbacks) explicitly: disabled, queued, or
  surfaced as an error. Never present a simulated or offline action as a real
  transfer.
- Update `docs/PRODUCT.md`, `docs/ARCHITECTURE.md`, and `docs/SECURITY.md` when
  offline behavior or sync scope changes.
- Add parity tests for persistence across restart, sign-out/sign-in sync, retry
  idempotency, and pending/conflict merging, in addition to the normal API and
  Flutter suites.

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
