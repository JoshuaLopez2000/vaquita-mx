# CoDi integration strategy

## What CoDi contributes

CoDi is Banco de Mexico's platform for collection and payment messages backed by electronic transfers. A collector generates a request, a payer accepts it using a supported application, and the parties receive confirmation.

Official overview: <https://www.banxico.org.mx/sistemas-de-pago/codi-cobro-digital-banco-me.html>

## Constraint that shapes this repository

CoDi is not treated as an open, self-service API. Banco de Mexico's participation guide states that third-party developers may build collection functionality but must register and certify the development. Payment functionality is made available by SPEI participants.

Official participation guide: <https://www.banxico.org.mx/sistemas-de-pago/d/%7BA21AA19F-C855-9E64-98A4-832D9A51B2B0%7D.pdf>

Consequently:

- The portfolio build uses `SimulatedProvider` and clearly labels it as non-live.
- The app does not imitate a bank or claim to execute a transfer.
- A future `CoDiProvider` will be enabled only after the applicable onboarding, certification, and credentials exist.
- Payment approval remains in a supported financial application.

## Provider contract

The backend owns a narrow `PaymentProvider` interface. Implementations create a collection request and later normalize provider events into internal statuses:

- `PENDING`
- `PAID`
- `EXPIRED`
- `FAILED`

Provider-specific payloads must not leak into expense or ledger modules. Preserve the raw event in protected storage for audit and debugging, while exposing only normalized fields to clients.

## Production integration checklist

Before implementing a live adapter, confirm the then-current requirements directly with Banco de Mexico and legal/compliance advisers:

- Developer or merchant classification.
- Registration and certification process.
- Test and production endpoint access.
- Cryptographic keys, signing, rotation, and custody.
- Message schemas, validation, expiration, and amount limits.
- Callback authentication and retry rules.
- User disclosure, privacy, support, and operational requirements.
- Reconciliation and dispute procedures.

## Demo behavior

The simulator creates a unique request with a 24-hour expiry and a `vaquitamx://` deep link. A later authenticated demo endpoint can transition it to `PAID`, exercising callbacks and ledger settlement without representing a real transfer.
